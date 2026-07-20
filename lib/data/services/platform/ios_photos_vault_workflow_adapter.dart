import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

import '../../../application/platform/vault_workflow.dart';
import '../../../domain/models/media_item.dart';
import '../../repositories/album_repository.dart';
import '../../repositories/media_repository.dart';
import '../import/import_models.dart';
import '../media_thumbnail_service.dart';
import '../vault_storage_service.dart';
import 'ios_photos_gateway.dart';

/// PhotoKit-backed hide/restore implementation.
///
/// PhotoKit identifiers are opaque and may outlive any temporary provider file,
/// so all destructive work is kept in this adapter. Android's rename and
/// MediaStore pipeline is intentionally not reused here.
final class IosPhotosVaultWorkflowAdapter implements VaultWorkflow {
  IosPhotosVaultWorkflowAdapter({
    required VaultStorageService storage,
    required MediaRepository media,
    required AlbumRepository albums,
    IosPhotosGateway? photos,
    MediaThumbnailCache? thumbnailCache,
    Uuid? uuid,
  })  : _storage = storage,
        _media = media,
        _albums = albums,
        _photos = photos ?? const PhotoManagerIosPhotosGateway(),
        _thumbnailCache = thumbnailCache,
        _uuid = uuid ?? const Uuid();

  final VaultStorageService _storage;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final IosPhotosGateway _photos;
  final MediaThumbnailCache? _thumbnailCache;
  final Uuid _uuid;

  @override
  Future<int> repairOutdatedVideoThumbnails() async {
    // A vault-only video has no PhotoKit source after Hide. A later AVAsset
    // thumbnail adapter can replace this bounded capability without changing
    // the application interface.
    return 0;
  }

  @override
  Future<String?> ensureThumbnail(MediaItem item) async {
    final path = item.thumbnailPath;
    if (path == null || path.isEmpty) return null;
    return await File(path).exists() ? path : null;
  }

  @override
  Future<ImportProgress> importAll(
    List<ImportSource> sources, {
    void Function(ImportProgress progress)? onProgress,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
    ImportSession? session,
  }) async {
    final activeSession = session ?? ImportSession();
    var imported = 0;
    var skipped = 0;
    var failed = 0;
    var sourceStillPresent = 0;
    var completed = 0;
    String? lastError;
    ImportErrorCode? errorCode;
    final total = sources.length;

    ImportProgress progress({
      required ImportPhase phase,
      bool cancelled = false,
    }) {
      return ImportProgress(
        done: completed,
        total: total,
        phase: phase,
        cancelled: cancelled,
        imported: imported,
        skipped: skipped,
        failed: failed,
        sourceStillPresent: sourceStillPresent,
        lastError: lastError,
        errorCode: errorCode,
      );
    }

    void emit(ImportProgress value) => onProgress?.call(value);

    if (total == 0) {
      const empty = ImportProgress(done: 0, total: 0, phase: ImportPhase.done);
      emit(empty);
      return empty;
    }

    for (final source in sources) {
      if (activeSession.isCancelled) {
        final cancelled = progress(
          phase: ImportPhase.cancelled,
          cancelled: true,
        );
        emit(cancelled);
        return cancelled;
      }

      try {
        final outcome = await _hideOne(
          source,
          targetUserAlbumId: targetUserAlbumId,
          defaultSourceFolderName: defaultSourceFolderName,
          session: activeSession,
        );
        switch (outcome) {
          case _IosHideResult.success:
            imported++;
          case _IosHideResult.skipped:
            skipped++;
          case _IosHideResult.sourceStillPresent:
            sourceStillPresent++;
            failed++;
            errorCode = ImportErrorCode.sourceStillPresent;
          case _IosHideResult.notLocallyAvailable:
            skipped++;
            errorCode = ImportErrorCode.notLocallyAvailable;
          case _IosHideResult.limitedAccess:
            failed++;
            errorCode = ImportErrorCode.limitedAccess;
          case _IosHideResult.permissionDenied:
            failed++;
            errorCode = ImportErrorCode.permissionDenied;
          case _IosHideResult.destinationVerificationFailed:
            failed++;
            errorCode = ImportErrorCode.destinationVerificationFailed;
          case _IosHideResult.failed:
            failed++;
            errorCode = ImportErrorCode.platformFailure;
        }
      } catch (error, stackTrace) {
        debugPrint('iOS hide failed: $error\n$stackTrace');
        failed++;
        lastError = error.toString();
        errorCode = ImportErrorCode.platformFailure;
      }

      completed++;
      final current = progress(
        phase: activeSession.isCancelled
            ? ImportPhase.cancelled
            : ImportPhase.hiding,
        cancelled: activeSession.isCancelled,
      );
      emit(current);
      if (activeSession.isCancelled) return current;
    }

    final done = progress(phase: ImportPhase.done);
    emit(done);
    return done;
  }

  @override
  Future<bool> reveal(
    MediaItem item, {
    bool clearGalleryCache = true,
    ImportSession? session,
  }) async {
    if (session?.isCancelled ?? false) return false;
    final current = await _media.findById(item.id);
    if (current == null) return false;

    final state = await _photos.permissionState();
    if (!state.hasAccess) return false;

    final photosId = current.sourcePlatformId?.trim();
    final photosAssetExists =
        photosId?.isNotEmpty == true && await _photos.assetExists(photosId!);
    final source = File(current.privatePath);
    if (!await _isVerified(source, current.contentDigest)) {
      if (!photosAssetExists) return false;
      return _completeRestoreCleanup(
        current,
        clearGalleryCache: clearGalleryCache,
      );
    }

    if (!photosAssetExists) {
      final createdId = await _photos.createAsset(current);
      if (createdId.trim().isEmpty || !await _photos.assetExists(createdId)) {
        return false;
      }
      try {
        await _media.updateSourceMetadata(
          current.id,
          sourcePlatformId: createdId,
          sourceRemovalPending: false,
          contentDigest: current.contentDigest,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'iOS restore marker failed ${current.id}: $error\n$stackTrace',
        );
        try {
          await _photos.deleteSource(createdId);
        } catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'iOS restore marker rollback failed ${current.id}: '
            '$rollbackError\n$rollbackStackTrace',
          );
        }
        return false;
      }
    }

    return _completeRestoreCleanup(
      current,
      clearGalleryCache: clearGalleryCache,
    );
  }

  Future<bool> _completeRestoreCleanup(
    MediaItem item, {
    required bool clearGalleryCache,
  }) async {
    try {
      await _storage.deleteMediaFilesStrict(
        privatePath: item.privatePath,
        thumbnailPath: item.thumbnailPath,
      );
      await _media.hardDeleteRowOnly(item.id);
      if (clearGalleryCache) await _photos.clearFileCache();
      return true;
    } catch (error, stackTrace) {
      debugPrint('iOS restore cleanup failed ${item.id}: $error\n$stackTrace');
      return false;
    }
  }

  @override
  Future<ImportProgress> revealAll(
    List<MediaItem> items, {
    void Function(ImportProgress progress)? onProgress,
    ImportSession? session,
  }) async {
    final activeSession = session ?? ImportSession();
    var imported = 0;
    var failed = 0;
    var completed = 0;

    for (final item in items) {
      if (activeSession.isCancelled) {
        final cancelled = ImportProgress(
          done: completed,
          total: items.length,
          phase: ImportPhase.cancelled,
          cancelled: true,
          imported: imported,
          failed: failed,
        );
        onProgress?.call(cancelled);
        return cancelled;
      }
      if (await reveal(item, session: activeSession)) {
        imported++;
      } else {
        failed++;
      }
      completed++;
      onProgress?.call(
        ImportProgress(
          done: completed,
          total: items.length,
          phase: ImportPhase.unhiding,
          imported: imported,
          failed: failed,
        ),
      );
    }

    final result = ImportProgress(
      done: items.length,
      total: items.length,
      phase: ImportPhase.done,
      imported: imported,
      failed: failed,
    );
    onProgress?.call(result);
    return result;
  }

  Future<_IosHideResult> _hideOne(
    ImportSource source, {
    required ImportSession session,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
  }) async {
    final assetId = source.assetId?.trim();
    if (assetId != null && assetId.isNotEmpty) {
      return _hidePhotoAsset(
        source,
        assetId: assetId,
        targetUserAlbumId: targetUserAlbumId,
        defaultSourceFolderName: defaultSourceFolderName,
        session: session,
      );
    }
    return _importExternalFile(
      source,
      targetUserAlbumId: targetUserAlbumId,
      defaultSourceFolderName: defaultSourceFolderName,
      session: session,
    );
  }

  Future<_IosHideResult> _hidePhotoAsset(
    ImportSource source, {
    required String assetId,
    required ImportSession session,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
  }) async {
    final permission = await _photos.permissionState();
    if (!permission.hasAccess) return _IosHideResult.permissionDenied;

    final existing = await _media.findBySourcePlatformId(assetId);
    if (existing != null) {
      return _retryPendingRemoval(existing, session);
    }

    final lookup = await _photos.resolveOriginal(assetId);
    if (lookup.status == IosPhotosAssetStatus.notLocallyAvailable) {
      return _IosHideResult.notLocallyAvailable;
    }
    final asset = lookup.asset;
    if (asset == null) return _IosHideResult.notLocallyAvailable;

    return _commitCopy(
      sourceFile: asset.file,
      name: source.name?.trim().isNotEmpty == true
          ? source.name!.trim()
          : asset.title,
      mimeType: source.mimeType ?? asset.mimeType,
      isVideo: asset.isVideo,
      dateTaken: source.dateTaken,
      sourcePlatformId: assetId,
      removeSource: true,
      sourceFolderName: source.sourceFolderName ?? defaultSourceFolderName,
      targetUserAlbumId: targetUserAlbumId,
      session: session,
    );
  }

  Future<_IosHideResult> _importExternalFile(
    ImportSource source, {
    required ImportSession session,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
  }) async {
    if (source.path.startsWith('content:') || source.path.trim().isEmpty) {
      return _IosHideResult.failed;
    }
    final file = File(source.path);
    if (!await file.exists() || await file.length() <= 0) {
      return _IosHideResult.notLocallyAvailable;
    }
    if (await _media.existsByPrivatePath(file.path)) {
      return _IosHideResult.skipped;
    }
    String? stagedDigest;
    if (source.deleteAfterImport) {
      stagedDigest = await _digest(file);
      final committed = await _media.findByContentDigest(stagedDigest);
      if (committed != null) {
        if (!await _isVerified(
          File(committed.privatePath),
          committed.contentDigest,
        )) {
          return _IosHideResult.destinationVerificationFailed;
        }
        await _storage.deleteShareStagedSource(file.path);
        return _IosHideResult.success;
      }
    }
    final name = source.name?.trim().isNotEmpty == true
        ? source.name!.trim()
        : p.basename(file.path);
    final mime = source.mimeType ?? _mimeFor(name);
    return _commitCopy(
      sourceFile: file,
      name: name,
      mimeType: mime,
      isVideo: mime.startsWith('video/'),
      dateTaken: source.dateTaken,
      sourcePlatformId: null,
      removeSource: false,
      deleteSourceAfterCommit: source.deleteAfterImport,
      expectedSourceDigest: stagedDigest,
      sourceFolderName: source.sourceFolderName ?? defaultSourceFolderName,
      targetUserAlbumId: targetUserAlbumId,
      session: session,
    );
  }

  Future<_IosHideResult> _retryPendingRemoval(
    MediaItem item,
    ImportSession session,
  ) async {
    if (!item.sourceRemovalPending || item.sourcePlatformId == null) {
      return _IosHideResult.skipped;
    }
    final file = File(item.privatePath);
    if (!await _isVerified(file, item.contentDigest)) {
      return _IosHideResult.destinationVerificationFailed;
    }
    if (session.isCancelled) return _IosHideResult.sourceStillPresent;
    final sourceId = item.sourcePlatformId!;
    if (await _photos.assetExists(sourceId)) {
      final removed = await _photos.deleteSource(sourceId);
      if (!removed) return _IosHideResult.sourceStillPresent;
    }
    await _media.updateSourceMetadata(
      item.id,
      sourcePlatformId: sourceId,
      sourceRemovalPending: false,
      contentDigest: item.contentDigest,
    );
    return _IosHideResult.success;
  }

  Future<_IosHideResult> _commitCopy({
    required File sourceFile,
    required String name,
    required String mimeType,
    required bool isVideo,
    required DateTime? dateTaken,
    required String? sourcePlatformId,
    required bool removeSource,
    bool deleteSourceAfterCommit = false,
    String? expectedSourceDigest,
    required String? sourceFolderName,
    required String? targetUserAlbumId,
    required ImportSession session,
  }) async {
    final id = _uuid.v4();
    final staging = await _storage.stagingFileFor(
      id: id,
      originalName: name,
    );
    final vault = await _storage.privateMediaFileFor(
      id: id,
      originalName: name,
      sourceFolder: sourceFolderName,
    );
    var committed = false;
    var ownsVaultFile = false;
    String? thumbnailPath;
    try {
      // A stale destination can only be an interrupted prior transaction or a
      // UUID collision. Never overwrite it or delete it as part of this run.
      if (await vault.exists()) {
        debugPrint('iOS vault destination already exists: ${vault.path}');
        return _IosHideResult.failed;
      }
      ownsVaultFile = true;
      final copied = await _copyAndVerify(sourceFile, staging, vault);
      if (copied == null) return _IosHideResult.destinationVerificationFailed;
      if (expectedSourceDigest != null &&
          copied.digest != expectedSourceDigest) {
        return _IosHideResult.destinationVerificationFailed;
      }

      thumbnailPath = await _writeSourceThumbnail(
        sourcePlatformId,
        id,
      );
      final albumId = targetUserAlbumId ??
          (await _albums.getOrCreateUserAlbumByName(
            sourceFolderName ?? 'Photos',
          ))
              .id;
      final item = MediaItem(
        id: id,
        privatePath: vault.path,
        originalPath: null,
        originalName: name,
        mimeType: mimeType,
        isVideo: isVideo,
        rating: 0,
        dateAdded: dateTaken?.toUtc() ?? DateTime.now().toUtc(),
        dateTaken: dateTaken?.toUtc(),
        sizeBytes: copied.length,
        thumbnailPath: thumbnailPath,
        sourcePlatformId: sourcePlatformId,
        sourceRemovalPending: removeSource,
        contentDigest: copied.digest,
      );
      await _media.insert(item, userAlbumId: albumId);
      committed = true;

      if (!removeSource) {
        if (deleteSourceAfterCommit) {
          await _storage.deleteShareStagedSource(sourceFile.path);
        }
        return _IosHideResult.success;
      }
      if (session.isCancelled) return _IosHideResult.sourceStillPresent;
      final removed = await _photos.deleteSource(sourcePlatformId!);
      if (!removed) return _IosHideResult.sourceStillPresent;
      await _media.updateSourceMetadata(
        id,
        sourcePlatformId: sourcePlatformId,
        sourceRemovalPending: false,
        contentDigest: copied.digest,
      );
      return _IosHideResult.success;
    } catch (error, stackTrace) {
      debugPrint('iOS vault transaction failed $id: $error\n$stackTrace');
      return _IosHideResult.failed;
    } finally {
      if (!committed && ownsVaultFile) {
        try {
          await _storage.deleteMediaFilesStrict(
            privatePath: vault.path,
            thumbnailPath: thumbnailPath,
          );
        } catch (error, stackTrace) {
          debugPrint(
            'iOS pre-commit vault cleanup failed $id: $error\n$stackTrace',
          );
        }
      }
      if (await staging.exists()) {
        try {
          await staging.delete();
        } catch (error) {
          debugPrint('iOS staging cleanup failed $id: $error');
        }
      }
    }
  }

  Future<_VerifiedCopy?> _copyAndVerify(
    File source,
    File staging,
    File vault,
  ) async {
    if (!await source.exists()) return null;
    await source.openRead().pipe(staging.openWrite());
    final stagedLength = await staging.length();
    if (stagedLength <= 0) return null;
    final digest = await _digest(staging);
    await staging.copy(vault.path);
    if (!await _isVerified(vault, digest)) return null;
    return _VerifiedCopy(length: stagedLength, digest: digest);
  }

  Future<String?> _writeSourceThumbnail(String? assetId, String mediaId) async {
    if (assetId == null || _thumbnailCache == null) return null;
    try {
      final bytes = await _thumbnailCache.load(assetId);
      if (bytes == null || bytes.isEmpty) return null;
      final target = await _storage.thumbFileFor(mediaId);
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } catch (error, stackTrace) {
      debugPrint('iOS source thumbnail $assetId: $error\n$stackTrace');
      return null;
    }
  }

  Future<bool> _isVerified(File file, String? expectedDigest) async {
    if (!await file.exists() || await file.length() <= 0) return false;
    if (expectedDigest == null || expectedDigest.isEmpty) return true;
    return await _digest(file) == expectedDigest;
  }

  Future<String> _digest(File file) async {
    final hash = await sha256.bind(file.openRead()).first;
    return base64UrlEncode(hash.bytes);
  }

  static String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }
}

final class _VerifiedCopy {
  const _VerifiedCopy({required this.length, required this.digest});

  final int length;
  final String digest;
}

enum _IosHideResult {
  success,
  skipped,
  sourceStillPresent,
  notLocallyAvailable,
  limitedAccess,
  permissionDenied,
  destinationVerificationFailed,
  failed,
}
