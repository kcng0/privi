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
    // Best-effort create shared hide root early.
    try {
      await ensureHiddenRoot();
    } catch (e) {
      debugPrint('ensureHiddenRoot: $e');
    }
    return vault;
  }

  Future<Directory> get thumbsDir async {
    await ensureVault();
    return _thumbs!;
  }

  Future<Directory> get vaultDir async => ensureVault();

  /// Shared-storage hide root: `.privateheart_vault` with `.nomedia`.
  Future<Directory> ensureHiddenRoot() async {
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
}
