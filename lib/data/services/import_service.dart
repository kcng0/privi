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
  });

  final String path;
  final String? name;
  final String? mimeType;
  final String? contentUri;
  final String? assetId;
  final String? sourceFolderName;
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

/// Hide by **rename in place** (no full-media copy). Timeouts prevent UI hangs.
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
  }) async {
    _cancelRequested = false;
    _folderAlbumCache.clear();
    var imported = 0;
    var skipped = 0;
    var failed = 0;
    String? lastError;
    final total = sources.length;

    void emit({
      required int done,
      String? currentName,
      String? statusMessage,
      bool cancelled = false,
    }) {
      onProgress?.call(
        ImportProgress(
          done: done,
          total: total,
          currentName: currentName,
          imported: imported,
          skipped: skipped,
          failed: failed,
          cancelled: cancelled,
          statusMessage: statusMessage,
        ),
      );
    }

    for (var i = 0; i < sources.length; i++) {
      if (_cancelRequested) {
        emit(done: i, cancelled: true, statusMessage: 'Cancelled');
        return ImportProgress(
          done: i,
          total: total,
          cancelled: true,
          imported: imported,
          skipped: skipped,
          failed: failed,
        );
      }

      final src = sources[i];
      final name = src.name ?? p.basename(src.path);
      emit(
        done: i,
        currentName: name,
        statusMessage: 'Hiding…',
      );

      try {
        final ok = await _withTimeout(
          _hideOne(
            src,
            targetUserAlbumId: targetUserAlbumId,
            defaultSourceFolderName: defaultSourceFolderName,
          ),
          timeout: const Duration(seconds: 45),
          label: 'hide timed out: $name',
        );
        if (ok) {
          imported++;
        } else {
          skipped++;
        }
      } catch (e, st) {
        debugPrint('hide failed: $e\n$st');
        failed++;
        lastError = e.toString();
      }
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

  Future<bool> _hideOne(
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
      if (entity == null) return false;
      File? resolved;
      try {
        resolved = await entity.file.timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('entity.file: $e');
      }
      if (resolved == null || !await resolved.exists()) return false;
      file = resolved;
    } else if (!pathOk) {
      return false;
    }

    final originalPath = file.path;
    if (originalPath.startsWith('content:')) return false;

    final name = src.name ?? p.basename(originalPath);
    var mime = _sniffMime(src.mimeType, name, originalPath);
    // Never hard-fail on unknown mime — default by extension / name.
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

    // Already in vault?
    if (HideNaming.isHiddenVaultPath(originalPath) ||
        await _media.existsByPrivatePath(originalPath)) {
      return false;
    }

    final id = _uuid.v4();
    final destPath = await _storage.hiddenDestPath(
      id: id,
      originalName: HideNaming.displayName(name),
      sourceFolder: folderName,
    );

    debugPrint(
      'PH_HIDE start src=$originalPath dest=$destPath asset=${src.assetId} video=$isVideo',
    );

    // Single native path: MediaStore stream copy/move into .nomedia vault.
    final native = await _renamer.hideToVault(
      path: originalPath,
      mediaId: src.assetId,
      newPath: destPath,
      isVideo: isVideo,
    );

    File? hiddenFile;
    if (native.ok &&
        native.newPath != null &&
        await File(native.newPath!).exists() &&
        (native.size == null || native.size! > 0)) {
      hiddenFile = File(native.newPath!);
      debugPrint('PH_HIDE native ok len=${native.size} path=${native.newPath}');
    } else {
      // Dart fallbacks (rare).
      try {
        await Directory(p.dirname(destPath)).create(recursive: true);
        final dest = File(destPath);
        if (await dest.exists()) await dest.delete();
        await file.openRead().pipe(dest.openWrite());
        if (await dest.exists() && await dest.length() > 0) {
          hiddenFile = dest;
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          debugPrint('hide via dart copy fallback');
        }
      } catch (e) {
        debugPrint('dart fallback hide: $e / native=$native');
      }
      if (hiddenFile == null && src.assetId != null) {
        try {
          final entity = await AssetEntity.fromId(src.assetId!);
          final origin =
              await entity?.originFile.timeout(const Duration(seconds: 30));
          if (origin != null && await origin.exists()) {
            final dest = File(destPath);
            await origin.openRead().pipe(dest.openWrite());
            if (await dest.exists() && await dest.length() > 0) {
              hiddenFile = dest;
              debugPrint('hide via originFile fallback');
            }
          }
        } catch (e) {
          debugPrint('origin fallback: $e');
        }
      }
    }

    if (hiddenFile == null || !await hiddenFile.exists()) {
      debugPrint('PH_HIDE FAIL native=$native');
      throw StateError(
        'Hide failed: ${native.error ?? "transfer_failed"} '
        '(needAllFiles=${native.needManageStorage}). '
        'Enable All files access and retry.',
      );
    }
    final movedLen = await hiddenFile.length();
    if (movedLen <= 0) {
      try {
        await hiddenFile.delete();
      } catch (_) {}
      throw StateError('Hide failed: vault file is empty after transfer.');
    }

    // Soft-hide: ensure MediaStore no longer lists the **original** path.
    // Do not scan the new path (dot folder + .nomedia blocks scanners).
    try {
      await _mediaStore.purgePath(originalPath);
    } catch (e) {
      debugPrint('purge original index: $e');
    }
    try {
      await PhotoManager.clearFileCache().timeout(const Duration(seconds: 2));
    } catch (_) {}

    final sizeBytes = await hiddenFile.length();
    int? width;
    int? height;
    String? thumbPath;

    try {
      thumbPath = await _makeThumb(
        hiddenFile: hiddenFile,
        id: id,
        isVideo: isVideo,
        assetId: src.assetId,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('thumb skip: $e');
    }

    if (!isVideo && thumbPath == null) {
      try {
        final dims = await _imageDimensions(hiddenFile)
            .timeout(const Duration(seconds: 5));
        width = dims?.$1;
        height = dims?.$2;
      } catch (_) {}
    }

    final item = MediaItem(
      id: id,
      privatePath: hiddenFile.path,
      originalPath: originalPath,
      originalName: HideNaming.displayName(name),
      mimeType: mime,
      isVideo: isVideo,
      width: width,
      height: height,
      durationMs: null,
      rating: 0,
      dateAdded: DateTime.now().toUtc(),
      dateTaken: await hiddenFile.lastModified(),
      sizeBytes: sizeBytes,
      thumbnailPath: thumbPath,
    );

    final albumId =
        targetUserAlbumId ?? await _resolveMirrorAlbumId(folderName);

    try {
      await _media.insert(item, userAlbumId: albumId);
    } catch (e, st) {
      debugPrint('hide DB insert failed: $e\n$st');
      // Retry once; never delete the vault file — leave orphan for scan.
      try {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _media.insert(item, userAlbumId: albumId);
      } catch (e2, st2) {
        debugPrint(
          'hide DB insert retry failed; orphan vault file kept at '
          '${hiddenFile.path}: $e2\n$st2',
        );
        throw StateError(
          'Hide DB insert failed; vault file orphaned at '
          '${hiddenFile.path}: $e2',
        );
      }
    }
    debugPrint('PH_HIDE OK $originalPath → ${hiddenFile.path} len=$movedLen');
    return true;
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

  Future<bool> reveal(MediaItem item) async {
    final hidden = File(item.privatePath);
    if (!await hidden.exists()) return false;

    // Pure path preference: originalPath → legacy reverse → vault mirror → Download.
    var visiblePath = HideNaming.resolveUnhidePath(
      privatePath: item.privatePath,
      originalPath: item.originalPath,
      originalName: item.originalName,
    );

    // If we invented a public restore dir (no originalPath) and that folder
    // is missing on disk, fall back to Download / Downloads.
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
        // Avoid clobber: suffix.
        final dir = p.dirname(visiblePath);
        final base = p.basenameWithoutExtension(visiblePath);
        final ext = p.extension(visiblePath);
        visiblePath = p.join(dir, '${base}_restored$ext');
      }
      try {
        await Directory(p.dirname(visiblePath)).create(recursive: true);
      } catch (_) {}
      try {
        await hidden.rename(visiblePath).timeout(const Duration(seconds: 15));
      } catch (e) {
        await hidden.copy(visiblePath);
        try {
          await hidden.delete();
        } catch (_) {}
      }
    }

    try {
      await _mediaStore.scanPath(visiblePath, mimeType: item.mimeType);
    } catch (e) {
      debugPrint('unhide scan: $e');
    }
    try {
      await PhotoManager.clearFileCache().timeout(const Duration(seconds: 2));
    } catch (_) {}
    final thumb = item.thumbnailPath;
    if (thumb != null && thumb.isNotEmpty) {
      final t = File(thumb);
      if (await t.exists()) await t.delete();
    }
    await _media.hardDeleteRowOnly(item.id);
    return true;
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

  Future<(int, int)?> _imageDimensions(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      return (w, h);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _makeThumb({
    required File hiddenFile,
    required String id,
    required bool isVideo,
    String? assetId,
  }) async {
    // Fast path: MediaStore thumbnail (no full-file decode).
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

    if (isVideo) return null;

    // Slow path: decode image file (capped).
    try {
      final len = await hiddenFile.length();
      if (len > 25 * 1024 * 1024) return null; // skip huge stills
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
