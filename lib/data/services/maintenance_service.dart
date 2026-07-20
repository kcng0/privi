import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../application/platform/vault_workflow.dart';
import '../../core/constants.dart';
import '../../domain/models/media_item.dart';
import '../db/database.dart';
import '../repositories/album_repository.dart';
import '../repositories/media_repository.dart';
import 'hide_naming.dart';
import 'media_rename_service.dart';
import 'media_store_service.dart';
import 'vault_storage_service.dart';

/// Result of reinstall / orphan vault recovery.
enum VaultRecoveryStatus { noFiles, reindexed, restoredToGallery }

class VaultRecoveryResult {
  const VaultRecoveryResult({
    required this.reindexed,
    required this.skipped,
    required this.failed,
    required this.status,
  });

  final int reindexed;
  final int skipped;
  final int failed;
  final VaultRecoveryStatus status;
}

class CaptureDateRepairResult {
  const CaptureDateRepairResult({
    required this.fixed,
    required this.skipped,
    required this.failed,
    required this.hadMedia,
  });

  final int fixed;
  final int skipped;
  final int failed;
  final bool hadMedia;
}

/// Launch-time integrity: orphans + recycle retention + reinstall recovery.
class MaintenanceService {
  MaintenanceService({
    required AppDatabase db,
    required MediaRepository media,
    required VaultStorageService storage,
    required AlbumRepository albums,
    VaultWorkflow? import,
    MediaRenameService? renamer,
    MediaStoreService? mediaStore,
    Uuid? uuid,
    bool sharedStorageEnabled = true,
  })  : _db = db,
        _media = media,
        _storage = storage,
        _albums = albums,
        _import = import,
        _renamer = renamer ?? MediaRenameService(),
        _mediaStore = mediaStore ?? MediaStoreService(),
        _uuid = uuid ?? const Uuid(),
        _sharedStorageEnabled = sharedStorageEnabled;

  final AppDatabase _db;
  final MediaRepository _media;
  final VaultStorageService _storage;
  final AlbumRepository _albums;
  final VaultWorkflow? _import;
  final MediaRenameService _renamer;
  final MediaStoreService _mediaStore;
  final Uuid _uuid;
  final bool _sharedStorageEnabled;

  /// Returns a short summary for logging/snackbar.
  Future<String> runLaunchMaintenance({required int retentionDays}) async {
    final accessible = await _vaultAccessible();
    final missing = accessible ? await _purgeMissingFiles() : 0;
    final expired = accessible ? await _purgeExpiredRecycle(retentionDays) : 0;
    final videoThumbnails = accessible && _import != null
        ? await _import.repairOutdatedVideoThumbnails()
        : 0;
    final thumbs = await _cleanOrphanThumbs();
    final parts = <String>[];
    if (!accessible) parts.add('skipped (no storage access)');
    if (missing > 0) parts.add('removed $missing missing');
    if (expired > 0) parts.add('purged $expired expired');
    if (videoThumbnails > 0) {
      parts.add('upgraded $videoThumbnails video thumbnails');
    }
    if (thumbs > 0) parts.add('cleared $thumbs orphan thumbs');
    if (parts.isEmpty) return 'ok';
    return parts.join(', ');
  }

  Future<bool> _vaultAccessible() async {
    if (!_sharedStorageEnabled) {
      try {
        final root = await _storage.ensureVault();
        await root.list(followLinks: false).first.timeout(
              const Duration(seconds: 3),
            );
        return true;
      } on StateError {
        return true;
      } catch (error) {
        debugPrint('app-private vault accessibility probe: $error');
        return false;
      }
    }
    if (!await _renamer.isExternalStorageManager()) return false;
    try {
      final root = await _storage.ensureHiddenRoot();
      await root.list(followLinks: false).first.timeout(
            const Duration(seconds: 3),
          );
      return true;
    } on StateError {
      return true;
    } catch (e) {
      debugPrint('vault accessibility probe: $e');
      return false;
    }
  }

  /// Scan parent directories of known vault paths for legacy markers + vault root
  /// files missing from the library DB; re-index them.
  ///
  /// Safe after reinstall (DB empty, files still under `.privateheart_vault`).
  Future<VaultRecoveryResult> scanOrphanHiddenFiles() =>
      recoverVaultFiles(alsoUnhide: false);

  /// Reinstall recovery: walk the shared hide root + legacy marker files,
  /// insert missing DB rows (files stay in vault). Optionally unhide to Gallery.
  ///
  /// Unlike hide, this does **not** move files — they are already vaulted.
  Future<VaultRecoveryResult> recoverVaultFiles({
    bool alsoUnhide = false,
  }) async {
    final known = await _db.listActivePrivatePaths();
    final knownSet = known.map(_norm).toSet();
    // Also include recycle so we don't double-import soft-deleted.
    final recycle = await _db.watchRecycleBin().first;
    for (final r in recycle) {
      knownSet.add(_norm(r.privatePath));
    }

    final candidates = await _discoverOrphanFiles(knownSet);
    if (candidates.isEmpty) {
      return const VaultRecoveryResult(
        reindexed: 0,
        skipped: 0,
        failed: 0,
        status: VaultRecoveryStatus.noFiles,
      );
    }

    var reindexed = 0;
    var skipped = 0;
    var failed = 0;
    final pending = <({MediaItem item, String? userAlbumId})>[];
    final unhideItems = <MediaItem>[];

    for (final c in candidates) {
      try {
        final file = File(c.path);
        if (!await file.exists()) {
          skipped++;
          continue;
        }
        final len = await file.length();
        if (len <= 0) {
          skipped++;
          continue;
        }

        // Already in vault with a DB row? (race / path variant)
        if (await _media.existsByPrivatePath(c.path)) {
          skipped++;
          continue;
        }

        final id = _uuid.v4();
        final isVideo = c.isVideo;
        final folder = c.folderName;
        final album = await _albums.getOrCreateUserAlbumByName(folder);
        final name = HideNaming.displayName(c.name);

        // Prefer keeping file where it is (vault path). Only move if legacy
        // marker still lives outside the hide root.
        var privatePath = c.path;
        if (!HideNaming.isHiddenVaultPath(c.path) &&
            HideNaming.isLegacyMarkerPath(c.path)) {
          // Leave legacy markers in place for reveal; record as-is.
          privatePath = c.path;
        }

        // Reinstall recovery: resolve real capture time from vault file (EXIF /
        // video metadata). Never invent "now" as dateTaken.
        DateTime? dateTaken;
        if (_sharedStorageEnabled) {
          try {
            final sec = await _mediaStore.resolveCaptureDateSec(
              path: privatePath,
              isVideo: isVideo,
            );
            if (sec != null && sec > 0) {
              dateTaken = DateTime.fromMillisecondsSinceEpoch(
                sec * 1000,
                isUtc: true,
              );
            }
          } catch (e, stackTrace) {
            debugPrint('recover capture date ${c.path}: $e\n$stackTrace');
          }
        }
        final sortKey = dateTaken ?? DateTime.utc(1970);
        final item = MediaItem(
          id: id,
          privatePath: privatePath,
          originalPath: null,
          originalName: name,
          mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
          isVideo: isVideo,
          width: null,
          height: null,
          durationMs: null,
          rating: 0,
          dateAdded: sortKey,
          dateTaken: dateTaken,
          sizeBytes: len,
          thumbnailPath: null,
        );
        pending.add((item: item, userAlbumId: album.id));
        if (alsoUnhide) unhideItems.add(item);
        knownSet.add(_norm(privatePath));
        reindexed++;
      } catch (e) {
        debugPrint('recover item ${c.path}: $e');
        failed++;
      }
    }

    if (pending.isNotEmpty) {
      try {
        await _media.insertMany(pending);
      } catch (e) {
        debugPrint('recover batch insert: $e');
        for (final e2 in pending) {
          try {
            await _media.insert(e2.item, userAlbumId: e2.userAlbumId);
          } catch (err) {
            debugPrint('recover single insert: $err');
            failed++;
            reindexed = (reindexed - 1).clamp(0, reindexed);
          }
        }
      }
    }

    if (alsoUnhide && unhideItems.isNotEmpty) {
      final import = _import;
      if (import != null) {
        var unhid = 0;
        for (final item in unhideItems) {
          try {
            final ok = await import.reveal(item, clearGalleryCache: false);
            if (ok) unhid++;
          } catch (e) {
            debugPrint('recover unhide ${item.id}: $e');
            failed++;
          }
        }
        if (_sharedStorageEnabled) {
          try {
            await _mediaStore.scanPath(
              HideNaming.defaultRestoreDir,
            );
          } catch (e, stackTrace) {
            debugPrint('recover gallery scan: $e\n$stackTrace');
          }
        }
        return VaultRecoveryResult(
          reindexed: unhid,
          skipped: skipped,
          failed: failed,
          status: VaultRecoveryStatus.restoredToGallery,
        );
      }
    }

    return VaultRecoveryResult(
      reindexed: reindexed,
      skipped: skipped,
      failed: failed,
      status: VaultRecoveryStatus.reindexed,
    );
  }

  /// Repair vault sort/capture dates from real capture metadata.
  ///
  /// For each active vault item, resolves capture time via MediaStore DATE_TAKEN
  /// → EXIF → video metadata (never filesystem mtime). Updates [dateTaken] and
  /// [dateAdded] only when a real capture time is found.
  ///
  /// Safe after older hides that stored hide-time as dateAdded.
  Future<CaptureDateRepairResult> repairCaptureDates() async {
    final rows = await _media.listActive();
    if (rows.isEmpty) {
      return const CaptureDateRepairResult(
        fixed: 0,
        skipped: 0,
        failed: 0,
        hadMedia: false,
      );
    }
    if (!_sharedStorageEnabled) {
      // The existing repair source is Android MediaStore/EXIF. iOS capture
      // dates are persisted while PhotoKit still owns the source asset.
      return CaptureDateRepairResult(
        fixed: 0,
        skipped: rows.length,
        failed: 0,
        hadMedia: true,
      );
    }
    var fixed = 0;
    var skipped = 0;
    var failed = 0;
    for (final item in rows) {
      try {
        final sec = await _mediaStore.resolveCaptureDateSec(
          path: item.privatePath,
          isVideo: item.isVideo,
        );
        if (sec == null || sec <= 0) {
          skipped++;
          continue;
        }
        final taken = DateTime.fromMillisecondsSinceEpoch(
          sec * 1000,
          isUtc: true,
        );
        // Skip no-op when already correct (within 1s).
        final existing = item.dateTaken?.toUtc();
        final added = item.dateAdded.toUtc();
        if (existing != null &&
            (existing.difference(taken).inSeconds).abs() <= 1 &&
            (added.difference(taken).inSeconds).abs() <= 1) {
          skipped++;
          continue;
        }
        await _media.updateDates(
          item.id,
          dateTaken: taken,
          dateAdded: taken,
        );
        fixed++;
      } catch (e) {
        debugPrint('repairCaptureDates ${item.id}: $e');
        failed++;
      }
    }
    return CaptureDateRepairResult(
      fixed: fixed,
      skipped: skipped,
      failed: failed,
      hadMedia: true,
    );
  }

  Future<List<_OrphanCandidate>> _discoverOrphanFiles(
    Set<String> knownSet,
  ) async {
    if (!_sharedStorageEnabled) {
      return _discoverAppPrivateOrphanFiles(knownSet);
    }
    final parents = <String>{};

    // Always scan the shared hide root (reinstall case: DB empty).
    try {
      final root = await _storage.ensureHiddenRoot();
      parents.add(root.path);
      if (await root.exists()) {
        await for (final ent in root.list(followLinks: false)) {
          if (ent is Directory) parents.add(ent.path);
        }
      }
    } catch (e) {
      debugPrint('ensureHiddenRoot: $e');
      const fallback = '/storage/emulated/0/${VaultPaths.hiddenRootName}';
      if (Directory(fallback).existsSync()) {
        parents.add(fallback);
        try {
          await for (final ent
              in Directory(fallback).list(followLinks: false)) {
            if (ent is Directory) parents.add(ent.path);
          }
        } catch (fallbackError, stackTrace) {
          debugPrint(
            'fallback vault scan: $fallbackError\n$stackTrace',
          );
        }
      }
    }

    // Legacy marker roots (older hides).
    for (final extra in const [
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/storage/emulated/0/Movies',
    ]) {
      if (Directory(extra).existsSync()) parents.add(extra);
    }

    final out = <_OrphanCandidate>[];
    for (final dirPath in parents) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final ent in dir.list(followLinks: false)) {
          if (ent is! File) continue;
          final path = ent.path;
          final base = p.basename(path);
          if (base == VaultPaths.nomedia || base == '.' || base == '..') {
            continue;
          }

          final inVault = HideNaming.isHiddenVaultPath(path);
          final legacy = HideNaming.isLegacyMarkerPath(path);
          // Vault root: any media file under .privateheart_vault.
          // Outside vault: only legacy marker names.
          if (!inVault && !legacy) continue;
          if (inVault && !_looksLikeMedia(base)) continue;
          if (knownSet.contains(_norm(path))) continue;
          if (!await ent.exists()) continue;

          final isVideo = _isVideoName(path);

          // Folder label for Invisible album.
          var folder = p.basename(dirPath);
          if (folder == VaultPaths.hiddenRootName || folder.startsWith('.')) {
            folder = 'Recovered';
          }
          if (folder.toLowerCase() == 'download') folder = 'Downloads';

          out.add(
            _OrphanCandidate(
              path: path,
              name: HideNaming.displayName(path),
              isVideo: isVideo,
              folderName: folder,
            ),
          );
        }
      } catch (e) {
        debugPrint('orphan scan dir $dirPath: $e');
      }
    }
    return out;
  }

  Future<List<_OrphanCandidate>> _discoverAppPrivateOrphanFiles(
    Set<String> knownSet,
  ) async {
    final vault = await _storage.ensureVault();
    final mediaRoot = Directory(p.join(vault.path, VaultPaths.mediaDir));
    if (!await mediaRoot.exists()) return const [];

    final out = <_OrphanCandidate>[];
    await for (final entity in mediaRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final path = entity.path;
      final name = p.basename(path);
      if (!_looksLikeMedia(name) || knownSet.contains(_norm(path))) continue;
      out.add(
        _OrphanCandidate(
          path: path,
          name: HideNaming.displayName(name),
          isVideo: _isVideoName(name),
          folderName: HideNaming.sanitizeFolder(p.basename(entity.parent.path)),
        ),
      );
    }
    return out;
  }

  static bool _looksLikeMedia(String name) {
    final lower = name.toLowerCase();
    const exts = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.heic',
      '.heif',
      '.mp4',
      '.mov',
      '.mkv',
      '.webm',
      '.3gp',
      '.avi',
      '.m4v',
    };
    for (final e in exts) {
      if (lower.endsWith(e)) return true;
    }
    return HideNaming.isLegacyMarkerPath(name);
  }

  static bool _isVideoName(String path) {
    final lower = path.toLowerCase();
    if (path.contains(HideNaming.videoMarker)) return true;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.m4v');
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
      final file = File(r.privatePath);
      if (!file.existsSync() && await _directoryAccessible(file.parent)) {
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

  Future<bool> _directoryAccessible(Directory directory) async {
    if (!await directory.exists()) return false;
    try {
      await directory.list(followLinks: false).first.timeout(
            const Duration(seconds: 3),
          );
      return true;
    } on StateError {
      return true;
    } catch (e) {
      debugPrint('directory accessibility probe (${directory.path}): $e');
      return false;
    }
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

class _OrphanCandidate {
  const _OrphanCandidate({
    required this.path,
    required this.name,
    required this.isVideo,
    required this.folderName,
  });

  final String path;
  final String name;
  final bool isVideo;
  final String folderName;
}
