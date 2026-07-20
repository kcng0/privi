import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/vault_backup_service.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

class _TestStorage extends VaultStorageService {
  _TestStorage({required this.root, required this.privateVault});

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
  late _TestStorage storage;
  final databases = <AppDatabase>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('privi-backup-');
    root = await Directory(p.join(temp.path, 'hidden')).create();
    final privateVault = await Directory(p.join(temp.path, 'private')).create();
    storage = _TestStorage(root: root, privateVault: privateVault);
  });

  tearDown(() async {
    for (final database in databases) {
      await database.close();
    }
    databases.clear();
    await temp.delete(recursive: true);
  });

  AppDatabase newDatabase() {
    final database = AppDatabase.memory();
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

  test('manifest v4 round-trip preserves source metadata and organization',
      () async {
    final sourceDb = newDatabase();
    final sourceMedia = MediaRepository(sourceDb, storage);
    final sourceAlbums = AlbumRepository(sourceDb);
    final pinnedAt = DateTime.utc(2026, 7, 1, 12);
    await sourceAlbums.insertWithId(
      id: 'album-camera',
      name: 'Camera',
      createdAt: DateTime.utc(2026, 1, 1),
      pinnedAt: pinnedAt,
      rating: 2,
      sortIndex: 4,
    );
    final group = await sourceAlbums.createGroup('Trips');
    await sourceAlbums.addToGroup('album-camera', group.id);

    const mediaId = '12345678-media-id';
    final privatePath = await storage.hiddenDestPath(
      id: mediaId,
      originalName: 'IMG_0001.jpg',
      sourceFolder: 'Camera',
    );
    await File(privatePath).writeAsString('round-trip-media');
    final item = MediaItem(
      id: mediaId,
      privatePath: privatePath,
      originalPath: '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
      originalName: 'IMG_0001.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      rating: 3,
      dateAdded: DateTime.utc(2026, 2, 1),
      dateTaken: DateTime.utc(2026, 1, 31),
      sizeBytes: await File(privatePath).length(),
      sourcePlatformId: 'photo-kit-local-id',
      sourceRemovalPending: true,
      contentDigest: 'sha256-digest',
    );
    await sourceMedia.insert(item, userAlbumId: 'album-camera');

    final exportDir = p.join(temp.path, 'export');
    expect(
      await service(
        sourceDb,
        usePrivateMediaStorage: true,
      ).exportToDirectory(exportDir),
      1,
    );
    final manifest = jsonDecode(
      await File(p.join(exportDir, VaultBackupService.manifestName))
          .readAsString(),
    ) as Map<String, dynamic>;
    expect(manifest['version'], 4);
    expect((manifest['albumGroups'] as List<dynamic>), hasLength(1));
    expect((manifest['membership'] as List<dynamic>), hasLength(1));
    final mediaManifest =
        (manifest['media'] as List<dynamic>).single as Map<String, dynamic>;
    expect(mediaManifest['source'], {
      'platform': 'ios',
      'libraryId': 'photo-kit-local-id',
    });

    await sourceDb.close();
    databases.remove(sourceDb);
    final restoredDb = newDatabase();
    expect(
      await service(
        restoredDb,
        usePrivateMediaStorage: true,
      ).importFromDirectory(exportDir),
      1,
    );

    final restored = await restoredDb.getMediaById(mediaId);
    expect(restored, isNotNull);
    expect(restored!.privatePath, startsWith(storage.privateVault.path));
    expect(
      restored.privatePath,
      contains('${p.separator}Camera${p.separator}'),
    );
    expect(p.basename(restored.privatePath), startsWith('${mediaId}_'));
    expect(
      restored.originalPath,
      '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
    );
    expect(restored.rating, 3);
    expect(restored.sourcePlatformId, 'photo-kit-local-id');
    expect(restored.sourceRemovalPending, isTrue);
    expect(restored.contentDigest, 'sha256-digest');
    expect(await restoredDb.countMembership('album-camera'), 1);
    final album = await restoredDb.getAlbumById('album-camera');
    expect(album, isNotNull);
    expect(album!.pinnedAt!.toUtc(), pinnedAt);
    expect(album.rating, 2);
    expect(album.groupId, group.id);
    expect((await restoredDb.getAllAlbumGroups()).single.name, 'Trips');
  });

  test('cross-platform restore does not reuse a foreign library identity',
      () async {
    final sourceDb = newDatabase();
    final sourceMedia = MediaRepository(sourceDb, storage);
    const mediaId = 'ios-source-media';
    final privatePath = await storage.privateMediaFileFor(
      id: mediaId,
      originalName: 'source.jpg',
      sourceFolder: 'Photos',
    );
    await privatePath.writeAsString('ios-backup-media');
    await sourceMedia.insert(
      MediaItem(
        id: mediaId,
        privatePath: privatePath.path,
        originalPath: null,
        originalName: 'source.jpg',
        mimeType: 'image/jpeg',
        isVideo: false,
        rating: 0,
        dateAdded: DateTime.utc(2026, 7, 19),
        sizeBytes: await privatePath.length(),
        sourcePlatformId: 'photo-kit-id',
        sourceRemovalPending: true,
        contentDigest: 'digest',
      ),
    );
    final exportDir = p.join(temp.path, 'ios-export');
    await service(
      sourceDb,
      usePrivateMediaStorage: true,
    ).exportToDirectory(exportDir);

    await sourceDb.close();
    databases.remove(sourceDb);

    final restoredDb = newDatabase();
    expect(await service(restoredDb).importFromDirectory(exportDir), 1);

    final restored = await restoredDb.getMediaById(mediaId);
    expect(restored, isNotNull);
    expect(restored!.privatePath, startsWith(root.path));
    expect(restored.sourcePlatformId, isNull);
    expect(restored.sourceRemovalPending, isFalse);
    expect(restored.contentDigest, 'digest');
  });

  test('v1 fixture remains importable into the shared hidden root', () async {
    final database = newDatabase();
    final fixture = Directory('test/fixtures/vault_backup_v1');

    expect(await service(database).importFromDirectory(fixture.path), 1);

    final restored = await database.getMediaById('legacy-media-id');
    expect(restored, isNotNull);
    expect(restored!.privatePath, startsWith(root.path));
    expect(
      restored.privatePath,
      contains('${p.separator}Imported${p.separator}'),
    );
    expect(restored.originalPath, isNull);
    expect(restored.rating, 2);
    final albums = await database.getUserAlbums();
    expect(albums.map((album) => album.name), contains('Legacy Album'));
  });

  test('import rejects manifest paths outside the backup media directory',
      () async {
    final database = newDatabase();
    final backup = await Directory(p.join(temp.path, 'malicious')).create();
    await Directory(p.join(backup.path, 'media')).create();
    await File(p.join(temp.path, 'outside.jpg')).writeAsBytes([1, 2, 3]);
    await File(p.join(backup.path, VaultBackupService.manifestName))
        .writeAsString(
      jsonEncode({
        'version': 2,
        'albums': <Object>[],
        'membership': <Object>[],
        'media': [
          {
            'id': 'safe-media-id',
            'file': '../outside.jpg',
            'originalName': 'outside.jpg',
            'isVideo': false,
          },
        ],
      }),
    );

    await expectLater(
      service(database).importFromDirectory(backup.path),
      throwsA(isA<FormatException>()),
    );
    expect(await database.getMediaById('safe-media-id'), isNull);
  });
}
