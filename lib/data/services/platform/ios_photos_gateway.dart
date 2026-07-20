import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../../../domain/models/media_item.dart';

enum IosPhotosAssetStatus { available, notFound, notLocallyAvailable }

final class IosPhotosAsset {
  const IosPhotosAsset({
    required this.id,
    required this.file,
    required this.title,
    required this.mimeType,
    required this.isVideo,
  });

  final String id;
  final File file;
  final String title;
  final String mimeType;
  final bool isVideo;
}

final class IosPhotosAssetLookup {
  const IosPhotosAssetLookup._(this.status, this.asset);

  const IosPhotosAssetLookup.available(IosPhotosAsset asset)
      : this._(IosPhotosAssetStatus.available, asset);

  const IosPhotosAssetLookup.notFound()
      : this._(IosPhotosAssetStatus.notFound, null);

  const IosPhotosAssetLookup.notLocallyAvailable()
      : this._(IosPhotosAssetStatus.notLocallyAvailable, null);

  final IosPhotosAssetStatus status;
  final IosPhotosAsset? asset;
}

/// Internal PhotoKit seam used by the iOS vault transaction.
abstract interface class IosPhotosGateway {
  Future<PermissionState> permissionState();

  Future<IosPhotosAssetLookup> resolveOriginal(String id);

  Future<bool> deleteSource(String id);

  Future<String> createAsset(MediaItem item);

  Future<bool> assetExists(String id);

  Future<void> clearFileCache();
}

final class PhotoManagerIosPhotosGateway implements IosPhotosGateway {
  const PhotoManagerIosPhotosGateway();

  static const _requestOption = PermissionRequestOption(
    iosAccessLevel: IosAccessLevel.readWrite,
  );

  @override
  Future<PermissionState> permissionState() {
    return PhotoManager.getPermissionState(requestOption: _requestOption);
  }

  @override
  Future<IosPhotosAssetLookup> resolveOriginal(String id) async {
    final entity = await AssetEntity.fromId(id);
    if (entity == null) return const IosPhotosAssetLookup.notFound();
    if (!await entity.isLocallyAvailable(isOrigin: true)) {
      return const IosPhotosAssetLookup.notLocallyAvailable();
    }
    final file = await entity.originFile;
    if (file == null || !await file.exists()) {
      return const IosPhotosAssetLookup.notLocallyAvailable();
    }
    return IosPhotosAssetLookup.available(
      IosPhotosAsset(
        id: entity.id,
        file: file,
        title: entity.title ?? id,
        mimeType: entity.mimeType ??
            (entity.type == AssetType.video ? 'video/quicktime' : 'image/jpeg'),
        isVideo: entity.type == AssetType.video,
      ),
    );
  }

  @override
  Future<bool> deleteSource(String id) async {
    final deleted = await PhotoManager.editor.deleteWithIds([id]);
    if (!deleted.contains(id)) return false;
    return !await assetExists(id);
  }

  @override
  Future<String> createAsset(MediaItem item) async {
    final source = File(item.privatePath);
    final entity = item.isVideo
        ? await PhotoManager.editor.saveVideo(
            source,
            title: item.originalName,
            creationDate: item.dateTaken,
          )
        : await PhotoManager.editor.saveImageWithPath(
            source.path,
            title: item.originalName,
            creationDate: item.dateTaken,
          );
    return entity.id;
  }

  @override
  Future<bool> assetExists(String id) async {
    return await AssetEntity.fromId(id) != null;
  }

  @override
  Future<void> clearFileCache() => PhotoManager.clearFileCache();
}
