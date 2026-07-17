import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../domain/models/media_item.dart';
import '../../repositories/media_repository.dart';
import '../hide_naming.dart';
import '../media_rename_service.dart';
import '../media_store_service.dart';
import 'asset_gateway.dart';
import 'file_system_gateway.dart';
import 'import_models.dart';

/// Runs reveal transfers and commits their DB cleanup chunk by chunk.
class VaultRevealRunner {
  const VaultRevealRunner({
    required MediaRepository mediaRepository,
    required MediaRenameService renamer,
    required MediaStoreService mediaStore,
    required AssetGateway assetGateway,
    required FileSystemGateway fileSystem,
  })  : _media = mediaRepository,
        _renamer = renamer,
        _mediaStore = mediaStore,
        _assets = assetGateway,
        _files = fileSystem;

  final MediaRepository _media;
  final MediaRenameService _renamer;
  final MediaStoreService _mediaStore;
  final AssetGateway _assets;
  final FileSystemGateway _files;

  static const int nativeBatchChunk = 8;

  Future<bool> reveal(
    MediaItem item, {
    required bool clearGalleryCache,
    required ImportSession session,
  }) async {
    if (session.isCancelled) return false;
    final visiblePath = await _resolveTarget(item);
    if (visiblePath == null || session.isCancelled) return false;

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
      try {
        if (!await _files.exists(item.privatePath)) return false;
        if (visiblePath != item.privatePath) {
          await _files.createDirectory(p.dirname(visiblePath));
          try {
            await _files
                .rename(item.privatePath, visiblePath)
                .timeout(const Duration(seconds: 15));
          } catch (error, stackTrace) {
            debugPrint('reveal rename fallback: $error\n$stackTrace');
            await _files.copy(item.privatePath, visiblePath);
            await _files.delete(item.privatePath);
          }
        }
        await _mediaStore.scanPath(
          visiblePath,
          mimeType: item.mimeType,
          dateTakenSec: takenSec,
          dateAddedSec: takenSec,
        );
      } catch (error, stackTrace) {
        debugPrint('reveal file fallback: $error\n$stackTrace');
        return false;
      }
    }

    if (clearGalleryCache) await _clearGalleryCache();
    final thumb = item.thumbnailPath;
    if (thumb != null && thumb.isNotEmpty && await _files.exists(thumb)) {
      await _files.delete(thumb);
    }
    await _media.hardDeleteRowOnly(item.id);
    return true;
  }

  Future<ImportProgress> run(
    List<MediaItem> items, {
    required ImportSession session,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    var imported = 0;
    var failed = 0;
    var completed = 0;
    String? lastError;
    ImportErrorCode? lastErrorCode;
    String? currentName;
    final total = items.length;

    void emit({bool cancelled = false}) {
      onProgress?.call(
        ImportProgress(
          done: completed,
          total: total,
          phase: cancelled || session.isCancelled
              ? ImportPhase.cancelled
              : ImportPhase.unhiding,
          currentName: currentName,
          imported: imported,
          failed: failed,
          cancelled: cancelled || session.isCancelled,
        ),
      );
    }

    ImportProgress cancelledProgress() => ImportProgress(
          done: completed,
          total: total,
          phase: ImportPhase.cancelled,
          cancelled: true,
          imported: imported,
          failed: failed,
          lastError: lastError,
          errorCode: lastErrorCode,
        );

    if (total == 0) {
      const empty = ImportProgress(
        done: 0,
        total: 0,
        phase: ImportPhase.done,
      );
      onProgress?.call(empty);
      return empty;
    }
    if (session.isCancelled) {
      emit(cancelled: true);
      return cancelledProgress();
    }
    emit();

    final prepared = <_PreparedReveal>[];
    for (final item in items) {
      if (session.isCancelled) {
        emit(cancelled: true);
        return cancelledProgress();
      }
      currentName = item.originalName;
      emit();
      try {
        final dest = await _resolveTarget(item);
        if (dest == null) {
          failed++;
          completed++;
          emit();
          continue;
        }
        final taken = item.dateTaken;
        prepared.add(
          _PreparedReveal(
            item: item,
            destinationPath: dest,
            takenSec: taken == null
                ? null
                : taken.toUtc().millisecondsSinceEpoch ~/ 1000,
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('prepare reveal ${item.id}: $error\n$stackTrace');
        failed++;
        lastError = error.toString();
        completed++;
        emit();
      }
    }

    final thumbsToDelete = <String>[];
    for (var offset = 0; offset < prepared.length; offset += nativeBatchChunk) {
      if (session.isCancelled) {
        emit(cancelled: true);
        await _deleteThumbs(thumbsToDelete);
        return cancelledProgress();
      }
      final end = offset + nativeBatchChunk > prepared.length
          ? prepared.length
          : offset + nativeBatchChunk;
      final chunk = prepared.sublist(offset, end);
      currentName = chunk.last.item.originalName;
      emit();

      final results = await _batchResults(chunk);
      final byId = <String, MediaRenameResult>{};
      for (final result in results) {
        final id = result.clientId;
        if (id != null) byId[id] = result;
      }
      for (var index = 0;
          index < chunk.length && index < results.length;
          index++) {
        byId.putIfAbsent(chunk[index].item.id, () => results[index]);
      }

      final chunkOkIds = <String>[];
      final thumbById = <String, String>{};
      for (final job in chunk) {
        if (session.isCancelled) break;
        final native = await _resolveNativeResult(job, byId[job.item.id]);
        if (native.ok) {
          chunkOkIds.add(job.item.id);
          final thumb = job.item.thumbnailPath;
          if (thumb != null && thumb.isNotEmpty) {
            thumbById[job.item.id] = thumb;
          }
          imported++;
        } else {
          failed++;
          lastError = native.error ?? 'transfer_failed';
          lastErrorCode = _errorCode(native);
        }
        completed++;
        emit(cancelled: session.isCancelled);
      }

      if (chunkOkIds.isNotEmpty) {
        final deletedIds = await _deleteRows(chunkOkIds);
        final deleteFailures = chunkOkIds.length - deletedIds.length;
        if (deleteFailures > 0) {
          imported -= deleteFailures;
          failed += deleteFailures;
          lastError = 'database_cleanup_failed';
          lastErrorCode = ImportErrorCode.transferFailed;
          emit();
        }
        for (final id in deletedIds) {
          final thumb = thumbById[id];
          if (thumb != null) thumbsToDelete.add(thumb);
        }
      }

      if (session.isCancelled) {
        emit(cancelled: true);
        await _deleteThumbs(thumbsToDelete);
        return cancelledProgress();
      }
    }

    await _deleteThumbs(thumbsToDelete);
    if (imported > 0) await _clearGalleryCache();

    final done = ImportProgress(
      done: total,
      total: total,
      phase: ImportPhase.done,
      imported: imported,
      failed: failed,
      lastError: lastError,
      errorCode: lastErrorCode,
    );
    onProgress?.call(done);
    return done;
  }

  Future<String?> _resolveTarget(MediaItem item) async {
    if (!await _files.exists(item.privatePath)) return null;
    var visiblePath = HideNaming.resolveUnhidePath(
      privatePath: item.privatePath,
      originalPath: item.originalPath,
      originalName: item.originalName,
    );

    final hadOriginal =
        item.originalPath != null && item.originalPath!.trim().isNotEmpty;
    if (!hadOriginal && !HideNaming.isLegacyMarkerPath(item.privatePath)) {
      final parentExists = await _files.exists(p.dirname(visiblePath));
      if (!parentExists) {
        final fileName = p.basename(visiblePath);
        final download = p.join(HideNaming.publicStorageRoot, 'Download');
        final downloads = p.join(HideNaming.publicStorageRoot, 'Downloads');
        if (await _files.exists(download)) {
          visiblePath = p.join(download, fileName);
        } else if (await _files.exists(downloads)) {
          visiblePath = p.join(downloads, fileName);
        } else {
          visiblePath = p.join(HideNaming.defaultRestoreDir, fileName);
        }
      }
    }

    if (visiblePath != item.privatePath && await _files.exists(visiblePath)) {
      final directory = p.dirname(visiblePath);
      final base = p.basenameWithoutExtension(visiblePath);
      final extension = p.extension(visiblePath);
      visiblePath = p.join(directory, '${base}_restored$extension');
    }
    return visiblePath;
  }

  Future<List<MediaRenameResult>> _batchResults(
    List<_PreparedReveal> chunk,
  ) async {
    try {
      return await _withTimeout(
        _renamer.unhideFromVaultBatch([
          for (final job in chunk)
            MediaUnhideRequest(
              clientId: job.item.id,
              path: job.item.privatePath,
              newPath: job.destinationPath,
              mimeType: job.item.mimeType,
              dateTakenSec: job.takenSec,
              dateAddedSec: job.takenSec,
            ),
        ]),
        timeout: Duration(seconds: 15 + chunk.length * 4),
        label: 'unhide batch timed out (${chunk.length} items)',
      );
    } catch (error, stackTrace) {
      debugPrint('unhide batch failed: $error\n$stackTrace');
      return const [];
    }
  }

  Future<MediaRenameResult> _resolveNativeResult(
    _PreparedReveal job,
    MediaRenameResult? batchResult,
  ) async {
    if (batchResult?.ok == true) return batchResult!;
    final recovered = await _recoverDestination(job);
    if (recovered != null) return recovered;
    try {
      final single = await _withTimeout(
        _renamer.unhideFromVault(
          path: job.item.privatePath,
          newPath: job.destinationPath,
          mimeType: job.item.mimeType,
          dateTakenSec: job.takenSec,
          dateAddedSec: job.takenSec,
        ),
        timeout: const Duration(seconds: 30),
        label: 'unhide timed out: ${job.item.originalName}',
      );
      if (single.ok) return single;
      return await _recoverDestination(job) ?? single;
    } catch (error) {
      return await _recoverDestination(job) ??
          MediaRenameResult(
            ok: false,
            error: error.toString(),
            clientId: job.item.id,
          );
    }
  }

  Future<MediaRenameResult?> _recoverDestination(_PreparedReveal job) async {
    try {
      if (!await _files.exists(job.destinationPath)) return null;
      final size = await _files.length(job.destinationPath);
      if (size <= 0) return null;
      return MediaRenameResult(
        ok: true,
        newPath: job.destinationPath,
        size: size,
        clientId: job.item.id,
        method: 'recovered',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'recover reveal destination ${job.destinationPath}: '
        '$error\n$stackTrace',
      );
      return null;
    }
  }

  Future<Set<String>> _deleteRows(List<String> ids) async {
    final deleted = <String>{};
    try {
      await _media.hardDeleteRowsOnly(ids);
      return deleted..addAll(ids);
    } catch (error, stackTrace) {
      debugPrint('batch hardDelete after unhide: $error\n$stackTrace');
    }
    for (final id in ids) {
      try {
        await _media.hardDeleteRowOnly(id);
        deleted.add(id);
      } catch (error, stackTrace) {
        debugPrint('hardDelete after unhide failed $id: $error\n$stackTrace');
      }
    }
    return deleted;
  }

  Future<void> _deleteThumbs(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        if (await _files.exists(path)) await _files.delete(path);
      } catch (error, stackTrace) {
        debugPrint('delete reveal thumbnail $path: $error\n$stackTrace');
      }
    }
  }

  Future<void> _clearGalleryCache() async {
    try {
      await _assets.clearFileCache().timeout(const Duration(seconds: 2));
    } catch (error, stackTrace) {
      debugPrint('clear gallery cache after reveal: $error\n$stackTrace');
    }
  }

  static ImportErrorCode _errorCode(MediaRenameResult result) {
    if (result.needManageStorage) return ImportErrorCode.needManageStorage;
    if (result.error?.toLowerCase().contains('timeout') == true) {
      return ImportErrorCode.timeout;
    }
    return ImportErrorCode.transferFailed;
  }

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
}

class _PreparedReveal {
  const _PreparedReveal({
    required this.item,
    required this.destinationPath,
    required this.takenSec,
  });

  final MediaItem item;
  final String destinationPath;
  final int? takenSec;
}
