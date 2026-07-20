import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../../../application/platform/visible_library.dart';
import '../../../domain/enums.dart';
import '../import/asset_gateway.dart';
import '../import/file_system_gateway.dart';
import '../import/import_models.dart';
import '../media_store_service.dart';

/// Android MediaStore adapter. Its path and metadata policy intentionally
/// mirrors the pre-seam implementation so D5 behavior remains unchanged.
final class AndroidVisibleLibraryAdapter implements VisibleLibrary {
  const AndroidVisibleLibraryAdapter({
    required AssetGateway assets,
    required FileSystemGateway files,
    required MediaStoreService mediaStore,
  })  : _assets = assets,
        _files = files,
        _mediaStore = mediaStore;

  final AssetGateway _assets;
  final FileSystemGateway _files;
  final MediaStoreService _mediaStore;

  @override
  VisibleLibraryCapabilities get capabilities =>
      const VisibleLibraryCapabilities(
        filtersAssetTypesInDart: false,
        includesAllCollection: false,
        showsLimitedAccessNotice: false,
      );

  @override
  Future<PermissionState> requestPermission() =>
      PhotoManager.requestPermissionExtend();

  @override
  Future<PermissionState> permissionState() => PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<List<AssetPathEntity>> paths(MediaKindFilter filter) {
    return PhotoManager.getAssetPathList(
      type: switch (filter) {
        MediaKindFilter.image => RequestType.image,
        MediaKindFilter.video => RequestType.video,
      },
      hasAll: false,
      onlyAll: false,
      filterOption: _filterOptions,
    );
  }

  @override
  Future<int> assetCount(AssetPathEntity path) => path.assetCountAsync;

  @override
  Future<List<AssetEntity>> assetPage(
    AssetPathEntity path, {
    required int page,
    required int size,
  }) {
    return path.getAssetListPaged(page: page, size: size);
  }

  @override
  Future<ImportSource?> resolveForHide(
    String id, {
    String? sourceFolderName,
  }) async {
    try {
      final info = await _assets.info(id).timeout(const Duration(seconds: 3));
      if (info == null) return null;

      final isVideo = info.isVideo;
      final mime = info.mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg');
      final nativePath = await _mediaStore.resolveMediaPath(
        id: id,
        isVideo: isVideo,
      );
      String? resolvedPath;
      if (nativePath != null &&
          nativePath.isNotEmpty &&
          await _files.exists(nativePath)) {
        resolvedPath = nativePath;
      } else {
        try {
          resolvedPath =
              (await _assets.entityFile(id).timeout(const Duration(seconds: 4)))
                  ?.path;
        } catch (error) {
          debugPrint('entity.file failed $id: $error');
        }
        if (resolvedPath == null || !await _files.exists(resolvedPath)) {
          try {
            resolvedPath = (await _assets
                    .originFile(id)
                    .timeout(const Duration(seconds: 6)))
                ?.path;
          } catch (error) {
            debugPrint('originFile failed $id: $error');
          }
        }
      }
      if (resolvedPath == null || !await _files.exists(resolvedPath)) {
        return null;
      }
      if (resolvedPath.startsWith('content:')) return null;
      final lower = resolvedPath.toLowerCase();
      if (lower.contains('/cache/') ||
          lower.contains('/.thumbnails/') ||
          lower.contains('/android/data/') ||
          lower.contains('/app_flutter/')) {
        debugPrint('PH_HIDE reject path $resolvedPath');
        return null;
      }

      var folder = sourceFolderName?.trim();
      if (folder == null || folder.isEmpty) {
        final relative = info.relativePath;
        if (relative != null && relative.isNotEmpty) {
          final parts = relative
              .replaceAll('\\', '/')
              .split('/')
              .where((part) => part.isNotEmpty)
              .toList();
          folder = parts.isNotEmpty ? parts.last : null;
        }
      }
      folder ??= p.basename(p.dirname(resolvedPath));
      if (folder.isEmpty) folder = 'Imported';
      if (folder.toLowerCase() == 'download') folder = 'Downloads';

      DateTime? dateTaken;
      final createSeconds = await _assets.createDateSecond(id);
      if (createSeconds != null && createSeconds > 0) {
        dateTaken = DateTime.fromMillisecondsSinceEpoch(
          createSeconds * 1000,
          isUtc: true,
        );
      }
      if (dateTaken == null) {
        try {
          final seconds = await _mediaStore.resolveCaptureDateSec(
            path: resolvedPath,
            mediaId: id,
            isVideo: isVideo,
          );
          if (seconds != null && seconds > 0) {
            dateTaken = DateTime.fromMillisecondsSinceEpoch(
              seconds * 1000,
              isUtc: true,
            );
          }
        } catch (error, stackTrace) {
          debugPrint('resolve capture date $id: $error\n$stackTrace');
        }
      }

      return ImportSource(
        path: resolvedPath,
        name: info.title ?? p.basename(resolvedPath),
        mimeType: mime,
        assetId: id,
        sourceFolderName: folder,
        dateTaken: dateTaken,
      );
    } catch (error, stackTrace) {
      debugPrint('resolve Android asset $id: $error\n$stackTrace');
      return null;
    }
  }

  FilterOptionGroup get _filterOptions => FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        videoOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );
}
