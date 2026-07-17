import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/maintenance_service.dart';
import 'package:privi/data/services/media_rename_service.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:sqlite3/open.dart';

class _TestStorage extends VaultStorageService {
  _TestStorage({required this.root, required this.thumbs});

  final Directory root;
  final Directory thumbs;

  @override
  Future<Directory> ensureHiddenRoot() async => root;

  @override
  Future<Directory> get thumbsDir async => thumbs;
}

class _TestRenamer extends MediaRenameService {
  _TestRenamer(this.accessible);

  final bool accessible;

  @override
  Future<bool> isExternalStorageManager() async => accessible;
}

MediaItemsCompanion _row({
  required String id,
  required String path,
  DateTime? deletedAt,
}) {
  return MediaItemsCompanion.insert(
    id: id,
    privatePath: path,
    originalName: '$id.jpg',
    mimeType: 'image/jpeg',
    isVideo: false,
    dateAdded: DateTime.utc(2026, 1, 1),
    sizeBytes: 100,
    deletedAt: Value(deletedAt),
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

  late Directory temp;
  late Directory root;
  late Directory thumbs;
  late AppDatabase db;
  late _TestStorage storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('privi-maintenance-');
    root = await Directory('${temp.path}/vault').create();
    thumbs = await Directory('${temp.path}/thumbs').create();
    db = AppDatabase.memory();
    storage = _TestStorage(root: root, thumbs: thumbs);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  MaintenanceService service({required bool accessible}) {
    return MaintenanceService(
      db: db,
      media: MediaRepository(db, storage),
      storage: storage,
      albums: AlbumRepository(db),
      renamer: _TestRenamer(accessible),
    );
  }

  test('launch maintenance keeps all rows when shared storage is unavailable',
      () async {
    await db.insertMedia(
      _row(id: 'active', path: '${root.path}/Camera/missing.jpg'),
    );
    await db.insertMedia(
      _row(
        id: 'recycle',
        path: '${root.path}/Download/missing.jpg',
        deletedAt: DateTime.utc(2025, 1, 1),
      ),
    );

    final summary =
        await service(accessible: false).runLaunchMaintenance(retentionDays: 7);

    expect(summary, contains('skipped (no storage access)'));
    expect(await db.getMediaById('active'), isNotNull);
    expect(await db.getMediaById('recycle'), isNotNull);
  });

  test('launch maintenance purges a missing file in a listable directory',
      () async {
    final parent = await Directory('${root.path}/Camera').create();
    await File('${parent.path}/present.jpg').writeAsString('present');
    await db.insertMedia(
      _row(id: 'missing', path: '${parent.path}/missing.jpg'),
    );

    final summary =
        await service(accessible: true).runLaunchMaintenance(retentionDays: 7);

    expect(summary, contains('removed 1 missing'));
    expect(await db.getMediaById('missing'), isNull);
  });

  test('missing parent directory is treated as an unreliable probe', () async {
    await db.insertMedia(
      _row(id: 'missing-parent', path: '${root.path}/Gone/missing.jpg'),
    );

    await service(accessible: true).runLaunchMaintenance(retentionDays: 7);

    expect(await db.getMediaById('missing-parent'), isNotNull);
  });

  test('empty recovery and date repair return typed results', () async {
    final maintenance = service(accessible: true);

    final recovery = await maintenance.recoverVaultFiles();
    final repair = await maintenance.repairCaptureDates();

    expect(recovery.status, VaultRecoveryStatus.noFiles);
    expect(recovery.reindexed, 0);
    expect(repair.hadMedia, isFalse);
    expect(repair.fixed, 0);
  });
}
