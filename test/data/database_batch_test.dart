import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/db/database.dart';
import 'package:sqlite3/open.dart';

MediaItemsCompanion _row({
  required String id,
  required String path,
  int rating = 0,
  int sizeBytes = 100,
  DateTime? deletedAt,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return MediaItemsCompanion.insert(
    id: id,
    privatePath: path,
    originalName: '$id.jpg',
    mimeType: 'image/jpeg',
    isVideo: false,
    dateAdded: now,
    sizeBytes: sizeBytes,
    rating: Value(rating),
    deletedAt: Value(deletedAt),
  );
}

void main() {
  // Host CI/WSL often has libsqlite3.so.0 but not the unversioned .so name.
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } catch (_) {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
  }

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test('listActivePrivatePaths returns only non-deleted paths', () async {
    await db.insertMedia(_row(id: 'a', path: '/v/a.jpg'));
    await db.insertMedia(_row(id: 'b', path: '/v/b.jpg'));
    await db.insertMedia(
      _row(id: 'c', path: '/v/c.jpg', deletedAt: DateTime.utc(2026, 2, 1)),
    );

    final paths = await db.listActivePrivatePaths();
    expect(paths, unorderedEquals(['/v/a.jpg', '/v/b.jpg']));
  });

  test('sumMediaBytes sums all rows including recycle', () async {
    await db.insertMedia(_row(id: 'a', path: '/v/a.jpg', sizeBytes: 10));
    await db.insertMedia(
      _row(
        id: 'b',
        path: '/v/b.jpg',
        sizeBytes: 25,
        deletedAt: DateTime.utc(2026, 2, 1),
      ),
    );

    expect(await db.sumMediaBytes(), 35);
  });

  test('countMembership ignores soft-deleted media', () async {
    // System albums already seeded by onCreate.
    await db.insertAlbum(
      AlbumsCompanion.insert(
        id: 'user1',
        name: 'Camera',
        isSystem: false,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await db.insertMedia(_row(id: 'a', path: '/v/a.jpg'));
    await db.insertMedia(
      _row(id: 'b', path: '/v/b.jpg', deletedAt: DateTime.utc(2026, 2, 1)),
    );
    await db.addMembership('user1', 'a', DateTime.utc(2026, 1, 2));
    await db.addMembership('user1', 'b', DateTime.utc(2026, 1, 2));

    expect(await db.countMembership('user1'), 1);
  });

  test('updateMediaRatings updates only listed ids', () async {
    await db.insertMedia(_row(id: 'a', path: '/v/a.jpg', rating: 0));
    await db.insertMedia(_row(id: 'b', path: '/v/b.jpg', rating: 0));
    await db.insertMedia(_row(id: 'c', path: '/v/c.jpg', rating: 1));

    await db.updateMediaRatings(['a', 'b'], 3);

    expect((await db.getMediaById('a'))!.rating, 3);
    expect((await db.getMediaById('b'))!.rating, 3);
    expect((await db.getMediaById('c'))!.rating, 1);
  });

  test('insertMediaBatch inserts rows and memberships in one transaction',
      () async {
    await db.insertAlbum(
      AlbumsCompanion.insert(
        id: 'user-batch',
        name: 'Downloads',
        isSystem: false,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await db.insertMediaBatch(
      [
        _row(id: 'x', path: '/v/x.jpg', sizeBytes: 11),
        _row(id: 'y', path: '/v/y.jpg', sizeBytes: 22),
      ],
      membershipByMediaId: {
        'x': 'user-batch',
        'y': 'user-batch',
      },
    );

    expect(await db.getMediaById('x'), isNotNull);
    expect(await db.getMediaById('y'), isNotNull);
    expect(await db.countMembership('user-batch'), 2);
    expect(await db.sumMediaBytes(), 33);
  });

  test('updateMediaThumbnail writes path', () async {
    await db.insertMedia(_row(id: 't', path: '/v/t.jpg'));
    await db.updateMediaThumbnail('t', '/thumbs/t.jpg');
    expect((await db.getMediaById('t'))!.thumbnailPath, '/thumbs/t.jpg');
  });

  test('softDeleteMediaMany and restoreMediaMany', () async {
    await db.insertMedia(_row(id: 'a', path: '/v/a.jpg'));
    await db.insertMedia(_row(id: 'b', path: '/v/b.jpg'));

    final at = DateTime.utc(2026, 3, 1);
    await db.softDeleteMediaMany(['a', 'b'], at);
    // Drift may surface stored times in local offset; assert non-null + equal rows.
    final delA = (await db.getMediaById('a'))!.deletedAt;
    final delB = (await db.getMediaById('b'))!.deletedAt;
    expect(delA, isNotNull);
    expect(delB, isNotNull);
    expect(delA!.toUtc(), delB!.toUtc());

    await db.restoreMediaMany(['a']);
    expect((await db.getMediaById('a'))!.deletedAt, isNull);
    expect((await db.getMediaById('b'))!.deletedAt, isNotNull);
  });

  test('hardDeleteMediaMany removes media and memberships', () async {
    await db.insertAlbum(
      AlbumsCompanion.insert(
        id: 'user1',
        name: 'Camera',
        isSystem: false,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await db.insertMedia(_row(id: 'a', path: '/v/a.jpg'));
    await db.insertMedia(_row(id: 'b', path: '/v/b.jpg'));
    await db.addMembership('user1', 'a', DateTime.utc(2026, 1, 2));
    await db.addMembership('user1', 'b', DateTime.utc(2026, 1, 2));

    await db.hardDeleteMediaMany(['a', 'b']);

    expect(await db.getMediaById('a'), isNull);
    expect(await db.getMediaById('b'), isNull);
    expect(await db.countMembership('user1'), 0);
  });

  test('perf indexes are created without error', () async {
    // onCreate path already ran; re-open style check via PRAGMA.
    final rows = await db.customSelect('PRAGMA index_list(media_items)').get();
    final names = rows.map((r) => r.data['name'] as String?).toSet();
    expect(names, contains('idx_media_items_deleted_date'));
    expect(names, contains('idx_media_items_private_path'));

    final am = await db.customSelect('PRAGMA index_list(album_media)').get();
    final amNames = am.map((r) => r.data['name'] as String?).toSet();
    expect(amNames, contains('idx_album_media_album_id'));
  });
}
