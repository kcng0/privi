import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/data/services/platform/ios_photos_gateway.dart';
import 'package:privi/data/services/platform/ios_photos_vault_workflow_adapter.dart';
import 'package:privi/data/services/platform/ios_share_source_stager.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:sqlite3/open.dart';

final class _TestStorage extends VaultStorageService {
  _TestStorage(this.root) : super(initializeSharedRoot: false);

  final Directory root;
  int failStrictDeletes = 0;
  int failShareDeletes = 0;

  @override
  Future<Directory> ensureVault() async => root;

  @override
  Future<Directory> get thumbsDir => _directory('thumbs');

  @override
  Future<Directory> get shareStagingDir => _directory('share_staging');

  @override
  Future<File> privateMediaFileFor({
    required String id,
    required String originalName,
    String? sourceFolder,
  }) async {
    final directory = await _directory('media');
    return File(p.join(directory.path, '$id-${p.basename(originalName)}'));
  }

  @override
  Future<File> stagingFileFor({
    required String id,
    required String originalName,
  }) async {
    final directory = await _directory('staging');
    return File(p.join(directory.path, '$id-${p.basename(originalName)}.part'));
  }

  @override
  Future<File> thumbFileFor(String id) async {
    final directory = await thumbsDir;
    return File(p.join(directory.path, '$id.jpg'));
  }

  @override
  Future<void> deleteMediaFilesStrict({
    required String privatePath,
    String? thumbnailPath,
  }) async {
    if (failStrictDeletes > 0) {
      failStrictDeletes--;
      throw FileSystemException('injected strict cleanup failure', privatePath);
    }
    await super.deleteMediaFilesStrict(
      privatePath: privatePath,
      thumbnailPath: thumbnailPath,
    );
  }

  @override
  Future<void> deleteShareStagedSource(String sourcePath) async {
    if (failShareDeletes > 0) {
      failShareDeletes--;
      throw FileSystemException('injected share cleanup failure', sourcePath);
    }
    await super.deleteShareStagedSource(sourcePath);
  }

  Future<Directory> _directory(String name) async {
    final directory = Directory(p.join(root.path, name));
    await directory.create(recursive: true);
    return directory;
  }
}

final class _FakeIosPhotosGateway implements IosPhotosGateway {
  PermissionState permission = PermissionState.authorized;
  final Map<String, IosPhotosAssetLookup> lookups = {};
  final Set<String> existingIds = {};
  bool deletionAllowed = true;
  int createCalls = 0;
  int clearCacheCalls = 0;
  int deleteCalls = 0;
  int resolveCalls = 0;

  void addAsset(String id, File file, {String name = 'photo.jpg'}) {
    lookups[id] = IosPhotosAssetLookup.available(
      IosPhotosAsset(
        id: id,
        file: file,
        title: name,
        mimeType: 'image/jpeg',
        isVideo: false,
      ),
    );
    existingIds.add(id);
  }

  @override
  Future<PermissionState> permissionState() async => permission;

  @override
  Future<IosPhotosAssetLookup> resolveOriginal(String id) async {
    resolveCalls++;
    return lookups[id] ?? const IosPhotosAssetLookup.notFound();
  }

  @override
  Future<bool> deleteSource(String id) async {
    deleteCalls++;
    if (!deletionAllowed || !existingIds.contains(id)) return false;
    existingIds.remove(id);
    lookups.remove(id);
    return true;
  }

  @override
  Future<String> createAsset(MediaItem item) async {
    createCalls++;
    final id = 'restored-$createCalls';
    existingIds.add(id);
    return id;
  }

  @override
  Future<bool> assetExists(String id) async => existingIds.contains(id);

  @override
  Future<void> clearFileCache() async {
    clearCacheCalls++;
  }
}

final class _FailingMediaRepository extends MediaRepository {
  _FailingMediaRepository(super.database, super.storage);

  @override
  Future<void> insert(MediaItem item, {String? userAlbumId}) async {
    throw StateError('injected media insert failure');
  }
}

final class _FailingSourceMetadataRepository extends MediaRepository {
  _FailingSourceMetadataRepository(
    super.database,
    super.storage, {
    required this.remainingFailures,
  });

  int remainingFailures;

  @override
  Future<void> updateSourceMetadata(
    String id, {
    String? sourcePlatformId,
    required bool sourceRemovalPending,
    String? contentDigest,
  }) {
    if (remainingFailures > 0) {
      remainingFailures--;
      throw StateError('injected source metadata update failure');
    }
    return super.updateSourceMetadata(
      id,
      sourcePlatformId: sourcePlatformId,
      sourceRemovalPending: sourceRemovalPending,
      contentDigest: contentDigest,
    );
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
  late AppDatabase database;
  late _TestStorage storage;
  late MediaRepository media;
  late _FakeIosPhotosGateway photos;
  late IosPhotosVaultWorkflowAdapter workflow;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('privi-ios-workflow-');
    final vault = await Directory(p.join(temp.path, 'vault')).create();
    database = AppDatabase.memory();
    storage = _TestStorage(vault);
    media = MediaRepository(database, storage);
    photos = _FakeIosPhotosGateway();
    workflow = IosPhotosVaultWorkflowAdapter(
      storage: storage,
      media: media,
      albums: AlbumRepository(database),
      photos: photos,
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<File> sourceFile(String name) async {
    final file = File(p.join(temp.path, name));
    await file.writeAsBytes(List<int>.generate(64, (index) => index));
    return file;
  }

  ImportSource photoSource(String id) => ImportSource(
        path: '',
        assetId: id,
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        sourceFolderName: 'Photos',
      );

  test('hide verifies a private copy before removing the Photos source',
      () async {
    final source = await sourceFile('source.jpg');
    photos.addAsset('photo-1', source);

    final result = await workflow.importAll([photoSource('photo-1')]);

    expect(result.imported, 1);
    expect(result.failed, 0);
    expect(await photos.assetExists('photo-1'), isFalse);
    final item = (await media.listActive()).single;
    expect(item.sourcePlatformId, 'photo-1');
    expect(item.sourceRemovalPending, isFalse);
    expect(item.contentDigest, isNotEmpty);
    expect(
      await File(item.privatePath).readAsBytes(),
      await source.readAsBytes(),
    );
  });

  test('delete refusal keeps a verified retryable vault row', () async {
    final source = await sourceFile('refused.jpg');
    photos
      ..addAsset('photo-refused', source)
      ..deletionAllowed = false;

    final result = await workflow.importAll([photoSource('photo-refused')]);

    expect(result.imported, 0);
    expect(result.failed, 1);
    expect(result.sourceStillPresent, 1);
    expect(result.errorCode, ImportErrorCode.sourceStillPresent);
    final item = (await media.listActive()).single;
    expect(item.sourceRemovalPending, isTrue);
    expect(await File(item.privatePath).exists(), isTrue);
    expect(await photos.assetExists('photo-refused'), isTrue);
  });

  test('limited cloud-only asset reports that media is not local', () async {
    photos
      ..permission = PermissionState.limited
      ..lookups['cloud-only'] =
          const IosPhotosAssetLookup.notLocallyAvailable();

    final result = await workflow.importAll([photoSource('cloud-only')]);

    expect(result.skipped, 1);
    expect(result.failed, 0);
    expect(result.errorCode, ImportErrorCode.notLocallyAvailable);
    expect(await media.listActive(), isEmpty);
  });

  test('retry reconciles a source deleted before marker update', () async {
    final source = await sourceFile('marker-failure.jpg');
    photos.addAsset('photo-marker-failure', source);
    final failingMedia = _FailingSourceMetadataRepository(
      database,
      storage,
      remainingFailures: 1,
    );
    final failingWorkflow = IosPhotosVaultWorkflowAdapter(
      storage: storage,
      media: failingMedia,
      albums: AlbumRepository(database),
      photos: photos,
    );

    final first = await failingWorkflow.importAll([
      photoSource('photo-marker-failure'),
    ]);

    expect(first.failed, 1);
    expect(await photos.assetExists('photo-marker-failure'), isFalse);
    expect((await media.listActive()).single.sourceRemovalPending, isTrue);
    expect(photos.resolveCalls, 1);
    expect(photos.deleteCalls, 1);

    final retry = await failingWorkflow.importAll([
      photoSource('photo-marker-failure'),
    ]);

    expect(retry.imported, 1);
    expect((await media.listActive()).single.sourceRemovalPending, isFalse);
    expect(photos.resolveCalls, 1);
    expect(photos.deleteCalls, 1);
  });

  test('pre-commit failure removes the untracked private copy', () async {
    final source = await sourceFile('insert-failure.jpg');
    photos.addAsset('photo-insert-failure', source);
    final failingWorkflow = IosPhotosVaultWorkflowAdapter(
      storage: storage,
      media: _FailingMediaRepository(database, storage),
      albums: AlbumRepository(database),
      photos: photos,
    );

    final result = await failingWorkflow.importAll([
      photoSource('photo-insert-failure'),
    ]);

    expect(result.imported, 0);
    expect(result.failed, 1);
    expect(await photos.assetExists('photo-insert-failure'), isTrue);
    expect(await media.listActive(), isEmpty);
    final mediaDirectory = Directory(p.join(storage.root.path, 'media'));
    expect(
      await mediaDirectory.list().where((entry) => entry is File).toList(),
      isEmpty,
    );
  });

  test('share cleanup retry reuses the committed digest without duplicating',
      () async {
    final incoming = await sourceFile('shared.jpg');
    final stager = IosShareSourceStager(storage: storage);
    final staged = (await stager.stage([
      ImportSource(
        path: incoming.path,
        name: 'shared.jpg',
        mimeType: 'image/jpeg',
      ),
    ]))
        .single;
    storage.failShareDeletes = 1;

    final first = await workflow.importAll([staged]);
    expect(first.failed, 1);
    expect(await File(staged.path).exists(), isTrue);
    expect(await media.listActive(), hasLength(1));

    final retry = await workflow.importAll([staged]);
    expect(retry.imported, 1);
    expect(await File(staged.path).exists(), isFalse);
    expect(await media.listActive(), hasLength(1));
  });

  test('restore cleanup retry does not create a duplicate Photos asset',
      () async {
    final source = await sourceFile('restore.jpg');
    photos.addAsset('photo-restore', source);
    final hidden = await workflow.importAll([photoSource('photo-restore')]);
    expect(hidden.imported, 1);
    final item = (await media.listActive()).single;
    storage.failStrictDeletes = 1;

    expect(await workflow.reveal(item), isFalse);
    expect(photos.createCalls, 1);
    final pending = await media.findById(item.id);
    expect(pending, isNotNull);
    expect(pending!.sourcePlatformId, 'restored-1');
    expect(await File(item.privatePath).exists(), isTrue);

    expect(await workflow.reveal(item), isTrue);
    expect(photos.createCalls, 1);
    expect(await media.findById(item.id), isNull);
    expect(await File(item.privatePath).exists(), isFalse);
  });
}
