import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

class AssetInfo {
  const AssetInfo({
    required this.id,
    required this.isVideo,
    this.title,
    this.mimeType,
    this.relativePath,
  });

  final String id;
  final bool isVideo;
  final String? title;
  final String? mimeType;
  final String? relativePath;
}

abstract class AssetGateway {
  Future<AssetInfo?> info(String id);

  Future<File?> entityFile(String id);

  Future<File?> originFile(String id);

  Future<Uint8List?> thumbnailBytes(
    String id, {
    required int size,
    required int quality,
    required int frameUs,
  });

  Future<int?> createDateSecond(String id);

  Future<void> clearFileCache();
}

class PhotoManagerAssetGateway implements AssetGateway {
  const PhotoManagerAssetGateway();

  @override
  Future<AssetInfo?> info(String id) async {
    final entity = await AssetEntity.fromId(id);
    if (entity == null) return null;
    return AssetInfo(
      id: entity.id,
      isVideo: entity.type == AssetType.video,
      title: entity.title,
      mimeType: entity.mimeType,
      relativePath: entity.relativePath,
    );
  }

  @override
  Future<File?> entityFile(String id) async {
    final entity = await AssetEntity.fromId(id);
    return entity?.file;
  }

  @override
  Future<File?> originFile(String id) async {
    final entity = await AssetEntity.fromId(id);
    return entity?.originFile;
  }

  @override
  Future<Uint8List?> thumbnailBytes(
    String id, {
    required int size,
    required int quality,
    required int frameUs,
  }) async {
    final entity = await AssetEntity.fromId(id);
    return entity?.thumbnailDataWithSize(
      ThumbnailSize.square(size),
      quality: quality,
      frame: frameUs,
    );
  }

  @override
  Future<int?> createDateSecond(String id) async {
    final entity = await AssetEntity.fromId(id);
    return entity?.createDateSecond;
  }

  @override
  Future<void> clearFileCache() => PhotoManager.clearFileCache();
}
