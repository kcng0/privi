import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/media_thumbnail_spec.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/data/services/import/asset_gateway.dart';
import 'package:privi/data/services/import/file_system_gateway.dart';
import 'package:privi/data/services/media_store_service.dart';
import 'package:privi/data/services/media_thumbnail_service.dart';

class _RecordingAssets implements AssetGateway {
  final poster = Uint8List.fromList([1, 3, 3, 7]);
  var thumbnailCalls = 0;
  int? requestedSize;
  int? requestedQuality;
  int? requestedFrameUs;

  @override
  Future<void> clearFileCache() async {}

  @override
  Future<int?> createDateSecond(String id) async => 1735689600;

  @override
  Future<File?> entityFile(String id) async => null;

  @override
  Future<AssetInfo?> info(String id) async => const AssetInfo(
        id: 'video-id',
        isVideo: true,
        title: 'clip.mp4',
        mimeType: 'video/mp4',
        relativePath: 'DCIM/Camera/',
      );

  @override
  Future<File?> originFile(String id) async => null;

  @override
  Future<Uint8List?> thumbnailBytes(
    String id, {
    required int size,
    required int quality,
    required int frameUs,
  }) async {
    thumbnailCalls++;
    requestedSize = size;
    requestedQuality = quality;
    requestedFrameUs = frameUs;
    return poster;
  }
}

class _ExistingFiles implements FileSystemGateway {
  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<String> copy(String sourcePath, String destinationPath) =>
      throw UnimplementedError();

  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();

  @override
  Future<void> delete(String path) => throw UnimplementedError();

  @override
  Future<int> length(String path) => throw UnimplementedError();

  @override
  Future<Uint8List> readBytes(String path) => throw UnimplementedError();

  @override
  Future<String> rename(String sourcePath, String destinationPath) =>
      throw UnimplementedError();

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      throw UnimplementedError();
}

class _ResolvedMediaStore extends MediaStoreService {
  @override
  Future<String?> resolveMediaPath({
    required String id,
    required bool isVideo,
  }) async =>
      '/storage/emulated/0/DCIM/Camera/clip.mp4';
}

void main() {
  test('Visible thumbnails share one high-definition poster cache', () async {
    final assets = _RecordingAssets();
    final thumbnails = MediaThumbnailService(assetGateway: assets);
    final gallery = GalleryService(
      assetGateway: assets,
      thumbnailCache: thumbnails,
      fileSystem: _ExistingFiles(),
      mediaStore: _ResolvedMediaStore(),
    );
    addTearDown(gallery.dispose);

    final visiblePoster = await gallery.mediaThumbnail('video-id');
    final cachedPoster = await gallery.mediaThumbnail('video-id');
    final sources = await gallery.resolveForHide(
      const ['video-id'],
      sourceFolderName: 'Camera',
    );

    expect(sources, hasLength(1));
    expect(identical(cachedPoster, visiblePoster), isTrue);
    expect(identical(thumbnails.peek('video-id'), visiblePoster), isTrue);
    expect(visiblePoster, assets.poster);
    expect(assets.thumbnailCalls, 1);
    expect(assets.requestedSize, MediaThumbnailSpec.dimension);
    expect(assets.requestedQuality, MediaThumbnailSpec.quality);
    expect(assets.requestedFrameUs, MediaThumbnailSpec.videoFrameUs);
  });
}
