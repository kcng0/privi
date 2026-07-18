import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/album.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

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

  late AppDatabase database;
  late AlbumRepository albums;
  late MediaRepository media;

  setUp(() {
    database = AppDatabase.memory();
    albums = AlbumRepository(database);
    media = MediaRepository(database, VaultStorageService());
  });

  tearDown(() => database.close());

  MediaItem favorite(String id, DateTime added) => MediaItem(
        id: id,
        privatePath: '/vault/$id.mp4',
        originalName: '$id.mp4',
        mimeType: 'video/mp4',
        isVideo: true,
        rating: 1,
        dateAdded: added,
        sizeBytes: 1,
      );

  Future<MediaItem?> favoritesCover() async {
    final views = await albums.watchAlbumViewsReactive(isVideo: true).first;
    return views
        .singleWhere((view) => view.album.id == SystemAlbumIds.favorites)
        .cover;
  }

  test('favorites cover falls back when the selected video is unfavorited',
      () async {
    await media.insert(favorite('newer', DateTime.utc(2026, 1, 2)));
    await media.insert(favorite('selected', DateTime.utc(2026, 1, 1)));
    await albums.setCover(SystemAlbumIds.favorites, 'selected');

    expect((await favoritesCover())?.id, 'selected');

    await media.updateRating('selected', 0);

    expect((await favoritesCover())?.id, 'newer');
    expect(
      (await database.getAlbumById(SystemAlbumIds.favorites))?.coverMediaId,
      isNull,
    );
  });

  test('favorites cover is cleared when the selected video is deleted',
      () async {
    await media.insert(favorite('selected', DateTime.utc(2026, 1, 1)));
    await albums.setCover(SystemAlbumIds.favorites, 'selected');

    await media.softDelete('selected');

    expect(await favoritesCover(), isNull);
    expect(
      (await database.getAlbumById(SystemAlbumIds.favorites))?.coverMediaId,
      isNull,
    );
  });

  test('user album cover falls back when the selected video is moved',
      () async {
    await albums.insertWithId(
      id: 'source',
      name: 'Source',
      createdAt: DateTime.utc(2026),
    );
    await albums.insertWithId(
      id: 'target',
      name: 'Target',
      createdAt: DateTime.utc(2026),
    );
    await media.insert(
      favorite('fallback', DateTime.utc(2026, 1, 2)),
      userAlbumId: 'source',
    );
    await media.insert(
      favorite('selected', DateTime.utc(2026, 1, 1)),
      userAlbumId: 'source',
    );
    await albums.setCover('source', 'selected');

    await albums.moveMediaToUserAlbum(
      sourceAlbumId: 'source',
      targetAlbumId: 'target',
      mediaIds: const ['selected'],
    );

    final views = await albums.watchAlbumViewsReactive(isVideo: true).first;
    expect(
      views.singleWhere((view) => view.album.id == 'source').cover?.id,
      'fallback',
    );
    expect(await database.hasMembership('source', 'selected'), isFalse);
    expect(await database.hasMembership('target', 'selected'), isTrue);
    expect((await database.getAlbumById('source'))?.coverMediaId, isNull);
  });
}
