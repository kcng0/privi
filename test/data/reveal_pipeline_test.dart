import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/import/asset_gateway.dart';
import 'package:privi/data/services/import_service.dart';
import 'package:privi/data/services/media_rename_service.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

class _RevealRenamer extends MediaRenameService {
  Future<List<MediaRenameResult>> Function(List<MediaUnhideRequest>)? batch;
  var singleCalls = 0;

  @override
  Future<List<MediaRenameResult>> unhideFromVaultBatch(
    List<MediaUnhideRequest> items,
  ) async {
    final override = batch;
    if (override != null) return override(items);
    final results = <MediaRenameResult>[];
    for (final item in items) {
      await _move(item.path, item.newPath);
      results.add(MediaRenameResult(ok: true, clientId: item.clientId));
    }
    return results;
  }

  @override
  Future<MediaRenameResult> unhideFromVault({
    required String path,
    required String newPath,
    String? mimeType,
    int? dateTakenSec,
    int? dateAddedSec,
  }) async {
    singleCalls++;
    await _move(path, newPath);
    return const MediaRenameResult(ok: true);
  }

  static Future<void> _move(String source, String destination) async {
    await Directory(p.dirname(destination)).create(recursive: true);
    await File(source).rename(destination);
  }
}

class _NoopAssets implements AssetGateway {
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

  @override
  Future<Uint8List?> thumbnailBytes(
    String id, {
    required int size,
    required int quality,
    required int frameUs,
  }) async =>
      null;
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

  late Directory temp;
  late AppDatabase db;
  late MediaRepository media;
  late _RevealRenamer renamer;
  late ImportService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('privi-reveal-test-');
    db = AppDatabase.memory();
    media = MediaRepository(db, VaultStorageService());
    renamer = _RevealRenamer();
    service = ImportService(
      storage: VaultStorageService(),
      mediaRepository: media,
      albumRepository: AlbumRepository(db),
      renamer: renamer,
      assetGateway: _NoopAssets(),
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<MediaItem> seed(int index) async {
    final hidden = File(p.join(temp.path, 'vault', '$index.jpg'));
    await hidden.parent.create(recursive: true);
    await hidden.writeAsBytes([1, 2, 3]);
    final item = MediaItem(
      id: 'media-$index',
      privatePath: hidden.path,
      originalPath: p.join(temp.path, 'visible', '$index.jpg'),
      originalName: '$index.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      rating: 0,
      dateAdded: DateTime.utc(2026, 1, 1),
      sizeBytes: 3,
    );
    await media.insert(item);
    return item;
  }

  test('batch success removes restored rows', () async {
    final items = [await seed(0), await seed(1)];

    final summary = await service.revealAll(items);

    expect(summary.imported, 2);
    expect(await db.getMediaById('media-0'), isNull);
    expect(await db.getMediaById('media-1'), isNull);
    expect(renamer.singleCalls, 0);
    expect(await File(items.first.originalPath!).exists(), isTrue);
    expect(await File(items.first.privatePath).exists(), isFalse);
  });

  test('short batch result uses per-item fallback', () async {
    final items = [await seed(0), await seed(1)];
    renamer.batch = (requests) async {
      final first = requests.first;
      await _RevealRenamer._move(first.path, first.newPath);
      return [MediaRenameResult(ok: true, clientId: first.clientId)];
    };

    final summary = await service.revealAll(items);

    expect(summary.imported, 2);
    expect(renamer.singleCalls, 1);
  });

  test('short result recovers an unreported destination', () async {
    final items = [await seed(0), await seed(1)];
    renamer.batch = (requests) async {
      for (final request in requests) {
        await _RevealRenamer._move(request.path, request.newPath);
      }
      return [
        MediaRenameResult(
          ok: true,
          clientId: requests.first.clientId,
        ),
      ];
    };

    final summary = await service.revealAll(items);

    expect(summary.imported, 2);
    expect(summary.failed, 0);
    expect(renamer.singleCalls, 0);
  });

  test('batch failure falls back per item', () async {
    final items = [await seed(0), await seed(1)];
    renamer.batch = (_) => throw TimeoutException('batch');

    final summary = await service.revealAll(items);

    expect(summary.imported, 2);
    expect(summary.failed, 0);
    expect(renamer.singleCalls, 2);
  });

  test('cancel between chunks keeps remaining rows', () async {
    final items = <MediaItem>[];
    for (var i = 0; i < 10; i++) {
      items.add(await seed(i));
    }
    final session = ImportSession();

    final summary = await service.revealAll(
      items,
      session: session,
      onProgress: (progress) {
        if (progress.done == ImportService.nativeBatchChunk) session.cancel();
      },
    );

    expect(summary.cancelled, isTrue);
    expect(summary.imported, ImportService.nativeBatchChunk);
    for (var i = 0; i < ImportService.nativeBatchChunk; i++) {
      expect(await db.getMediaById('media-$i'), isNull);
    }
    expect(await db.getMediaById('media-8'), isNotNull);
    expect(await db.getMediaById('media-9'), isNotNull);
  });
}
