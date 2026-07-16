import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../repositories/media_repository.dart';
import 'hide_naming.dart';
import 'import_service.dart';
import 'vault_storage_service.dart';

/// Launch-time integrity: orphans + recycle retention.
class MaintenanceService {
  MaintenanceService({
    required AppDatabase db,
    required MediaRepository media,
    required VaultStorageService storage,
    ImportService? import,
  })  : _db = db,
        _media = media,
        _storage = storage,
        _import = import;

  final AppDatabase _db;
  final MediaRepository _media;
  final VaultStorageService _storage;
  final ImportService? _import;

  /// Returns a short summary for logging/snackbar.
  Future<String> runLaunchMaintenance({required int retentionDays}) async {
    final missing = await _purgeMissingFiles();
    final expired = await _purgeExpiredRecycle(retentionDays);
    final thumbs = await _cleanOrphanThumbs();
    final parts = <String>[];
    if (missing > 0) parts.add('removed $missing missing');
    if (expired > 0) parts.add('purged $expired expired');
    if (thumbs > 0) parts.add('cleared $thumbs orphan thumbs');
    if (parts.isEmpty) return 'ok';
    return parts.join(', ');
  }

  /// Scan parent directories of known vault paths for `*.vid.pg.*` / `*.img.pg.*`
  /// files that have no DB row; re-import them into the vault.
  ///
  /// Returns a short human summary.
  Future<String> scanOrphanHiddenFiles() async {
    final import = _import;
    if (import == null) {
      return 'Import service unavailable';
    }

    final known = await _db.listActivePrivatePaths();
    final knownSet = known.map(_norm).toSet();
    // Also include recycle so we don't double-import soft-deleted.
    final recycle = await _db.watchRecycleBin().first;
    for (final r in recycle) {
      knownSet.add(_norm(r.privatePath));
    }

    final parents = <String>{};
    for (final path in known) {
      final parent = p.dirname(path);
      if (parent.isNotEmpty && parent != '.' && parent != '/') {
        parents.add(parent);
      }
    }
    // Always include common public media roots when present.
    for (final extra in const [
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/.privateheart_vault',
    ]) {
      if (Directory(extra).existsSync()) parents.add(extra);
    }
    // Nested folders under hide root.
    try {
      final root = Directory('/storage/emulated/0/.privateheart_vault');
      if (await root.exists()) {
        await for (final ent in root.list(followLinks: false)) {
          if (ent is Directory) parents.add(ent.path);
        }
      }
    } catch (_) {}

    final candidates = <ImportSource>[];
    for (final dirPath in parents) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final ent in dir.list(followLinks: false)) {
          if (ent is! File) continue;
          final path = ent.path;
          if (!HideNaming.isHiddenPath(path)) continue;
          if (knownSet.contains(_norm(path))) continue;
          if (!await ent.exists()) continue;
          final isVideo = path.contains(HideNaming.videoMarker) ||
              path.toLowerCase().endsWith('.mp4') ||
              path.toLowerCase().endsWith('.mkv') ||
              path.toLowerCase().endsWith('.webm');
          candidates.add(
            ImportSource(
              path: path,
              name: HideNaming.displayName(path),
              mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
              sourceFolderName: p.basename(dirPath),
            ),
          );
        }
      } catch (e) {
        debugPrint('orphan scan dir $dirPath: $e');
      }
    }

    if (candidates.isEmpty) {
      return 'No orphan hidden files found';
    }

    final progress = await import.importAll(candidates);
    return 'Re-indexed ${progress.imported} '
        '(skipped ${progress.skipped}, failed ${progress.failed})';
  }

  static String _norm(String path) {
    var s = path.replaceAll('\\', '/');
    if (s.length > 1 && s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// Rows whose media file is gone → drop row (and thumb).
  Future<int> _purgeMissingFiles() async {
    final active = await _db.watchActiveMedia().first;
    final deleted = await _db.watchRecycleBin().first;
    var n = 0;
    for (final r in [...active, ...deleted]) {
      if (!File(r.privatePath).existsSync()) {
        try {
          await _media.hardDeleteRowOnly(r.id);
          final t = r.thumbnailPath;
          if (t != null && t.isNotEmpty) {
            final f = File(t);
            if (await f.exists()) await f.delete();
          }
          n++;
        } catch (e) {
          debugPrint('missing purge: $e');
        }
      }
    }
    return n;
  }

  Future<int> _purgeExpiredRecycle(int retentionDays) async {
    if (retentionDays <= 0) return 0;
    final bin = await _db.watchRecycleBin().first;
    final cutoff =
        DateTime.now().toUtc().subtract(Duration(days: retentionDays));
    var n = 0;
    for (final r in bin) {
      final del = r.deletedAt;
      if (del != null && del.isBefore(cutoff)) {
        try {
          await _media.purge(r.id);
          n++;
        } catch (e) {
          debugPrint('retention purge: $e');
        }
      }
    }
    return n;
  }

  Future<int> _cleanOrphanThumbs() async {
    try {
      final thumbs = await _storage.thumbsDir;
      if (!await thumbs.exists()) return 0;
      final rows = [
        ...await _db.watchActiveMedia().first,
        ...await _db.watchRecycleBin().first,
      ];
      final used = <String>{
        for (final r in rows)
          if (r.thumbnailPath != null) r.thumbnailPath!,
      };
      var n = 0;
      await for (final ent in thumbs.list()) {
        if (ent is! File) continue;
        if (!used.contains(ent.path)) {
          await ent.delete();
          n++;
        }
      }
      return n;
    } catch (e) {
      debugPrint('orphan thumbs: $e');
      return 0;
    }
  }
}
