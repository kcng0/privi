part of '../vault_backup_service_test.dart';

void registerVaultBackupExportTests(VaultBackupTestHarness h) {
  group('vault backup export', () {
    test('manifest v5 round-trip preserves metadata and organization',
        () async {
      const contents = 'round-trip-media';
      const mediaId = 'round-trip-media-id';
      final sourceDb = h.newDatabase();
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

      final sourcePath = p.join(h.temp.path, 'round-trip.jpg');
      await File(sourcePath).writeAsString(contents);
      await MediaRepository(sourceDb, h.storage).insert(
        MediaItem(
          id: mediaId,
          privatePath: sourcePath,
          originalPath: '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
          originalName: 'IMG_0001.jpg',
          mimeType: 'image/jpeg',
          isVideo: false,
          rating: 3,
          dateAdded: DateTime.utc(2026, 2, 1),
          dateTaken: DateTime.utc(2026, 1, 31),
          sizeBytes: contents.length,
          sourcePlatformId: 'photo-kit-local-id',
          sourceRemovalPending: true,
          contentDigest: digestFor(contents),
        ),
        userAlbumId: 'album-camera',
      );

      final exportDirectory = p.join(h.temp.path, 'round-trip-export');
      final exported = await h
          .service(sourceDb, usePrivateMediaStorage: true)
          .exportToDirectory(exportDirectory);

      expect(exported.status, VaultBackupResultStatus.completed);
      expect(exported.itemCount, 1);
      expect(exported.totalBytes, contents.length);
      expect(exported.checksumsVerified, isTrue);
      final manifest = await h.readManifest(exportDirectory);
      expect(manifest['version'], VaultBackupService.manifestVersion);
      expect(manifest['itemCount'], 1);
      expect(manifest['totalBytes'], contents.length);
      expect(DateTime.tryParse(manifest['verifiedAt'] as String), isNotNull);
      expect(manifest['albumGroups'], hasLength(1));
      expect(manifest['membership'], hasLength(1));
      final mediaManifest = h.onlyMedia(manifest);
      expect(mediaManifest['byteLength'], contents.length);
      expect(mediaManifest['sha256'], digestFor(contents));
      expect(mediaManifest['source'], {
        'platform': 'ios',
        'libraryId': 'photo-kit-local-id',
      });

      await sourceDb.close();
      h.databases.remove(sourceDb);
      final restoredDb = h.newDatabase();
      final restored = await h
          .service(restoredDb, usePrivateMediaStorage: true)
          .importFromDirectory(exportDirectory);

      expect(restored.status, VaultBackupResultStatus.completed);
      expect(restored.itemCount, 1);
      expect(restored.checksumsVerified, isTrue);
      final restoredMedia = await restoredDb.getMediaById(mediaId);
      expect(restoredMedia, isNotNull);
      expect(
        restoredMedia!.privatePath,
        startsWith(h.storage.privateVault.path),
      );
      expect(
        restoredMedia.originalPath,
        '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
      );
      expect(restoredMedia.rating, 3);
      expect(restoredMedia.sourcePlatformId, 'photo-kit-local-id');
      expect(restoredMedia.sourceRemovalPending, isTrue);
      expect(restoredMedia.contentDigest, digestFor(contents));
      expect(await restoredDb.countMembership('album-camera'), 1);
      final restoredAlbum = await restoredDb.getAlbumById('album-camera');
      expect(restoredAlbum, isNotNull);
      expect(restoredAlbum!.pinnedAt!.toUtc(), pinnedAt);
      expect(restoredAlbum.rating, 2);
      expect(restoredAlbum.groupId, group.id);
    });

    test('missing source fails before creating the destination', () async {
      final database = h.newDatabase();
      final source = await h.addMedia(database, id: 'missing-source');
      await File(source).delete();
      final destination = p.join(h.temp.path, 'missing-source-export');

      await expectLater(
        h.service(database).exportToDirectory(destination),
        throwsA(backupError(VaultBackupErrorCode.sourceMissing)),
      );

      expect(await Directory(destination).exists(), isFalse);
    });

    test('empty source is rejected instead of being omitted', () async {
      final database = h.newDatabase();
      await h.addMedia(database, id: 'empty-source', contents: '');

      await expectLater(
        h.service(database).exportToDirectory(
              p.join(h.temp.path, 'empty-source-export'),
            ),
        throwsA(backupError(VaultBackupErrorCode.sourceEmpty)),
      );
    });

    test('multi-megabyte payload is streamed and verified', () async {
      const byteLength = 2 * 1024 * 1024;
      final source = File(p.join(h.temp.path, 'large-source.jpg'));
      final sink = source.openWrite();
      final chunk = List<int>.unmodifiable(List<int>.filled(64 * 1024, 0x5a));
      for (var offset = 0; offset < byteLength; offset += chunk.length) {
        sink.add(chunk);
      }
      await sink.close();
      final database = h.newDatabase();
      await MediaRepository(database, h.storage).insert(
        MediaItem(
          id: 'large-source',
          privatePath: source.path,
          originalName: 'large-source.jpg',
          mimeType: 'image/jpeg',
          isVideo: false,
          rating: 0,
          dateAdded: DateTime.utc(2026, 7, 22),
          sizeBytes: byteLength,
        ),
      );
      final destination = p.join(h.temp.path, 'large-source-export');

      final result = await h.service(database).exportToDirectory(destination);

      expect(result.totalBytes, byteLength);
      expect(result.checksumsVerified, isTrue);
      expect((await h.readManifest(destination))['totalBytes'], byteLength);
    });

    test('recorded content digest mismatch rejects the source', () async {
      final database = h.newDatabase();
      await h.addMedia(
        database,
        id: 'digest-mismatch',
        contents: 'actual-source',
        contentDigest: digestFor('different-source'),
      );

      await expectLater(
        h.service(database).exportToDirectory(
              p.join(h.temp.path, 'digest-mismatch-export'),
            ),
        throwsA(
          backupErrorAt(
            VaultBackupErrorCode.sourceChanged,
            VaultBackupStage.checkingSource,
          ),
        ),
      );
    });

    test('source mutation between preflight and copy fails explicitly',
        () async {
      final database = h.newDatabase();
      final source = await h.addMedia(
        database,
        id: 'source-toctou',
        contents: 'before-copy',
      );
      final destination = p.join(h.temp.path, 'source-toctou-export');
      var mutated = false;

      await expectLater(
        h.service(database).exportToDirectory(
          destination,
          onProgress: (progress) {
            if (!mutated &&
                progress.stage == VaultBackupStage.copying &&
                progress.completed == 0) {
              mutated = true;
              File(source).writeAsStringSync('changed-after-preflight');
            }
          },
        ),
        throwsA(
          backupErrorAt(
            VaultBackupErrorCode.sourceChanged,
            VaultBackupStage.copying,
          ),
        ),
      );

      expect(mutated, isTrue);
      expect(
        await File(
          p.join(destination, VaultBackupService.manifestName),
        ).exists(),
        isFalse,
      );
    });

    test('existing backup files are never overwritten', () async {
      final database = h.newDatabase();
      await h.addMedia(database, id: 'existing-backup');
      final destination = p.join(h.temp.path, 'existing-backup-export');
      await h.service(database).exportToDirectory(destination);
      final manifestFile = File(
        p.join(destination, VaultBackupService.manifestName),
      );
      final payloadFile = File(
        p.join(destination, 'media', 'existing-backup.jpg'),
      );
      final manifestBefore = await manifestFile.readAsBytes();
      final payloadBefore = await payloadFile.readAsBytes();

      await expectLater(
        h.service(database).exportToDirectory(destination),
        throwsA(backupError(VaultBackupErrorCode.destinationConflict)),
      );

      expect(await manifestFile.readAsBytes(), orderedEquals(manifestBefore));
      expect(await payloadFile.readAsBytes(), orderedEquals(payloadBefore));
    });

    test('final verification failure removes only newly committed files',
        () async {
      final database = h.newDatabase();
      await h.addMedia(
        database,
        id: 'verify-rollback',
        contents: 'verified-source',
      );
      final destination = await Directory(
        p.join(h.temp.path, 'verification-rollback'),
      ).create();
      final mediaDirectory = await Directory(
        p.join(destination.path, 'media'),
      ).create();
      final sentinel = File(p.join(mediaDirectory.path, 'keep.txt'));
      await sentinel.writeAsString('keep');
      final committedPayload = File(
        p.join(mediaDirectory.path, 'verify-rollback.jpg'),
      );
      var corrupted = false;

      await expectLater(
        h.service(database).exportToDirectory(
          destination.path,
          onProgress: (progress) {
            if (!corrupted &&
                progress.stage == VaultBackupStage.checkingBackup &&
                progress.completed == 0) {
              corrupted = true;
              committedPayload.writeAsStringSync('corrupted');
            }
          },
        ),
        throwsA(backupError(VaultBackupErrorCode.destinationWriteFailed)),
      );

      expect(corrupted, isTrue);
      expect(await sentinel.readAsString(), 'keep');
      expect(await committedPayload.exists(), isFalse);
      expect(
        await File(
          p.join(destination.path, VaultBackupService.manifestName),
        ).exists(),
        isFalse,
      );
    });

    test('completed progress observer failure does not change export result',
        () async {
      final database = h.newDatabase();
      await h.addMedia(database, id: 'observer-export');
      final destination = p.join(h.temp.path, 'observer-export');

      final result = await h.service(database).exportToDirectory(
        destination,
        onProgress: (progress) {
          if (progress.stage == VaultBackupStage.completed) {
            throw StateError('disposed observer');
          }
        },
      );

      expect(result.status, VaultBackupResultStatus.completed);
      expect(result.itemCount, 1);
      expect(
        await File(
          p.join(destination, VaultBackupService.manifestName),
        ).exists(),
        isTrue,
      );
    });

    test('export cancellation returns cancelled without publishing a backup',
        () async {
      final database = h.newDatabase();
      await h.addMedia(database, id: 'cancel-export');
      final session = VaultBackupSession();
      final destination = p.join(h.temp.path, 'cancel-export');

      final result = await h.service(database).exportToDirectory(
        destination,
        session: session,
        onProgress: (progress) {
          if (progress.stage == VaultBackupStage.checkingSource &&
              progress.completed == 0) {
            session.cancel();
          }
        },
      );

      expect(result.status, VaultBackupResultStatus.cancelled);
      expect(result.itemCount, 0);
      expect(await Directory(destination).exists(), isFalse);
    });
  });
}
