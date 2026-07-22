import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/vault_backup_service.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

void configureVaultBackupTestSqlite() {
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}

Matcher backupError(VaultBackupErrorCode code) =>
    isA<VaultBackupException>().having((error) => error.code, 'code', code);

Matcher backupErrorAt(
  VaultBackupErrorCode code,
  VaultBackupStage stage,
) =>
    isA<VaultBackupException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.stage, 'stage', stage);

String digestFor(String contents) =>
    base64UrlEncode(sha256.convert(utf8.encode(contents)).bytes);

final class VaultBackupTestHarness {
  late Directory temp;
  late Directory root;
  late TestVaultStorage storage;
  final databases = <AppDatabase>[];

  Future<void> setUp() async {
    temp = await Directory.systemTemp.createTemp('privi-backup-');
    root = await Directory(p.join(temp.path, 'hidden')).create();
    final privateVault = await Directory(p.join(temp.path, 'private')).create();
    storage = TestVaultStorage(root: root, privateVault: privateVault);
  }

  Future<void> tearDown() async {
    for (final database in databases) {
      await database.close();
    }
    databases.clear();
    await temp.delete(recursive: true);
  }

  AppDatabase newDatabase({QueryInterceptor? interceptor}) {
    final database = interceptor == null
        ? AppDatabase.memory()
        : AppDatabase(
            NativeDatabase.memory().interceptWith(interceptor),
          );
    databases.add(database);
    return database;
  }

  VaultBackupService service(
    AppDatabase database, {
    bool usePrivateMediaStorage = false,
  }) {
    return VaultBackupService(
      db: database,
      media: MediaRepository(database, storage),
      albums: AlbumRepository(database),
      storage: storage,
      usePrivateMediaStorage: usePrivateMediaStorage,
    );
  }

  Future<String> addMedia(
    AppDatabase database, {
    required String id,
    String contents = 'backup-media',
    String? contentDigest,
  }) async {
    final path = p.join(temp.path, '$id.jpg');
    await File(path).writeAsString(contents);
    await MediaRepository(database, storage).insert(
      MediaItem(
        id: id,
        privatePath: path,
        originalName: '$id.jpg',
        mimeType: 'image/jpeg',
        isVideo: false,
        rating: 0,
        dateAdded: DateTime.utc(2026, 7, 22),
        sizeBytes: contents.length,
        contentDigest: contentDigest,
      ),
    );
    return path;
  }

  Future<String> exportFixture({
    String contents = 'backup-media',
    String directoryName = 'fixture-export',
  }) async {
    final database = newDatabase();
    await addMedia(database, id: 'fixture-media-id', contents: contents);
    final directory = p.join(temp.path, directoryName);
    final result = await service(database).exportToDirectory(directory);
    expect(result.itemCount, 1);
    await database.close();
    databases.remove(database);
    return directory;
  }

  Future<Map<String, dynamic>> readManifest(String directory) async {
    return jsonDecode(
      await File(
        p.join(directory, VaultBackupService.manifestName),
      ).readAsString(),
    ) as Map<String, dynamic>;
  }

  Future<void> writeManifest(
    String directory,
    Map<String, dynamic> manifest,
  ) {
    return File(p.join(directory, VaultBackupService.manifestName))
        .writeAsString(jsonEncode(manifest));
  }

  Map<String, dynamic> onlyMedia(Map<String, dynamic> manifest) =>
      (manifest['media'] as List<dynamic>).single as Map<String, dynamic>;

  Future<List<String>> vaultFiles() async {
    return root
        .list(recursive: true)
        .where(
          (entity) => entity is File && p.basename(entity.path) != '.nomedia',
        )
        .map((entity) => entity.path)
        .toList();
  }
}

final class TestVaultStorage extends VaultStorageService {
  TestVaultStorage({required this.root, required this.privateVault});

  final Directory root;
  final Directory privateVault;

  @override
  Future<Directory> ensureHiddenRoot() async => root;

  @override
  Future<Directory> ensureVault() async => privateVault;

  @override
  Future<Directory> get thumbsDir async {
    final directory = Directory(p.join(privateVault.path, 'thumbs'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }
}

final class FailingMembershipInsert extends QueryInterceptor {
  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('album_media')) {
      throw StateError('injected membership write failure');
    }
    return executor.runInsert(statement, args);
  }
}
