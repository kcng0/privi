import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../repositories/album_repository.dart';
import '../../repositories/media_repository.dart';
import '../hide_naming.dart';
import '../media_store_service.dart';
import '../vault_storage_service.dart';
import 'asset_gateway.dart';
import 'file_system_gateway.dart';
import 'import_models.dart';

class PreparedHide {
  const PreparedHide({
    required this.id,
    required this.source,
    required this.originalPath,
    required this.originalName,
    required this.mimeType,
    required this.isVideo,
    required this.destinationPath,
    required this.folderName,
    required this.albumId,
    this.dateTaken,
  });

  final String id;
  final ImportSource source;
  final String originalPath;
  final String originalName;
  final String mimeType;
  final bool isVideo;
  final String destinationPath;
  final String folderName;
  final String? albumId;
  final DateTime? dateTaken;
}

class HidePreparer {
  HidePreparer({
    required VaultStorageService storage,
    required MediaRepository mediaRepository,
    required AlbumRepository albumRepository,
    required MediaStoreService mediaStore,
    required FileSystemGateway fileSystem,
    required AssetGateway assetGateway,
    Uuid? uuid,
  })  : _storage = storage,
        _media = mediaRepository,
        _albums = albumRepository,
        _mediaStore = mediaStore,
        _files = fileSystem,
        _assets = assetGateway,
        _uuid = uuid ?? const Uuid();

  final VaultStorageService _storage;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final MediaStoreService _mediaStore;
  final FileSystemGateway _files;
  final AssetGateway _assets;
  final Uuid _uuid;
  final Map<String, String> _folderAlbumCache = {};

  void beginBatch() => _folderAlbumCache.clear();

  Future<String> preResolveAlbum(String folderName) =>
      _resolveMirrorAlbumId(folderName);

  Future<PreparedHide?> prepare(
    ImportSource source, {
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
  }) async {
    var originalPath = source.path;
    var pathExists = await _safeExists(originalPath);
    if (!pathExists && source.assetId != null) {
      try {
        final resolved = await _assets
            .entityFile(source.assetId!)
            .timeout(const Duration(seconds: 15));
        if (resolved == null) return null;
        originalPath = resolved.path;
        pathExists = await _safeExists(originalPath);
      } catch (error, stackTrace) {
        debugPrint('entity.file: $error\n$stackTrace');
        return null;
      }
    }
    if (!pathExists || originalPath.startsWith('content:')) return null;

    final sourceName = source.name ?? p.basename(originalPath);
    final mimeType = sniffMime(source.mimeType, sourceName, originalPath) ??
        _fallbackMime(sourceName);
    final isVideo = mimeType.startsWith('video/');
    final folderName = source.sourceFolderName ??
        defaultSourceFolderName ??
        folderNameFromPath(originalPath);

    if (HideNaming.isHiddenVaultPath(originalPath) ||
        await _media.existsByPrivatePath(originalPath)) {
      return null;
    }

    final id = _uuid.v4();
    final originalName = HideNaming.displayName(sourceName);
    final destinationPath = await _storage.hiddenDestPath(
      id: id,
      originalName: originalName,
      sourceFolder: folderName,
    );
    final albumId =
        targetUserAlbumId ?? await _resolveMirrorAlbumId(folderName);
    final dateTaken = await _resolveDateTaken(
      source,
      originalPath: originalPath,
      isVideo: isVideo,
    );

    return PreparedHide(
      id: id,
      source: source,
      originalPath: originalPath,
      originalName: originalName,
      mimeType: mimeType,
      isVideo: isVideo,
      destinationPath: destinationPath,
      folderName: folderName,
      albumId: albumId,
      dateTaken: dateTaken,
    );
  }

  Future<bool> _safeExists(String path) async {
    try {
      return await _files.exists(path);
    } catch (error, stackTrace) {
      debugPrint('file exists probe ($path): $error\n$stackTrace');
      return false;
    }
  }

  Future<DateTime?> _resolveDateTaken(
    ImportSource source, {
    required String originalPath,
    required bool isVideo,
  }) async {
    var dateTaken = source.dateTaken;
    if (dateTaken == null) {
      try {
        final seconds = await _mediaStore.resolveCaptureDateSec(
          path: originalPath,
          mediaId: source.assetId,
          isVideo: isVideo,
        );
        if (seconds != null && seconds > 0) {
          dateTaken = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        }
      } catch (error, stackTrace) {
        debugPrint('capture date: $error\n$stackTrace');
      }
    }
    if (dateTaken == null && source.assetId != null) {
      try {
        final seconds = await _assets.createDateSecond(source.assetId!);
        if (seconds != null && seconds > 0) {
          dateTaken = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        }
      } catch (error, stackTrace) {
        debugPrint('asset create date: $error\n$stackTrace');
      }
    }
    return dateTaken;
  }

  Future<String> _resolveMirrorAlbumId(String folderName) async {
    final key = folderName.trim().toLowerCase();
    final cached = _folderAlbumCache[key];
    if (cached != null) return cached;
    final album = await _albums.getOrCreateUserAlbumByName(folderName);
    _folderAlbumCache[key] = album.id;
    return album.id;
  }

  static String folderNameFromPath(String path) {
    final parent = p.basename(p.dirname(path));
    if (parent.isEmpty || parent == '/' || parent == '.') return 'Imported';
    if (parent.toLowerCase() == 'download') return 'Downloads';
    return parent;
  }

  static String? sniffMime(String? provided, String name, String path) {
    if (provided != null &&
        (provided.startsWith('image/') || provided.startsWith('video/'))) {
      return provided;
    }
    final visible = HideNaming.toVisiblePath(name.isNotEmpty ? name : path);
    final extension = p.extension(visible).toLowerCase();
    return switch (extension) {
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

  static String _fallbackMime(String name) {
    const videoExtensions = {
      '.mp4',
      '.mov',
      '.mkv',
      '.webm',
      '.3gp',
      '.avi',
      '.m4v',
    };
    return videoExtensions.contains(p.extension(name).toLowerCase())
        ? 'video/mp4'
        : 'image/jpeg';
  }
}
