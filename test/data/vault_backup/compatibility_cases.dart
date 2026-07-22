part of '../vault_backup_service_test.dart';

void registerVaultBackupCompatibilityTests(VaultBackupTestHarness h) {
  group('vault backup compatibility', () {
    test('cross-platform restore drops foreign library identity', () async {
      const contents = 'ios-backup-media';
      const mediaId = 'ios-source-media';
      final sourceDb = h.newDatabase();
      final source = File(p.join(h.temp.path, 'ios-source.jpg'));
      await source.writeAsString(contents);
      await MediaRepository(sourceDb, h.storage).insert(
        MediaItem(
          id: mediaId,
          privatePath: source.path,
          originalName: 'source.jpg',
          mimeType: 'image/jpeg',
          isVideo: false,
          rating: 0,
          dateAdded: DateTime.utc(2026, 7, 19),
          sizeBytes: contents.length,
          sourcePlatformId: 'photo-kit-id',
          sourceRemovalPending: true,
          contentDigest: digestFor(contents),
        ),
      );
      final backup = p.join(h.temp.path, 'ios-export');
      await h
          .service(sourceDb, usePrivateMediaStorage: true)
          .exportToDirectory(backup);
      await sourceDb.close();
      h.databases.remove(sourceDb);
      final restoredDb = h.newDatabase();

      final result = await h.service(restoredDb).importFromDirectory(backup);

      expect(result.status, VaultBackupResultStatus.completed);
      final restored = await restoredDb.getMediaById(mediaId);
      expect(restored, isNotNull);
      expect(restored!.privatePath, startsWith(h.root.path));
      expect(restored.sourcePlatformId, isNull);
      expect(restored.sourceRemovalPending, isFalse);
      expect(restored.contentDigest, digestFor(contents));
    });

    test('v1 fixture remains importable into the shared hidden root', () async {
      final database = h.newDatabase();
      const fixture = 'test/fixtures/vault_backup_v1';

      final result = await h.service(database).importFromDirectory(fixture);

      expect(result.status, VaultBackupResultStatus.completed);
      expect(result.itemCount, 1);
      expect(result.checksumsVerified, isFalse);
      final restored = await database.getMediaById('legacy-media-id');
      expect(restored, isNotNull);
      expect(restored!.privatePath, startsWith(h.root.path));
      expect(
        restored.privatePath,
        contains('${p.separator}Imported${p.separator}'),
      );
      expect(restored.originalPath, isNull);
      expect(restored.rating, 2);
      final albums = await database.getUserAlbums();
      expect(albums.map((album) => album.name), contains('Legacy Album'));
    });

    for (final fixture in const [
      (
        version: 2,
        mediaId: 'historical-v2-media-id',
        albumId: 'historical-v2-album-id',
        groupId: null,
        rating: 0,
      ),
      (
        version: 3,
        mediaId: 'historical-v3-media-id',
        albumId: 'historical-v3-album-id',
        groupId: 'historical-v3-group-id',
        rating: 2,
      ),
      (
        version: 4,
        mediaId: 'historical-v4-media-id',
        albumId: 'historical-v4-album-id',
        groupId: 'historical-v4-group-id',
        rating: 3,
      ),
    ]) {
      test('real v${fixture.version} historical fixture remains importable',
          () async {
        final database = h.newDatabase();
        final directory = 'test/fixtures/vault_backup_v${fixture.version}';

        final result = await h
            .service(
              database,
              usePrivateMediaStorage: fixture.version == 4,
            )
            .importFromDirectory(directory);

        expect(result.status, VaultBackupResultStatus.completed);
        expect(result.itemCount, 1);
        expect(result.totalBytes, 20);
        expect(result.checksumsVerified, isFalse);
        final media = await database.getMediaById(fixture.mediaId);
        expect(media, isNotNull);
        expect(media!.originalPath, contains('/DCIM/Camera/'));
        expect(await database.countMembership(fixture.albumId), 1);
        final album = await database.getAlbumById(fixture.albumId);
        expect(album, isNotNull);
        expect(album!.rating, fixture.rating);
        expect(album.groupId, fixture.groupId);
        if (fixture.groupId != null) {
          final groups = await database.getAllAlbumGroups();
          expect(groups.map((group) => group.id), contains(fixture.groupId));
        }
        if (fixture.version == 4) {
          expect(media.sourcePlatformId, 'historical-photo-kit-id');
          expect(media.sourceRemovalPending, isTrue);
          expect(
            media.contentDigest,
            't9yiPn8g7IlJphaKnBQQE3Lww75_y7OoyYeeo3lp02w=',
          );
        } else {
          expect(media.sourcePlatformId, isNull);
          expect(media.sourceRemovalPending, isFalse);
          expect(media.contentDigest, isNull);
        }
      });
    }

    test('legacy restore detects same-size payload mutation after preflight',
        () async {
      const fixture = 'test/fixtures/vault_backup_v4';
      final backup = await Directory(
        p.join(h.temp.path, 'legacy-toctou'),
      ).create();
      final mediaDirectory = await Directory(
        p.join(backup.path, 'media'),
      ).create();
      await File(p.join(fixture, VaultBackupService.manifestName)).copy(
        p.join(backup.path, VaultBackupService.manifestName),
      );
      final payload = File(
        p.join(mediaDirectory.path, 'historical-v4-media-id.jpg'),
      );
      await File(
        p.join(fixture, 'media', 'historical-v4-media-id.jpg'),
      ).copy(payload.path);
      final database = h.newDatabase();
      var mutated = false;

      await expectLater(
        h.service(database, usePrivateMediaStorage: true).importFromDirectory(
          backup.path,
          onProgress: (progress) {
            if (!mutated &&
                progress.stage == VaultBackupStage.restoring &&
                progress.completed == 0) {
              final bytes = payload.readAsBytesSync();
              bytes[0] ^= 0xff;
              payload.writeAsBytesSync(bytes);
              mutated = true;
            }
          },
        ),
        throwsA(backupError(VaultBackupErrorCode.payloadDigestMismatch)),
      );

      expect(mutated, isTrue);
      expect(
        await database.getMediaById('historical-v4-media-id'),
        isNull,
      );
      expect(await h.vaultFiles(), isEmpty);
    });
  });
}
