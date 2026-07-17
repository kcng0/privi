import 'dart:ffi';
import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/db/database.dart';
import 'package:sqlite3/open.dart';

import '../generated_migrations/schema.dart';

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

  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  for (final fromVersion in [2, 3, 4]) {
    test('v$fromVersion to v5 preserves rows and validates schema', () async {
      final schema = await verifier.schemaAt(fromVersion);
      final raw = schema.rawDatabase;
      raw.execute(
        'INSERT INTO albums '
        '(id, name, is_system, cover_media_id, created_at, system_kind) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['legacy-album', 'Legacy', 0, null, 1704067200, null],
      );
      raw.execute(
        'INSERT INTO media_items '
        '(id, private_path, original_path, original_name, mime_type, '
        'is_video, rating, date_added, size_bytes) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'legacy-media',
          '/vault/legacy.jpg',
          '/camera/legacy.jpg',
          'legacy.jpg',
          'image/jpeg',
          0,
          2,
          1704067200,
          42,
        ],
      );
      raw.execute(
        'INSERT INTO album_media (album_id, media_id, added_at) '
        'VALUES (?, ?, ?)',
        ['legacy-album', 'legacy-media', 1704067200],
      );

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);

      final media = await db.getMediaById('legacy-media');
      expect(media, isNotNull);
      expect(media!.originalPath, '/camera/legacy.jpg');
      expect(media.rating, 2);
      expect(await db.countMembership('legacy-album'), 1);

      final album = await db.getAlbumById('legacy-album');
      expect(album, isNotNull);
      expect(album!.pinnedAt, isNull);

      final foreignKeys =
          await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(foreignKeys.data['foreign_keys'], 1);
      await db.close();
    });
  }
}
