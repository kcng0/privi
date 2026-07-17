import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/media_thumbnail_spec.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/import/asset_gateway.dart';
import 'package:privi/data/services/import/file_system_gateway.dart';
import 'package:privi/data/services/import/hide_preparer.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/data/services/import/thumbnail_generator.dart';
import 'package:privi/data/services/media_rename_service.dart';
import 'package:privi/data/services/media_thumbnail_service.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

class _ThumbStorage extends VaultStorageService {
  @override
  Future<File> thumbFileFor(String id) async =>
      File('/thumbs/${MediaThumbnailSpec.fileName(id)}');
}

class _RecordingFiles implements FileSystemGateway {
  String? writtenPath;
  List<int>? writtenBytes;
  final existing = <String>{};
  final deleted = <String>[];

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    writtenPath = path;
    writtenBytes = List<int>.of(bytes);
    existing.add(path);
  }

  @override
  Future<String> copy(String sourcePath, String destinationPath) =>
      throw UnimplementedError();

  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
    existing.remove(path);
  }

  @override
  Future<bool> exists(String path) async => existing.contains(path);

  @override
  Future<int> length(String path) async => 10;

  @override
  Future<Uint8List> readBytes(String path) => throw UnimplementedError();

  @override
  Future<String> rename(String sourcePath, String destinationPath) =>
      throw UnimplementedError();
}

class _RecordingAssets implements AssetGateway {
  final poster = Uint8List.fromList([9, 8, 7, 6]);
  var thumbnailCalls = 0;
  int? requestedSize;
  int? requestedQuality;
  int? requestedFrameUs;

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

  @override
  Future<void> clearFileCache() async {}

  @override
  Future<int?> createDateSecond(String id) async => null;

  @override
  Future<File?> entityFile(String id) async => null;

  @override
  Future<AssetInfo?> info(String id) async => null;

  @override
  Future<File?> originFile(String id) async => null;
}

class _UnusedRenamer extends MediaRenameService {
  var thumbnailCalls = 0;
  var result = false;
  int? maxSize;

  @override
  Future<bool> videoThumbnail({
    required String path,
    required String destPath,
    int maxSize = 256,
  }) async {
    thumbnailCalls++;
    this.maxSize = maxSize;
    return result;
  }
}

void main() {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } catch (_) {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
  }

  test('writes the exact Visible poster without regenerating a video frame',
      () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final storage = _ThumbStorage();
    final files = _RecordingFiles();
    final assets = _RecordingAssets();
    final renamer = _UnusedRenamer();
    final media = MediaRepository(database, storage);
    final thumbnails = MediaThumbnailService(assetGateway: assets);
    final generator = ThumbnailGenerator(
      storage: storage,
      mediaRepository: media,
      renamer: renamer,
      thumbnailCache: thumbnails,
      fileSystem: files,
    );
    await media.insert(
      MediaItem(
        id: 'video-id',
        privatePath: '/vault/video.mp4',
        originalName: 'video.mp4',
        mimeType: 'video/mp4',
        isVideo: true,
        rating: 0,
        dateAdded: DateTime.utc(2026, 1, 1),
        sizeBytes: 10,
      ),
    );

    const prepared = PreparedHide(
      id: 'video-id',
      source: ImportSource(
        path: '/visible/video.mp4',
        assetId: 'asset-id',
      ),
      originalPath: '/visible/video.mp4',
      originalName: 'video.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      destinationPath: '/vault/video.mp4',
      folderName: 'Camera',
      albumId: 'camera',
    );
    await thumbnails.load('asset-id');
    final captured = await generator.attachCachedPosters([prepared]);

    await generator.generateOne(
      ThumbnailJob(
        id: 'video-id',
        privatePath: '/vault/video.mp4',
        isVideo: true,
        assetId: 'asset-id',
        sourceThumbnailBytes: captured.single.thumbnailBytes,
      ),
    );

    expect(files.writtenPath, '/thumbs/video-id.v3.jpg');
    expect(identical(captured.single.thumbnailBytes, assets.poster), isTrue);
    expect(files.writtenBytes, assets.poster);
    expect(
      (await database.getMediaById('video-id'))?.thumbnailPath,
      '/thumbs/video-id.v3.jpg',
    );
    expect(assets.thumbnailCalls, 1);
    expect(renamer.thumbnailCalls, 0);
  });

  test('batch hide does not decode uncached posters before moving files',
      () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final storage = _ThumbStorage();
    final files = _RecordingFiles();
    final assets = _RecordingAssets();
    final generator = ThumbnailGenerator(
      storage: storage,
      mediaRepository: MediaRepository(database, storage),
      renamer: _UnusedRenamer(),
      thumbnailCache: MediaThumbnailService(assetGateway: assets),
      fileSystem: files,
    );
    final prepared = List.generate(
      12,
      (index) => PreparedHide(
        id: 'video-$index',
        source: ImportSource(
          path: '/visible/video-$index.mp4',
          assetId: 'asset-$index',
        ),
        originalPath: '/visible/video-$index.mp4',
        originalName: 'video-$index.mp4',
        mimeType: 'video/mp4',
        isVideo: true,
        destinationPath: '/vault/video-$index.mp4',
        folderName: 'Camera',
        albumId: 'camera',
      ),
    );

    final captured = await generator.attachCachedPosters(prepared);

    expect(assets.thumbnailCalls, 0);
    expect(captured, hasLength(prepared.length));
    expect(
      captured.every((job) => job.thumbnailBytes == null),
      isTrue,
    );
  });

  test('repairs legacy low-resolution video thumbnails once', () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final storage = _ThumbStorage();
    final files = _RecordingFiles();
    final assets = _RecordingAssets();
    final renamer = _UnusedRenamer()..result = true;
    final media = MediaRepository(database, storage);
    final generator = ThumbnailGenerator(
      storage: storage,
      mediaRepository: media,
      renamer: renamer,
      thumbnailCache: MediaThumbnailService(assetGateway: assets),
      fileSystem: files,
    );
    const oldPath = '/thumbs/video-id.jpg';
    const newPath = '/thumbs/video-id.v3.jpg';
    files.existing.addAll([oldPath, newPath]);
    await media.insert(
      MediaItem(
        id: 'video-id',
        privatePath: '/vault/video.mp4',
        originalName: 'video.mp4',
        mimeType: 'video/mp4',
        isVideo: true,
        rating: 0,
        dateAdded: DateTime.utc(2026, 1, 1),
        sizeBytes: 10,
        thumbnailPath: oldPath,
      ),
    );

    expect(await generator.repairOutdatedVideos(), 1);
    expect(renamer.thumbnailCalls, 1);
    expect(renamer.maxSize, MediaThumbnailSpec.dimension);
    expect((await database.getMediaById('video-id'))?.thumbnailPath, newPath);
    expect(files.deleted, [oldPath]);

    expect(await generator.repairOutdatedVideos(), 0);
    expect(renamer.thumbnailCalls, 1);
  });
}
