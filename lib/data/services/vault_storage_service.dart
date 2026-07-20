import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/media_thumbnail_spec.dart';
import 'hide_naming.dart';

/// Manages vault directories:
/// - App-private: thumbs/metadata under documents/vault/
/// - Shared hide root: /storage/emulated/0/.privateheart_vault/ (+ .nomedia)
///
/// See docs/03-architecture/storage-and-hiding.md (dense gallery directory hide).
class VaultStorageService {
  VaultStorageService({this.initializeSharedRoot = true});

  /// Whether this instance may touch Android's shared-storage hide root.
  ///
  /// iOS uses the same app-private vault metadata path but must never probe or
  /// create `/storage/emulated/0/.privateheart_vault`.
  final bool initializeSharedRoot;

  Directory? _vault;
  Directory? _thumbs;
  Directory? _hiddenRoot;

  Future<Directory> ensureVault() async {
    if (_vault != null) return _vault!;
    final docs = await getApplicationDocumentsDirectory();
    final vault = Directory(p.join(docs.path, VaultPaths.vaultDir));
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    final nomedia = File(p.join(vault.path, VaultPaths.nomedia));
    if (!await nomedia.exists()) {
      await nomedia.create();
    }
    final thumbs = Directory(p.join(vault.path, VaultPaths.thumbsDir));
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
    _vault = vault;
    _thumbs = thumbs;
    // Android creates the shared root early so the first hide can use a rename.
    // App-private platforms deliberately skip this probe.
    if (initializeSharedRoot) {
      try {
        await ensureHiddenRoot();
      } catch (e) {
        debugPrint('ensureHiddenRoot: $e');
      }
    }
    return vault;
  }

  Future<Directory> get thumbsDir async {
    await ensureVault();
    return _thumbs!;
  }

  Future<Directory> get vaultDir async => ensureVault();

  Future<Directory> get shareStagingDir async {
    final vault = await ensureVault();
    final directory = Directory(p.join(vault.path, VaultPaths.shareStagingDir));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  /// Shared-storage hide root: `.privateheart_vault` with `.nomedia`.
  Future<Directory> ensureHiddenRoot() async {
    if (!initializeSharedRoot) {
      throw UnsupportedError(
        'Shared-storage vault is disabled for this platform',
      );
    }
    if (_hiddenRoot != null && await _hiddenRoot!.exists()) {
      return _hiddenRoot!;
    }
    // Prefer primary external storage (same volume as DCIM/Download) so move is rename.
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    // getExternalStorageDirectory on Android is often …/Android/data/<pkg>/files
    // Walk up to the emulated root when possible.
    String rootPath;
    if (base != null) {
      final cur = base.path.replaceAll('\\', '/');
      final idx = cur.indexOf('/Android/data/');
      if (idx > 0) {
        rootPath = cur.substring(0, idx);
      } else if (cur.startsWith('/storage/emulated/0')) {
        rootPath = '/storage/emulated/0';
      } else {
        rootPath = cur;
      }
    } else {
      rootPath = '/storage/emulated/0';
    }
    final hidden = Directory(p.join(rootPath, VaultPaths.hiddenRootName));
    if (!await hidden.exists()) {
      await hidden.create(recursive: true);
    }
    final nomedia = File(p.join(hidden.path, VaultPaths.nomedia));
    if (!await nomedia.exists()) {
      await nomedia.create();
    }
    _hiddenRoot = hidden;
    return hidden;
  }

  /// Destination path for a hide move under the .nomedia vault.
  Future<String> hiddenDestPath({
    required String id,
    required String originalName,
    required String? sourceFolder,
  }) async {
    final root = await ensureHiddenRoot();
    final folder = HideNaming.sanitizeFolder(sourceFolder);
    final dir = Directory(p.join(root.path, folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      final nm = File(p.join(dir.path, VaultPaths.nomedia));
      if (!await nm.exists()) await nm.create();
    }
    final safeName = p.basename(originalName).replaceAll(RegExp(r'[\\/]'), '_');
    // Prefix id to avoid collisions when restoring multiple same names.
    final short = id.length >= 8 ? id.substring(0, 8) : id;
    return p.join(dir.path, '${short}_$safeName');
  }

  /// Stream-copy [source] into app-private vault (export/import fallback).
  Future<File> copyIntoVault({
    required File source,
    required String id,
    required String extension,
  }) async {
    final vault = await ensureVault();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final dest = File(p.join(vault.path, '$id$ext'));
    await source.openRead().pipe(dest.openWrite());
    return dest;
  }

  Future<File> writeBytesIntoVault({
    required List<int> bytes,
    required String id,
    required String extension,
  }) async {
    final vault = await ensureVault();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final dest = File(p.join(vault.path, '$id$ext'));
    await dest.writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// App-private media destination used by the iOS Photos adapter. Android's
  /// D5 path continues to use [hiddenDestPath] and the shared `.nomedia` root.
  Future<File> privateMediaFileFor({
    required String id,
    required String originalName,
    String? sourceFolder,
  }) async {
    final vault = await ensureVault();
    final folder = HideNaming.sanitizeFolder(sourceFolder);
    final dir = Directory(p.join(vault.path, VaultPaths.mediaDir, folder));
    await dir.create(recursive: true);
    final safeName = p.basename(originalName).replaceAll(RegExp(r'[\\/]'), '_');
    // Keep the complete transaction id in the filename. A short prefix would
    // make unrelated iOS vault items collide once the library grows.
    return File(p.join(dir.path, '${id}_$safeName'));
  }

  /// Durable staging location for provider/PhotoKit materialization. Staging
  /// files are never treated as source identities and are removed after commit.
  Future<File> stagingFileFor({
    required String id,
    required String originalName,
  }) async {
    final vault = await ensureVault();
    final dir = Directory(p.join(vault.path, VaultPaths.stagingDir));
    await dir.create(recursive: true);
    final safeName = p.basename(originalName).replaceAll(RegExp(r'[\\/]'), '_');
    return File(p.join(dir.path, '$id-$safeName.part'));
  }

  String thumbPathFor(String id) {
    final base =
        _thumbs?.path ?? p.join(VaultPaths.vaultDir, VaultPaths.thumbsDir);
    return p.join(base, MediaThumbnailSpec.fileName(id));
  }

  Future<File> thumbFileFor(String id) async {
    final thumbs = await thumbsDir;
    return File(p.join(thumbs.path, MediaThumbnailSpec.fileName(id)));
  }

  Future<void> deleteMediaFiles({
    required String privatePath,
    String? thumbnailPath,
  }) async {
    try {
      final media = File(privatePath);
      if (await media.exists()) await media.delete();
    } catch (_) {}
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      try {
        final thumb = File(thumbnailPath);
        if (await thumb.exists()) await thumb.delete();
      } catch (_) {}
    }
  }

  /// Deletes iOS restore bytes without hiding cleanup failures.
  ///
  /// The thumbnail is removed first so a failure cannot leave a database row
  /// whose verified media bytes have already disappeared.
  Future<void> deleteMediaFilesStrict({
    required String privatePath,
    String? thumbnailPath,
  }) async {
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      await _deleteFileStrict(File(thumbnailPath));
    }
    await _deleteFileStrict(File(privatePath));
  }

  /// Consumes one app-owned share entry and its now-empty digest directory.
  Future<void> deleteShareStagedSource(String sourcePath) async {
    final root = await shareStagingDir;
    final rootPath = p.canonicalize(root.absolute.path);
    final source = File(sourcePath).absolute;
    final normalizedSource = p.canonicalize(source.path);
    if (!p.isWithin(rootPath, normalizedSource)) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'Share staging cleanup must stay inside ${root.path}',
      );
    }

    await _deleteFileStrict(source);
    final entry = source.parent;
    if (p.equals(entry.path, root.path)) return;
    if (await entry.exists()) {
      final remaining = await entry.list(followLinks: false).toList();
      for (final entity in remaining) {
        if (entity is File && p.basename(entity.path).startsWith('.source-')) {
          await _deleteFileStrict(entity);
        }
      }
      final unexpected = await entry.list(followLinks: false).toList();
      if (unexpected.isNotEmpty) {
        throw StateError(
          'Share staging entry is not empty after consumption: ${entry.path}',
        );
      }
      await entry.delete();
      if (await entry.exists()) {
        throw FileSystemException(
          'Could not remove consumed share staging entry',
          entry.path,
        );
      }
    }
  }

  static Future<void> _deleteFileStrict(File file) async {
    if (await file.exists()) await file.delete();
    if (await file.exists()) {
      throw FileSystemException('Could not delete file', file.path);
    }
  }
}
