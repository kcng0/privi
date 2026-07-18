import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/grid_thumbnail_service.dart';
import 'package:privi/data/services/thumbnail_cache.dart';
import 'package:privi/domain/models/media_item.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('grid_thumb_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ThumbnailCache cache() => ThumbnailCache(cacheDir: () async => dir);

  MediaItem video({String? thumbnailPath, required String privatePath}) =>
      MediaItem(
        id: 'v1',
        privatePath: privatePath,
        originalName: 'v.mp4',
        mimeType: 'video/mp4',
        isVideo: true,
        rating: 0,
        dateAdded: DateTime.utc(2026),
        sizeBytes: 1,
        thumbnailPath: thumbnailPath,
      );

  test('forAsset decodes once and caches', () async {
    var calls = 0;
    final service = GridThumbnailService(
      cache: cache(),
      decodeAsset: (id, size) async {
        calls++;
        return Uint8List.fromList([id.length, size % 256]);
      },
      ensureVaultPoster: (_) async => null,
    );

    final first = await service.forAsset('asset', size: 512);
    final second = await service.forAsset('asset', size: 512);
    expect(first, [5, 0]);
    expect(second, [5, 0]);
    expect(calls, 1);
  });

  test('forVaultItem reads an existing poster file', () async {
    final poster = File('${dir.path}/poster.jpg');
    await poster.writeAsBytes([7, 7, 7]);
    final service = GridThumbnailService(
      cache: cache(),
      decodeAsset: (_, __) async => null,
      ensureVaultPoster: (_) async => fail('should not generate'),
    );

    final bytes = await service.forVaultItem(
      video(thumbnailPath: poster.path, privatePath: '/x.mp4'),
      size: 512,
    );
    expect(bytes, [7, 7, 7]);
  });

  test('forVaultItem generates a missing video poster on demand', () async {
    final generated = File('${dir.path}/gen.jpg');
    await generated.writeAsBytes([9, 9]);
    var generateCalls = 0;
    final service = GridThumbnailService(
      cache: cache(),
      decodeAsset: (_, __) async => null,
      ensureVaultPoster: (_) async {
        generateCalls++;
        return generated.path;
      },
    );

    final bytes = await service.forVaultItem(
      video(thumbnailPath: null, privatePath: '/x.mp4'),
      size: 512,
    );
    expect(bytes, [9, 9]);
    expect(generateCalls, 1);
  });

  test('forVaultItem falls back to the original for un-postered images',
      () async {
    final original = File('${dir.path}/image.jpg');
    await original.writeAsBytes([3, 1, 4]);
    final service = GridThumbnailService(
      cache: cache(),
      decodeAsset: (_, __) async => null,
      ensureVaultPoster: (_) async => fail('images never generate'),
    );

    final item = MediaItem(
      id: 'img',
      privatePath: original.path,
      originalName: 'i.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      rating: 0,
      dateAdded: DateTime.utc(2026),
      sizeBytes: 1,
    );

    final bytes = await service.forVaultItem(item, size: 512);
    expect(bytes, [3, 1, 4]);
  });
}
