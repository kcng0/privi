import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/import/hide_preparer.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/data/services/import/media_recorder.dart';
import 'package:privi/data/services/import/vault_transfer_runner.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

PreparedHide _job(int index) {
  return PreparedHide(
    id: 'job-$index',
    source: ImportSource(path: '/source/$index.jpg'),
    originalPath: '/source/$index.jpg',
    originalName: '$index.jpg',
    mimeType: 'image/jpeg',
    isVideo: false,
    destinationPath: '/vault/$index.jpg',
    folderName: 'Camera',
    albumId: 'album-camera',
  );
}

TransferOutcome _success(PreparedHide job) {
  return TransferOutcome.success(
    job: job,
    destinationPath: job.destinationPath,
    sizeBytes: 10,
  );
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

  late AppDatabase database;
  late MediaRepository media;

  setUp(() async {
    database = AppDatabase.memory();
    media = MediaRepository(database, VaultStorageService());
    await AlbumRepository(database).insertWithId(
      id: 'album-camera',
      name: 'Camera',
      createdAt: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() => database.close());

  test('batch failure retries each row and reports only durable records',
      () async {
    await media.insert(
      MediaItem(
        id: 'job-0',
        privatePath: '/existing/0.jpg',
        originalName: '0.jpg',
        mimeType: 'image/jpeg',
        isVideo: false,
        rating: 0,
        dateAdded: DateTime.utc(2026, 1, 1),
        sizeBytes: 10,
      ),
    );
    final recorder = MediaRecorder(
      mediaRepository: media,
      now: () => DateTime.utc(2026, 1, 2),
    );

    final records = await recorder.record([
      _success(_job(0)),
      _success(_job(1)),
    ]);

    expect(records.map((record) => record.item.id), ['job-1']);
    expect(await database.getMediaById('job-1'), isNotNull);
    expect(await database.countMembership('album-camera'), 1);
  });
}
