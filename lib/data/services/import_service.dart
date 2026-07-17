import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/media_item.dart';
import '../repositories/album_repository.dart';
import '../repositories/media_repository.dart';
import 'hide_naming.dart';
import 'media_rename_service.dart';
import 'media_store_service.dart';
import 'vault_storage_service.dart';

/// Source for a hide operation (real file path preferred).
class ImportSource {
  const ImportSource({
    required this.path,
    this.name,
    this.mimeType,
    this.contentUri,
    this.assetId,
    this.sourceFolderName,
    this.dateTaken,
  });

  final String path;
  final String? name;
  final String? mimeType;
  final String? contentUri;
  final String? assetId;
  final String? sourceFolderName;

  /// Original capture/create time from MediaStore (or file mtime).
  /// Preserved across hide so Invisible "Newest first" matches Visible.
  final DateTime? dateTaken;
}

class ImportProgress {
  const ImportProgress({
    required this.done,
    required this.total,
    this.currentName,
    this.cancelled = false,
    this.imported = 0,
    this.skipped = 0,
    this.failed = 0,
    this.removalFailed = 0,
    this.statusMessage,
    this.lastError,
  });

  final int done;
  final int total;
  final String? currentName;
  final bool cancelled;
  final int imported;
  final int skipped;
  final int failed;
  final int removalFailed;
  final String? statusMessage;
  final String? lastError;

  double get fraction => total == 0 ? 0 : done / total;
}

/// Prepared hide job (paths resolved, dest ready) before native transfer.
class _PreparedHide {
  _PreparedHide({
    required this.id,
    required this.src,
    required this.originalPath,
    required this.originalName,
    required this.mime,
    required this.isVideo,
    required this.destPath,
    required this.folderName,
    required this.albumId,
    this.dateTaken,
  });

  final String id;
  final ImportSource src;
  final String originalPath;
  final String originalName;
  final String mime;
  final bool isVideo;
  final String destPath;
  final String folderName;
  final String? albumId;

  /// Original capture/create time (not hide time).
  final DateTime? dateTaken;
}

/// Hide via native atomic rename (prefer) / batch IPC.
///
/// Cancel is cooperative: checked between prep steps and **between native
/// chunks**. A single in-flight native chunk cannot be aborted mid-call, so
/// chunk size stays small enough that Cancel still feels responsive.
class ImportService {
  ImportService({
    required VaultStorageService storage,
    required MediaRepository mediaRepository,
    required AlbumRepository albumRepository,
    MediaRenameService? renamer,
    MediaStoreService? mediaStore,
    Uuid? uuid,
  })  : _storage = storage,
        _media = mediaRepository,
        _albums = albumRepository,
        _renamer = renamer ?? MediaRenameService(),
        _mediaStore = mediaStore ?? MediaStoreService(),
        _uuid = uuid ?? const Uuid();

  final VaultStorageService _storage;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final MediaRenameService _renamer;
  final MediaStoreService _mediaStore;
  final Uuid _uuid;
  final Map<String, String> _folderAlbumCache = {};

  bool _cancelRequested = false;

  void cancel() => _cancelRequested = true;

  /// Clear cancel for a new session. Prefer [ImportController.beginSession].
  void resetCancel() => _cancelRequested = false;

  bool get isCancelRequested => _cancelRequested;

  /// Native items processed per MethodChannel call.
  ///
  /// Small enough that Cancel is noticed within ~one chunk of renames, and a
  /// single bad video cannot stall the whole batch for minutes.
  static const int nativeBatchChunk = 8;

  /// How many deferred thumbs to generate at once (post-insert, best-effort).
  static const int thumbConcurrency = 2;

  static Future<T> _withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
    required String label,
  }) {
    return future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(label, timeout),
    );
  }

  Future<ImportProgress> importAll(
    List<ImportSource> sources, {
    void Function(ImportProgress progress)? onProgress,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,

    /// Extra cancel probe (controller session flag). OR'd with [cancel].
    bool Function()? isCancelRequested,
  }) async {
    // Do NOT clear cancel here — caller may have requested cancel during
    // path resolve before importAll starts. Use resetCancel()/beginSession.
    _folderAlbumCache.clear();
    var imported = 0;
    var skipped = 0;
    var failed = 0;
    var completed = 0;
    String? lastError;
    String? currentName;
    final total = sources.length;

    bool cancelledNow() =>
        _cancelRequested || (isCancelRequested?.call() ?? false);

    void emit({
      String? statusMessage,
      bool cancelled = false,
    }) {
      onProgress?.call(
        ImportProgress(
          done: completed,
          total: total,
          currentName: currentName,
          imported: imported,
          skipped: skipped,
          failed: failed,
          cancelled: cancelled || cancelledNow(),
          statusMessage: statusMessage,
        ),
      );
    }

    ImportProgress cancelledProgress() => ImportProgress(
          done: completed,
          total: total,
          cancelled: true,
          imported: imported,
          skipped: skipped,
          failed: failed,
          lastError: lastError,
          statusMessage: 'Cancelled',
        );

    if (cancelledNow()) {
      emit(statusMessage: 'Cancelled', cancelled: true);
      return cancelledProgress();
    }

    if (total == 0) {
      const empty = ImportProgress(
        done: 0,
        total: 0,
        statusMessage: 'Done',
      );
      onProgress?.call(empty);
      return empty;
    }

    // Pre-resolve mirror albums serially so concurrent hides never race-create
    // the same user album.
    if (targetUserAlbumId == null) {
      final folders = <String>{};
      for (final src in sources) {
        final folder = (src.sourceFolderName ??
                defaultSourceFolderName ??
                _folderNameFromPath(src.path))
            .trim();
        if (folder.isNotEmpty) folders.add(folder);
      }
      for (final folder in folders) {
        if (cancelledNow()) {
          emit(statusMessage: 'Cancelled', cancelled: true);
          return cancelledProgress();
        }
        await _resolveMirrorAlbumId(folder);
      }
    }

    emit(statusMessage: total <= 1 ? 'Hiding…' : 'Hiding…');

    // ── Phase 1: prepare dest paths (cancelable per item) ───────────
    final prepared = <_PreparedHide>[];
    for (var i = 0; i < sources.length; i++) {
      if (cancelledNow()) {
        // Remaining unprepared sources count as not-done (user cancelled).
        emit(statusMessage: 'Cancelled', cancelled: true);
        return cancelledProgress();
      }
      final src = sources[i];
      final name = src.name ?? p.basename(src.path);
      currentName = name;
      emit(statusMessage: 'Hiding…');

      try {
        final job = await _prepareHide(
          src,
          targetUserAlbumId: targetUserAlbumId,
          defaultSourceFolderName: defaultSourceFolderName,
        );
        if (job == null) {
          skipped++;
          completed++;
          emit(statusMessage: 'Hiding…');
          continue;
        }
        prepared.add(job);
      } catch (e, st) {
        debugPrint('prepare hide failed: $e\n$st');
        failed++;
        lastError = e.toString();
        completed++;
        emit(statusMessage: 'Hiding…');
      }
    }

    if (cancelledNow()) {
      emit(statusMessage: 'Cancelled', cancelled: true);
      return cancelledProgress();
    }

    // ── Phase 2: native batch moves in cancelable chunks ────────────
    final pendingDb = <({MediaItem item, String? userAlbumId})>[];
    final thumbJobs = <_ThumbJob>[];

    for (var offset = 0; offset < prepared.length; offset += nativeBatchChunk) {
      if (cancelledNow()) {
        // Flush any already-moved rows so partial work is durable.
        if (pendingDb.isNotEmpty) {
          await _flushDb(pendingDb);
          pendingDb.clear();
        }
        emit(statusMessage: 'Cancelled', cancelled: true);
        return cancelledProgress();
      }

      final end = offset + nativeBatchChunk > prepared.length
          ? prepared.length
          : offset + nativeBatchChunk;
      final chunk = prepared.sublist(offset, end);
      currentName = chunk.isEmpty ? null : chunk.last.originalName;
      emit(statusMessage: 'Hiding…');

      final requests = [
        for (final job in chunk)
          MediaHideRequest(
            clientId: job.id,
            path: job.originalPath,
            mediaId: job.src.assetId,
            newPath: job.destPath,
            isVideo: job.isVideo,
          ),
      ];

      List<MediaRenameResult> results;
      try {
        // Cap batch wait: cancel can only take effect after this returns.
        // Atomic renames should finish well under this; copies of huge videos
        // fall through to per-item with shorter individual timeouts.
        results = await _withTimeout(
          _renamer.hideToVaultBatch(requests),
          timeout: Duration(seconds: 20 + chunk.length * 5),
          label: 'hide batch timed out (${chunk.length} items)',
        );
      } catch (e, st) {
        debugPrint('hide batch failed: $e\n$st');
        results = [];
      }

      // If batch returned fewer results than requested (or timed out empty),
      // finish remaining items one-by-one. First recover any dest already
      // written by a timed-out native batch (no double-move).
      final byId = <String, MediaRenameResult>{};
      for (final r in results) {
        final id = r.clientId;
        if (id != null) byId[id] = r;
      }
      for (var i = 0; i < chunk.length && i < results.length; i++) {
        byId.putIfAbsent(chunk[i].id, () => results[i]);
      }

      for (final job in chunk) {
        if (cancelledNow()) break;

        var native = byId[job.id];
        // Recover: native batch may have moved the file before Dart timed out.
        if (native == null || !native.ok) {
          final recovered = await _recoverExistingDest(job.destPath);
          if (recovered != null) {
            native = MediaRenameResult(
              ok: true,
              newPath: job.destPath,
              size: recovered,
              clientId: job.id,
              method: 'recovered',
            );
          } else if (native == null || !native.ok) {
            // Per-item fallback for this job only.
            try {
              final one = await _withTimeout(
                _renamer.hideToVault(
                  path: job.originalPath,
                  mediaId: job.src.assetId,
                  newPath: job.destPath,
                  isVideo: job.isVideo,
                ),
                timeout: const Duration(seconds: 30),
                label: 'hide timed out: ${job.originalName}',
              );
              native = MediaRenameResult(
                ok: one.ok,
                newPath: one.newPath,
                error: one.error,
                needManageStorage: one.needManageStorage,
                size: one.size,
                clientId: job.id,
                method: one.method,
              );
              // Second recovery if timed out mid-move.
              if (!native.ok) {
                final again = await _recoverExistingDest(job.destPath);
                if (again != null) {
                  native = MediaRenameResult(
                    ok: true,
                    newPath: job.destPath,
                    size: again,
                    clientId: job.id,
                    method: 'recovered',
                  );
                }
              }
            } catch (e2) {
              final again = await _recoverExistingDest(job.destPath);
              if (again != null) {
                native = MediaRenameResult(
                  ok: true,
                  newPath: job.destPath,
                  size: again,
                  clientId: job.id,
                  method: 'recovered',
                );
              } else {
                native = MediaRenameResult(
                  ok: false,
                  error: '$e2',
                  clientId: job.id,
                );
              }
            }
          }
        }

        if (!native.ok) {
          failed++;
          lastError = native.error ?? 'transfer_failed';
          if (native.needManageStorage) {
            lastError = 'Permission needed to hide media. Allow access in '
                'Settings and try again.';
          }
          completed++;
          emit(statusMessage: cancelledNow() ? 'Cancelled' : 'Hiding…');
          continue;
        }

        final newPath = native.newPath ?? job.destPath;
        var size = native.size ?? 0;
        if (size <= 0) {
          size = await _recoverExistingDest(newPath) ?? 0;
        }
        if (size <= 0) {
          failed++;
          lastError = 'empty_dest';
          completed++;
          emit(statusMessage: 'Hiding…');
          continue;
        }

        pendingDb.add(
          (
            item: MediaItem(
              id: job.id,
              privatePath: newPath,
              originalPath: job.originalPath,
              originalName: job.originalName,
              mimeType: job.mime,
              isVideo: job.isVideo,
              width: null,
              height: null,
              durationMs: null,
              rating: 0,
              // dateAdded drives Invisible "Newest first". Prefer original capture
              // only — never invent a new capture time. If unknown, use hide
              // time for vault listing only (dateTaken stays null).
              dateAdded: job.dateTaken?.toUtc() ?? DateTime.now().toUtc(),
              dateTaken: job.dateTaken?.toUtc(),
              sizeBytes: size,
              thumbnailPath: null,
            ),
            userAlbumId: job.albumId,
          ),
        );
        thumbJobs.add(
          _ThumbJob(
            id: job.id,
            privatePath: newPath,
            isVideo: job.isVideo,
            assetId: job.src.assetId,
          ),
        );
        imported++;
        completed++;
        emit(statusMessage: cancelledNow() ? 'Cancelled' : 'Hiding…');
      }

      // Always flush after each chunk so cancel/partial failure keeps rows.
      if (pendingDb.isNotEmpty) {
        await _flushDb(pendingDb);
        pendingDb.clear();
      }

      if (cancelledNow()) {
        emit(statusMessage: 'Cancelled', cancelled: true);
        return cancelledProgress();
      }
    }

    if (pendingDb.isNotEmpty) {
      await _flushDb(pendingDb);
      pendingDb.clear();
    }

    if (cancelledNow()) {
      emit(statusMessage: 'Cancelled', cancelled: true);
      return cancelledProgress();
    }

    // One cache clear for the whole batch (per-item clear was a major slowdown).
    if (imported > 0) {
      try {
        await PhotoManager.clearFileCache().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    // ── Phase 3: deferred thumbs (non-blocking for UI completion) ───
    // Fire-and-forget after progress reports Done so the sheet can dismiss.
    // Cancel mid-thumb is best-effort only.
    if (thumbJobs.isNotEmpty && !_cancelRequested) {
      unawaited(_generateThumbsDeferred(thumbJobs));
    }

    final done = ImportProgress(
      done: total,
      total: total,
      imported: imported,
      skipped: skipped,
      failed: failed,
      statusMessage: 'Done',
      lastError: lastError,
    );
    onProgress?.call(done);
    return done;
  }

  Future<void> _flushDb(
    List<({MediaItem item, String? userAlbumId})> pending,
  ) async {
    if (pending.isEmpty) return;
    try {
      await _media.insertMany(List.of(pending));
    } catch (e, st) {
      debugPrint('batch DB insert failed: $e\n$st');
      for (final e2 in pending) {
        try {
          await _media.insert(e2.item, userAlbumId: e2.userAlbumId);
        } catch (err) {
          debugPrint('single DB insert failed ${e2.item.id}: $err');
        }
      }
    }
  }

  /// If a dest file already exists with bytes (e.g. timed-out native move),
  /// treat the hide as successful so we don't leave orphans without DB rows.
  Future<int?> _recoverExistingDest(String destPath) async {
    try {
      final f = File(destPath);
      if (!await f.exists()) return null;
      final len = await f.length();
      if (len <= 0) return null;
      return len;
    } catch (_) {
      return null;
    }
  }

  Future<_PreparedHide?> _prepareHide(
    ImportSource src, {
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
  }) async {
    File? file = File(src.path);
    var pathOk = false;
    try {
      pathOk = await file.exists();
    } catch (_) {
      pathOk = false;
    }

    if (!pathOk && src.assetId != null) {
      final entity = await AssetEntity.fromId(src.assetId!);
      if (entity == null) return null;
      File? resolved;
      try {
        resolved = await entity.file.timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('entity.file: $e');
      }
      if (resolved == null || !await resolved.exists()) return null;
      file = resolved;
    } else if (!pathOk) {
      return null;
    }

    final originalPath = file.path;
    if (originalPath.startsWith('content:')) return null;

    final name = src.name ?? p.basename(originalPath);
    var mime = _sniffMime(src.mimeType, name, originalPath);
    mime ??= () {
      final ext = p.extension(name).toLowerCase();
      if ({'.mp4', '.mov', '.mkv', '.webm', '.3gp', '.avi', '.m4v'}
          .contains(ext)) {
        return 'video/mp4';
      }
      return 'image/jpeg';
    }();
    final isVideo = mime.startsWith('video/');
    final folderName = src.sourceFolderName ??
        defaultSourceFolderName ??
        _folderNameFromPath(originalPath);

    if (HideNaming.isHiddenVaultPath(originalPath) ||
        await _media.existsByPrivatePath(originalPath)) {
      return null;
    }

    final id = _uuid.v4();
    final destPath = await _storage.hiddenDestPath(
      id: id,
      originalName: HideNaming.displayName(name),
      sourceFolder: folderName,
    );
    final albumId =
        targetUserAlbumId ?? await _resolveMirrorAlbumId(folderName);

    // Capture time only: MediaStore DATE_TAKEN → EXIF / video metadata.
    // Never use modified time or "now" — missing stays null so we don't invent dates.
    DateTime? dateTaken = src.dateTaken;
    if (dateTaken == null) {
      try {
        final sec = await _mediaStore.resolveCaptureDateSec(
          path: originalPath,
          mediaId: src.assetId,
          isVideo: isVideo,
        );
        if (sec != null && sec > 0) {
          dateTaken = DateTime.fromMillisecondsSinceEpoch(
            sec * 1000,
            isUtc: true,
          );
        }
      } catch (_) {}
    }
    // photo_manager createDateSecond as last non-mtime fallback (often DATE_TAKEN).
    if (dateTaken == null && src.assetId != null) {
      try {
        final entity = await AssetEntity.fromId(src.assetId!);
        final sec = entity?.createDateSecond;
        if (sec != null && sec > 0) {
          dateTaken = DateTime.fromMillisecondsSinceEpoch(
            sec * 1000,
            isUtc: true,
          );
        }
      } catch (_) {}
    }

    return _PreparedHide(
      id: id,
      src: src,
      originalPath: originalPath,
      originalName: HideNaming.displayName(name),
      mime: mime,
      isVideo: isVideo,
      destPath: destPath,
      folderName: folderName,
      albumId: albumId,
      dateTaken: dateTaken,
    );
  }

  /// Background thumbs after hide completes. Does not block import progress.
  Future<void> _generateThumbsDeferred(List<_ThumbJob> jobs) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelRequested) return;
        final i = next;
        if (i >= jobs.length) return;
        next = i + 1;
        final job = jobs[i];
        try {
          final path = await _makeThumb(
            hiddenFile: File(job.privatePath),
            id: job.id,
            isVideo: job.isVideo,
            assetId: job.assetId,
          ).timeout(const Duration(seconds: 6));
          if (path != null && path.isNotEmpty) {
            await _media.updateThumbnail(job.id, path);
          }
        } catch (e) {
          debugPrint('deferred thumb ${job.id}: $e');
        }
      }
    }

    final n = jobs.length < thumbConcurrency ? jobs.length : thumbConcurrency;
    await Future.wait(List.generate(n, (_) => worker()));
  }

  Future<String> _resolveMirrorAlbumId(String folderName) async {
    final key = folderName.trim().toLowerCase();
    final cached = _folderAlbumCache[key];
    if (cached != null) return cached;
    final album = await _albums.getOrCreateUserAlbumByName(folderName);
    _folderAlbumCache[key] = album.id;
    return album.id;
  }

  static String _folderNameFromPath(String path) {
    final parent = p.basename(p.dirname(path));
    if (parent.isEmpty || parent == '/' || parent == '.') return 'Imported';
    if (parent.toLowerCase() == 'download') return 'Downloads';
    return parent;
  }

  /// Resolve public restore path for [item] without moving files.
  Future<String?> _resolveRevealTarget(MediaItem item) async {
    final hidden = File(item.privatePath);
    if (!await hidden.exists()) return null;

    var visiblePath = HideNaming.resolveUnhidePath(
      privatePath: item.privatePath,
      originalPath: item.originalPath,
      originalName: item.originalName,
    );

    final hadOriginal =
        item.originalPath != null && item.originalPath!.trim().isNotEmpty;
    if (!hadOriginal && !HideNaming.isLegacyMarkerPath(item.privatePath)) {
      final parentDir = Directory(p.dirname(visiblePath));
      var parentOk = false;
      try {
        parentOk = await parentDir.exists();
      } catch (_) {
        parentOk = false;
      }
      if (!parentOk) {
        final fileName = p.basename(visiblePath);
        final download = Directory('${HideNaming.publicStorageRoot}/Download');
        final downloads =
            Directory('${HideNaming.publicStorageRoot}/Downloads');
        if (await download.exists()) {
          visiblePath = p.join(download.path, fileName);
        } else if (await downloads.exists()) {
          visiblePath = p.join(downloads.path, fileName);
        } else {
          visiblePath = p.join(HideNaming.defaultRestoreDir, fileName);
        }
      }
    }

    if (visiblePath != item.privatePath) {
      final target = File(visiblePath);
      if (await target.exists()) {
        final dir = p.dirname(visiblePath);
        final base = p.basenameWithoutExtension(visiblePath);
        final ext = p.extension(visiblePath);
        visiblePath = p.join(dir, '${base}_restored$ext');
      }
    }
    return visiblePath;
  }

  /// Unhide [item] back to a public path and drop the vault DB row.
  ///
  /// Prefers native atomic move + MediaStore scan in one IPC.
  Future<bool> reveal(
    MediaItem item, {
    bool clearGalleryCache = true,
  }) async {
    final visiblePath = await _resolveRevealTarget(item);
    if (visiblePath == null) return false;

    final taken = item.dateTaken;
    final takenSec =
        taken == null ? null : taken.toUtc().millisecondsSinceEpoch ~/ 1000;

    final native = await _renamer.unhideFromVault(
      path: item.privatePath,
      newPath: visiblePath,
      mimeType: item.mimeType,
      dateTakenSec: takenSec,
      dateAddedSec: takenSec,
    );

    if (!native.ok) {
      // Dart fallback (rare).
      try {
        final hidden = File(item.privatePath);
        if (!await hidden.exists()) return false;
        if (visiblePath != item.privatePath) {
          await Directory(p.dirname(visiblePath)).create(recursive: true);
          try {
            await hidden
                .rename(visiblePath)
                .timeout(const Duration(seconds: 15));
          } catch (_) {
            await hidden.copy(visiblePath);
            try {
              await hidden.delete();
            } catch (_) {}
          }
        }
        await _mediaStore.scanPath(
          visiblePath,
          mimeType: item.mimeType,
          dateTakenSec: takenSec,
          dateAddedSec: takenSec,
        );
      } catch (e) {
        debugPrint('reveal dart fallback: $e');
        return false;
      }
    }

    if (clearGalleryCache) {
      try {
        await PhotoManager.clearFileCache().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    final thumb = item.thumbnailPath;
    if (thumb != null && thumb.isNotEmpty) {
      final t = File(thumb);
      if (await t.exists()) await t.delete();
    }
    await _media.hardDeleteRowOnly(item.id);
    return true;
  }

  /// Batch unhide: chunked native renames + one DB transaction per chunk.
  ///
  /// Mirrors hide's architecture so large restores stay responsive.
  Future<ImportProgress> revealAll(
    List<MediaItem> items, {
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelRequested,
  }) async {
    var imported = 0;
    var failed = 0;
    var completed = 0;
    String? lastError;
    String? currentName;
    final total = items.length;

    bool cancelledNow() =>
        _cancelRequested || (isCancelRequested?.call() ?? false);

    void emit({
      String? statusMessage,
      bool cancelled = false,
    }) {
      onProgress?.call(
        ImportProgress(
          done: completed,
          total: total,
          currentName: currentName,
          imported: imported,
          failed: failed,
          cancelled: cancelled || cancelledNow(),
          statusMessage: statusMessage,
        ),
      );
    }

    ImportProgress cancelledProgress() => ImportProgress(
          done: completed,
          total: total,
          cancelled: true,
          imported: imported,
          failed: failed,
          lastError: lastError,
          statusMessage: 'Cancelled',
        );

    if (total == 0) {
      const empty = ImportProgress(
        done: 0,
        total: 0,
        statusMessage: 'Done',
      );
      onProgress?.call(empty);
      return empty;
    }

    if (cancelledNow()) {
      emit(statusMessage: 'Cancelled', cancelled: true);
      return cancelledProgress();
    }

    emit(statusMessage: 'Unhiding…');

    // Pre-resolve unique public targets (cancelable).
    final prepared = <({MediaItem item, String dest, int? takenSec})>[];
    for (final item in items) {
      if (cancelledNow()) {
        emit(statusMessage: 'Cancelled', cancelled: true);
        return cancelledProgress();
      }
      currentName = item.originalName;
      emit(statusMessage: 'Unhiding…');
      try {
        final dest = await _resolveRevealTarget(item);
        if (dest == null) {
          failed++;
          completed++;
          emit(statusMessage: 'Unhiding…');
          continue;
        }
        final taken = item.dateTaken;
        final takenSec =
            taken == null ? null : taken.toUtc().millisecondsSinceEpoch ~/ 1000;
        prepared.add((item: item, dest: dest, takenSec: takenSec));
      } catch (e) {
        failed++;
        lastError = e.toString();
        completed++;
        emit(statusMessage: 'Unhiding…');
      }
    }

    if (cancelledNow()) {
      emit(statusMessage: 'Cancelled', cancelled: true);
      return cancelledProgress();
    }

    final successIds = <String>[];
    final thumbsToDelete = <String>[];

    for (var offset = 0; offset < prepared.length; offset += nativeBatchChunk) {
      if (cancelledNow()) {
        if (successIds.isNotEmpty) {
          await _media.hardDeleteRowsOnly(successIds);
          successIds.clear();
        }
        emit(statusMessage: 'Cancelled', cancelled: true);
        return cancelledProgress();
      }

      final end = offset + nativeBatchChunk > prepared.length
          ? prepared.length
          : offset + nativeBatchChunk;
      final chunk = prepared.sublist(offset, end);
      currentName = chunk.isEmpty ? null : chunk.last.item.originalName;
      emit(statusMessage: 'Unhiding…');

      final requests = [
        for (final job in chunk)
          MediaUnhideRequest(
            clientId: job.item.id,
            path: job.item.privatePath,
            newPath: job.dest,
            mimeType: job.item.mimeType,
            dateTakenSec: job.takenSec,
            dateAddedSec: job.takenSec,
          ),
      ];

      List<MediaRenameResult> results;
      try {
        results = await _withTimeout(
          _renamer.unhideFromVaultBatch(requests),
          timeout: Duration(seconds: 15 + chunk.length * 4),
          label: 'unhide batch timed out (${chunk.length} items)',
        );
      } catch (e, st) {
        debugPrint('unhide batch failed: $e\n$st');
        results = [];
      }

      final byId = <String, MediaRenameResult>{};
      for (final r in results) {
        final id = r.clientId;
        if (id != null) byId[id] = r;
      }
      for (var i = 0; i < chunk.length && i < results.length; i++) {
        byId.putIfAbsent(chunk[i].item.id, () => results[i]);
      }

      final chunkOkIds = <String>[];
      for (final job in chunk) {
        if (cancelledNow()) break;
        MediaRenameResult native = byId[job.item.id] ??
            const MediaRenameResult(ok: false, error: 'missing_result');
        if (!native.ok) {
          // Per-item native fallback.
          try {
            native = await _withTimeout(
              _renamer.unhideFromVault(
                path: job.item.privatePath,
                newPath: job.dest,
                mimeType: job.item.mimeType,
                dateTakenSec: job.takenSec,
                dateAddedSec: job.takenSec,
              ),
              timeout: const Duration(seconds: 30),
              label: 'unhide timed out: ${job.item.originalName}',
            );
          } catch (e) {
            native = MediaRenameResult(
              ok: false,
              error: '$e',
              clientId: job.item.id,
            );
          }
        }

        if (native.ok) {
          chunkOkIds.add(job.item.id);
          final thumb = job.item.thumbnailPath;
          if (thumb != null && thumb.isNotEmpty) thumbsToDelete.add(thumb);
          imported++;
        } else {
          failed++;
          lastError = native.error ?? 'transfer_failed';
          if (native.needManageStorage) {
            lastError = 'Permission needed to unhide media. Allow access in '
                'Settings and try again.';
          }
        }
        completed++;
        emit(statusMessage: cancelledNow() ? 'Cancelled' : 'Unhiding…');
      }

      if (chunkOkIds.isNotEmpty) {
        try {
          await _media.hardDeleteRowsOnly(chunkOkIds);
        } catch (e) {
          debugPrint('batch hardDelete after unhide: $e');
          for (final id in chunkOkIds) {
            try {
              await _media.hardDeleteRowOnly(id);
            } catch (_) {}
          }
        }
      }

      if (cancelledNow()) {
        emit(statusMessage: 'Cancelled', cancelled: true);
        // Best-effort thumb cleanup for already-unhidden.
        for (final t in thumbsToDelete) {
          try {
            final f = File(t);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        return cancelledProgress();
      }
    }

    // Drop vault thumbs after successful unhides.
    for (final t in thumbsToDelete) {
      try {
        final f = File(t);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    if (imported > 0) {
      try {
        await PhotoManager.clearFileCache().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    if (cancelledNow()) {
      final c = cancelledProgress();
      onProgress?.call(c);
      return c;
    }

    final done = ImportProgress(
      done: total,
      total: total,
      imported: imported,
      failed: failed,
      statusMessage: 'Done',
      lastError: lastError,
    );
    onProgress?.call(done);
    return done;
  }

  String? _sniffMime(String? provided, String name, String path) {
    if (provided != null &&
        (provided.startsWith('image/') || provided.startsWith('video/'))) {
      return provided;
    }
    final visible = HideNaming.toVisiblePath(name.isNotEmpty ? name : path);
    final ext = p.extension(visible).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.heic' || '.heif' => 'image/heic',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.mkv' => 'video/x-matroska',
      '.webm' => 'video/webm',
      '.3gp' => 'video/3gpp',
      _ => null,
    };
  }

  Future<String?> _makeThumb({
    required File hiddenFile,
    required String id,
    required bool isVideo,
    String? assetId,
  }) async {
    // Fast path: MediaStore thumbnail (may still work briefly after move).
    if (assetId != null) {
      try {
        final entity = await AssetEntity.fromId(assetId);
        final bytes = await entity?.thumbnailDataWithSize(
          const ThumbnailSize.square(256),
          quality: 70,
        );
        if (bytes != null && bytes.isNotEmpty) {
          final out = await _storage.thumbFileFor(id);
          await out.writeAsBytes(bytes, flush: true);
          return out.path;
        }
      } catch (e) {
        debugPrint('asset thumb: $e');
      }
    }

    // Videos: decode a still from the vault file (MediaMetadataRetriever).
    if (isVideo) {
      try {
        final out = await _storage.thumbFileFor(id);
        final ok = await _renamer.videoThumbnail(
          path: hiddenFile.path,
          destPath: out.path,
          maxSize: 256,
        );
        if (ok && await out.exists() && await out.length() > 0) {
          return out.path;
        }
      } catch (e) {
        debugPrint('video thumb: $e');
      }
      return null;
    }

    // Slow path: decode image file (capped). Prefer skipped over stalling.
    try {
      final len = await hiddenFile.length();
      if (len > 8 * 1024 * 1024) return null;
      final bytes = await hiddenFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (data == null) return null;
      final out = await _storage.thumbFileFor(id);
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return out.path;
    } catch (e) {
      debugPrint('file thumb: $e');
      return null;
    }
  }
}

class _ThumbJob {
  const _ThumbJob({
    required this.id,
    required this.privatePath,
    required this.isVideo,
    this.assetId,
  });

  final String id;
  final String privatePath;
  final bool isVideo;
  final String? assetId;
}
