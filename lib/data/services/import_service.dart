import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../domain/models/media_item.dart';
import '../repositories/album_repository.dart';
import '../repositories/media_repository.dart';
import 'import/asset_gateway.dart';
import 'import/file_system_gateway.dart';
import 'import/hide_preparer.dart';
import 'import/import_models.dart';
import 'import/media_recorder.dart';
import 'import/thumbnail_generator.dart';
import 'import/vault_reveal_runner.dart';
import 'import/vault_transfer_runner.dart';
import 'media_rename_service.dart';
import 'media_store_service.dart';
import 'vault_storage_service.dart';

export 'import/import_models.dart';

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
    FileSystemGateway? fileSystem,
    AssetGateway? assetGateway,
    HidePreparer? preparer,
    VaultTransferRunner? transferRunner,
    VaultRevealRunner? revealRunner,
    MediaRecorder? recorder,
    ThumbnailGenerator? thumbnailGenerator,
    Uuid? uuid,
  })  : _renamer = renamer ?? MediaRenameService(),
        _mediaStore = mediaStore ?? MediaStoreService() {
    _fileSystem = fileSystem ?? const IoFileSystemGateway();
    _assetGateway = assetGateway ?? const PhotoManagerAssetGateway();
    _preparer = preparer ??
        HidePreparer(
          storage: storage,
          mediaRepository: mediaRepository,
          albumRepository: albumRepository,
          mediaStore: _mediaStore,
          fileSystem: _fileSystem,
          assetGateway: _assetGateway,
          uuid: uuid,
        );
    _transferRunner = transferRunner ??
        VaultTransferRunner(
          renamer: _renamer,
          fileSystem: _fileSystem,
        );
    _revealRunner = revealRunner ??
        VaultRevealRunner(
          mediaRepository: mediaRepository,
          renamer: _renamer,
          mediaStore: _mediaStore,
          assetGateway: _assetGateway,
          fileSystem: _fileSystem,
        );
    _recorder = recorder ?? MediaRecorder(mediaRepository: mediaRepository);
    _thumbnailGenerator = thumbnailGenerator ??
        ThumbnailGenerator(
          storage: storage,
          mediaRepository: mediaRepository,
          renamer: _renamer,
          assetGateway: _assetGateway,
          fileSystem: _fileSystem,
        );
  }

  final MediaRenameService _renamer;
  final MediaStoreService _mediaStore;
  late final FileSystemGateway _fileSystem;
  late final AssetGateway _assetGateway;
  late final HidePreparer _preparer;
  late final VaultTransferRunner _transferRunner;
  late final VaultRevealRunner _revealRunner;
  late final MediaRecorder _recorder;
  late final ThumbnailGenerator _thumbnailGenerator;

  /// Native items processed per MethodChannel call.
  ///
  /// Small enough that Cancel is noticed within ~one chunk of renames, and a
  /// single bad video cannot stall the whole batch for minutes.
  static const int nativeBatchChunk = VaultRevealRunner.nativeBatchChunk;

  Future<ImportProgress> importAll(
    List<ImportSource> sources, {
    void Function(ImportProgress progress)? onProgress,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
    ImportSession? session,
  }) async {
    final activeSession = session ?? ImportSession();
    _preparer.beginBatch();
    var imported = 0;
    var skipped = 0;
    var failed = 0;
    var completed = 0;
    String? lastError;
    ImportErrorCode? lastErrorCode;
    String? currentName;
    final total = sources.length;

    bool cancelledNow() => activeSession.isCancelled;

    var currentPhase = ImportPhase.resolving;

    void emit({bool cancelled = false}) {
      onProgress?.call(
        ImportProgress(
          done: completed,
          total: total,
          phase: cancelled || cancelledNow()
              ? ImportPhase.cancelled
              : currentPhase,
          currentName: currentName,
          imported: imported,
          skipped: skipped,
          failed: failed,
          cancelled: cancelled || cancelledNow(),
        ),
      );
    }

    ImportProgress cancelledProgress() => ImportProgress(
          done: completed,
          total: total,
          phase: ImportPhase.cancelled,
          cancelled: true,
          imported: imported,
          skipped: skipped,
          failed: failed,
          lastError: lastError,
          errorCode: lastErrorCode,
        );

    if (cancelledNow()) {
      emit(cancelled: true);
      return cancelledProgress();
    }

    if (total == 0) {
      const empty = ImportProgress(
        done: 0,
        total: 0,
        phase: ImportPhase.done,
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
                HidePreparer.folderNameFromPath(src.path))
            .trim();
        if (folder.isNotEmpty) folders.add(folder);
      }
      for (final folder in folders) {
        if (cancelledNow()) {
          emit(cancelled: true);
          return cancelledProgress();
        }
        await _preparer.preResolveAlbum(folder);
      }
    }

    emit();

    // ── Phase 1: prepare dest paths (cancelable per item) ───────────
    final prepared = <PreparedHide>[];
    for (var i = 0; i < sources.length; i++) {
      if (cancelledNow()) {
        // Remaining unprepared sources count as not-done (user cancelled).
        emit(cancelled: true);
        return cancelledProgress();
      }
      final src = sources[i];
      final name = src.name ?? p.basename(src.path);
      currentName = name;
      emit();

      try {
        final job = await _preparer.prepare(
          src,
          targetUserAlbumId: targetUserAlbumId,
          defaultSourceFolderName: defaultSourceFolderName,
        );
        if (job == null) {
          skipped++;
          completed++;
          emit();
          continue;
        }
        prepared.add(job);
      } catch (e, st) {
        debugPrint('prepare hide failed: $e\n$st');
        failed++;
        lastError = e.toString();
        completed++;
        emit();
      }
    }

    if (cancelledNow()) {
      emit(cancelled: true);
      return cancelledProgress();
    }

    // ── Phase 2: native transfers + durable per-chunk recording ─────
    currentPhase = ImportPhase.hiding;
    emit();
    final thumbJobs = <ThumbnailJob>[];
    await _transferRunner.run(
      prepared,
      session: activeSession,
      onChunk: (outcomes) async {
        for (final outcome in outcomes) {
          final job = outcome.job;
          currentName = job.originalName;
          completed++;
          if (!outcome.ok) {
            failed++;
            lastError = outcome.rawError;
            lastErrorCode = outcome.errorCode;
            emit(cancelled: cancelledNow());
            continue;
          }

          imported++;
          emit(cancelled: cancelledNow());
        }

        final recorded = await _recorder.record(outcomes);
        final recordedIds = {
          for (final record in recorded) record.item.id,
        };
        final recordingFailures = outcomes.where(
          (outcome) => outcome.ok && !recordedIds.contains(outcome.job.id),
        );
        final recordingFailureCount = recordingFailures.length;
        if (recordingFailureCount > 0) {
          imported -= recordingFailureCount;
          failed += recordingFailureCount;
          lastError = 'database_record_failed';
          lastErrorCode = ImportErrorCode.transferFailed;
          emit();
        }
        for (final record in recorded) {
          final job = record.outcome.job;
          thumbJobs.add(
            ThumbnailJob(
              id: job.id,
              privatePath: record.item.privatePath,
              isVideo: job.isVideo,
              assetId: job.source.assetId,
            ),
          );
        }
      },
    );

    if (cancelledNow()) {
      emit(cancelled: true);
      return cancelledProgress();
    }

    // One cache clear for the whole batch (per-item clear was a major slowdown).
    if (imported > 0) {
      try {
        await _assetGateway
            .clearFileCache()
            .timeout(const Duration(seconds: 2));
      } catch (error, stackTrace) {
        debugPrint('clear gallery cache after hide: $error\n$stackTrace');
      }
    }

    // ── Phase 3: deferred thumbs (non-blocking for UI completion) ───
    // Fire-and-forget after progress reports Done so the sheet can dismiss.
    // Cancel mid-thumb is best-effort only.
    if (thumbJobs.isNotEmpty && !activeSession.isCancelled) {
      unawaited(
        _thumbnailGenerator.generateDeferred(thumbJobs, activeSession),
      );
    }

    final done = ImportProgress(
      done: total,
      total: total,
      phase: ImportPhase.done,
      imported: imported,
      skipped: skipped,
      failed: failed,
      lastError: lastError,
      errorCode: lastErrorCode,
    );
    onProgress?.call(done);
    return done;
  }

  /// Unhide one item through the injected reveal pipeline.
  Future<bool> reveal(
    MediaItem item, {
    bool clearGalleryCache = true,
    ImportSession? session,
  }) {
    return _revealRunner.reveal(
      item,
      clearGalleryCache: clearGalleryCache,
      session: session ?? ImportSession(),
    );
  }

  /// Batch unhide with chunk-level durability and cooperative cancellation.
  Future<ImportProgress> revealAll(
    List<MediaItem> items, {
    void Function(ImportProgress progress)? onProgress,
    ImportSession? session,
  }) {
    return _revealRunner.run(
      items,
      session: session ?? ImportSession(),
      onProgress: onProgress,
    );
  }
}
