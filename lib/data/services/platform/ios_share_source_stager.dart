import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../application/platform/share_source_stager.dart';
import '../import/import_models.dart';
import '../vault_storage_service.dart';

/// Moves App Group share attachments into an app-private, restart-safe queue.
final class IosShareSourceStager implements ShareSourceStager {
  IosShareSourceStager({
    required VaultStorageService storage,
    Uuid? uuid,
  })  : _storage = storage,
        _uuid = uuid ?? const Uuid();

  final VaultStorageService _storage;
  final Uuid _uuid;

  static const _temporaryDirectoryPrefix = '.tmp-';
  static const _sourceReceiptPrefix = '.source-';

  @override
  Future<List<ImportSource>> recoverPending() async {
    final root = await _storage.shareStagingDir;
    final recovered = <ImportSource>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      if (p.basename(entity.path).startsWith(_temporaryDirectoryPrefix)) {
        // A temp directory contains no committed source. It is safe to remove
        // after a process crash, while final digest directories remain durable.
        await entity.delete(recursive: true);
        continue;
      }
      final staged = await _existingSource(entity);
      if (staged == null) continue;
      final file = File(staged.path);
      recovered.add(
        ImportSource(
          path: file.path,
          name: p.basename(file.path),
          deleteAfterImport: true,
        ),
      );
    }
    recovered.sort((left, right) => left.path.compareTo(right.path));
    return List.unmodifiable(recovered);
  }

  @override
  Future<List<ImportSource>> stage(List<ImportSource> sources) async {
    final stagedByPath = <String, ImportSource>{};
    final incomingFiles = <File>{};
    final root = await _storage.shareStagingDir;
    for (final source in sources) {
      final input = File(_filePath(source.path));
      late final ImportSource staged;
      var consumeInput = false;
      if (await input.exists()) {
        final sourceLength = await input.length();
        if (sourceLength <= 0) {
          throw FileSystemException(
            'Shared iOS attachment is empty',
            source.path,
          );
        }

        final digest = await _digest(input);
        final finalDirectory = Directory(p.join(root.path, digest));
        final existing = await _existingSource(finalDirectory);
        if (existing != null) {
          staged = _stagedSource(path: existing.path, source: source);
        } else {
          staged = await _createStagedSource(
            root: root,
            finalDirectory: finalDirectory,
            input: input,
            source: source,
            sourceLength: sourceLength,
            digest: digest,
          );
        }
        await _writeSourceReceipt(
          directory: Directory(p.dirname(staged.path)),
          sourcePath: input.path,
        );
        consumeInput = !_sameFile(input.path, staged.path);
      } else {
        final recovered = await _findBySourceReceipt(root, input.path);
        if (recovered == null) {
          throw FileSystemException(
            'Shared iOS attachment is not a readable file and has no '
            'durable staging receipt',
            source.path,
          );
        }
        staged = _stagedSource(path: recovered.path, source: source);
      }

      if (consumeInput) incomingFiles.add(input);
      final thumbnail = source.temporaryThumbnailPath;
      if (thumbnail != null && thumbnail.trim().isNotEmpty) {
        incomingFiles.add(File(_filePath(thumbnail)));
      }
      stagedByPath[staged.path] = staged;
    }

    // Do not consume any provider input until every attachment has a verified
    // durable copy. A later attachment failure must leave the whole share
    // retryable, including files already processed in this call.
    for (final input in incomingFiles) {
      await _deleteIncomingFile(input);
    }
    return List.unmodifiable(stagedByPath.values);
  }

  Future<ImportSource> _createStagedSource({
    required Directory root,
    required Directory finalDirectory,
    required File input,
    required ImportSource source,
    required int sourceLength,
    required String digest,
  }) async {
    final temporaryDirectory = Directory(
      p.join(root.path, '$_temporaryDirectoryPrefix${_uuid.v4()}'),
    );
    await temporaryDirectory.create(recursive: false);
    try {
      final originalName = _safeName(source.name, input.path);
      final output = File(p.join(temporaryDirectory.path, originalName));
      await input.openRead().pipe(output.openWrite());
      if (await output.length() != sourceLength ||
          await _digest(output) != digest) {
        throw StateError('iOS share staging verification failed');
      }
      try {
        await temporaryDirectory.rename(finalDirectory.path);
        return _stagedSource(
          path: p.join(finalDirectory.path, originalName),
          source: source,
        );
      } on FileSystemException {
        final concurrent = await _existingSource(finalDirectory);
        if (concurrent == null) rethrow;
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
        return _stagedSource(path: concurrent.path, source: source);
      }
    } catch (_) {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<ImportSource?> _existingSource(Directory directory) async {
    if (!await directory.exists()) return null;
    final files = <File>[];
    await for (final child in directory.list(followLinks: false)) {
      if (child is File && !_isReceipt(child.path)) files.add(child);
    }
    if (files.length != 1 || await files.single.length() <= 0) {
      throw StateError(
        'Invalid existing iOS share staging entry: ${directory.path}',
      );
    }
    final file = files.single;
    final expectedDigest = p.basename(directory.path);
    if (await _digest(file) != expectedDigest) {
      throw StateError(
        'iOS share staging digest mismatch: ${directory.path}',
      );
    }
    return _stagedSource(path: file.path);
  }

  Future<void> _writeSourceReceipt({
    required Directory directory,
    required String sourcePath,
  }) async {
    final receipt = File(
      p.join(directory.path, '$_sourceReceiptPrefix${_pathDigest(sourcePath)}'),
    );
    if (!await receipt.exists()) {
      await receipt.writeAsString('', flush: true);
    }
  }

  Future<ImportSource?> _findBySourceReceipt(
    Directory root,
    String sourcePath,
  ) async {
    final receiptName = '$_sourceReceiptPrefix${_pathDigest(sourcePath)}';
    ImportSource? match;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          p.basename(entity.path).startsWith(_temporaryDirectoryPrefix)) {
        continue;
      }
      final receipt = File(p.join(entity.path, receiptName));
      if (!await receipt.exists()) continue;
      final staged = await _existingSource(entity);
      if (staged == null) continue;
      if (match != null && match.path != staged.path) {
        throw StateError('Multiple iOS share staging receipts for $sourcePath');
      }
      match = staged;
    }
    return match;
  }

  static bool _isReceipt(String path) =>
      p.basename(path).startsWith(_sourceReceiptPrefix);

  static bool _sameFile(String left, String right) =>
      p.equals(File(left).absolute.path, File(right).absolute.path);

  static String _pathDigest(String path) =>
      base64UrlEncode(sha256.convert(utf8.encode(path)).bytes);

  Future<void> _deleteIncomingFile(File file) async {
    if (!await file.exists()) return;
    await file.delete();
    if (await file.exists()) {
      throw FileSystemException(
        'Could not consume shared iOS attachment',
        file.path,
      );
    }
  }

  static String _filePath(String path) {
    final value = path.trim();
    if (value.startsWith('file:')) return Uri.parse(value).toFilePath();
    return value;
  }

  static String _safeName(String? requested, String sourcePath) {
    final candidate = p.basename(
      requested?.trim().isNotEmpty == true ? requested!.trim() : sourcePath,
    );
    final sanitized = candidate.replaceAll(RegExp(r'[\\/]'), '_');
    return sanitized.isEmpty ? 'shared-media' : sanitized;
  }

  static Future<String> _digest(File file) async {
    final hash = await sha256.bind(file.openRead()).first;
    return base64UrlEncode(hash.bytes);
  }

  static ImportSource _stagedSource({
    required String path,
    ImportSource? source,
  }) {
    return ImportSource(
      path: path,
      name: p.basename(path),
      mimeType: source?.mimeType,
      sourceFolderName: source?.sourceFolderName,
      dateTaken: source?.dateTaken,
      deleteAfterImport: true,
    );
  }
}
