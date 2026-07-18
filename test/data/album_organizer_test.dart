import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/domain/models/album.dart';
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

  setUp(() {
    database = AppDatabase.memory();
    albums = AlbumRepository(database);
  });

  tearDown(() => database.close());

  test('rating clamps and system album rating stays unchanged', () async {
    final user = await albums.createUserAlbum('User');
    await albums.setRating(user.id, 9);
    expect((await albums.getById(user.id))!.rating, 3);

    await albums.setRating(SystemAlbumIds.all, 2);
    expect((await albums.getById(SystemAlbumIds.all))!.rating, 0);
  });

  test('group membership appends and dissolve preserves albums', () async {
    final first = await albums.createUserAlbum('First');
    final second = await albums.createUserAlbum('Second');
    final group = await albums.createGroup('Series');

    await albums.addToGroup(first.id, group.id);
    await albums.addToGroup(second.id, group.id);
    expect((await albums.getById(first.id))!.sortIndex, 0);
    expect((await albums.getById(second.id))!.sortIndex, 1);

    await albums.dissolveGroup(group.id);
    expect(await albums.listGroups(), isEmpty);
    expect((await albums.getById(first.id))!.groupId, isNull);
    expect((await albums.getById(second.id))!.groupId, isNull);
  });

  test('moving to a missing group exposes the integrity error', () async {
    final user = await albums.createUserAlbum('User');

    await expectLater(
      albums.addToGroup(user.id, 'missing-group'),
      throwsStateError,
    );
    expect((await albums.getById(user.id))!.groupId, isNull);
  });
}
