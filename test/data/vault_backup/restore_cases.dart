part of '../vault_backup_service_test.dart';

void registerVaultBackupRestoreTests(VaultBackupTestHarness h) {
  group('vault backup restore', () {
    test('missing manifest is reported explicitly', () async {
      final backup = await Directory(
        p.join(h.temp.path, 'missing-manifest'),
      ).create();
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup.path),
        throwsA(backupError(VaultBackupErrorCode.manifestMissing)),
      );
    });

    test('unsupported manifest version is rejected', () async {
      final backup = await Directory(
        p.join(h.temp.path, 'unsupported-version'),
      ).create();
      await h.writeManifest(backup.path, {
        'version': VaultBackupService.manifestVersion + 1,
      });
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup.path),
        throwsA(
          backupError(VaultBackupErrorCode.unsupportedManifestVersion),
        ),
      );
    });

    test('path traversal is rejected before database mutation', () async {
      final database = h.newDatabase();
      final backup = await Directory(
        p.join(h.temp.path, 'path-traversal'),
      ).create();
      await Directory(p.join(backup.path, 'media')).create();
      await h.writeManifest(backup.path, {
        'version': 2,
        'albums': <Object>[],
        'membership': <Object>[],
        'media': [
          {
            'id': 'unsafe-media-id',
            'file': '../outside.jpg',
            'originalName': 'outside.jpg',
            'isVideo': false,
          },
        ],
      });

      await expectLater(
        h.service(database).importFromDirectory(backup.path),
        throwsA(backupError(VaultBackupErrorCode.unsafePath)),
      );

      expect(await database.getMediaById('unsafe-media-id'), isNull);
    });

    test('declared payload length mismatch is rejected', () async {
      final backup = await h.exportFixture(directoryName: 'wrong-length');
      final manifest = await h.readManifest(backup);
      final media = h.onlyMedia(manifest);
      media['byteLength'] = (media['byteLength'] as int) + 1;
      media['sizeBytes'] = (media['sizeBytes'] as int) + 1;
      manifest['totalBytes'] = (manifest['totalBytes'] as int) + 1;
      await h.writeManifest(backup, manifest);
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.payloadLengthMismatch)),
      );

      expect(await database.getMediaById('fixture-media-id'), isNull);
    });

    test('declared payload digest mismatch is rejected', () async {
      final backup = await h.exportFixture(directoryName: 'wrong-digest');
      final manifest = await h.readManifest(backup);
      h.onlyMedia(manifest)['sha256'] = digestFor('different-payload');
      await h.writeManifest(backup, manifest);
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.payloadDigestMismatch)),
      );

      expect(await database.getMediaById('fixture-media-id'), isNull);
    });

    test('tampered payload is rejected', () async {
      final backup = await h.exportFixture(directoryName: 'tampered-payload');
      final payload = await _restorePayload(h, backup);
      final original = await payload.readAsString();
      await payload.writeAsString(original.split('').reversed.join());
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.payloadDigestMismatch)),
      );

      expect(await database.getMediaById('fixture-media-id'), isNull);
    });

    test('missing payload is rejected', () async {
      final backup = await h.exportFixture(directoryName: 'missing-payload');
      await (await _restorePayload(h, backup)).delete();
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.payloadMissing)),
      );

      expect(await database.getMediaById('fixture-media-id'), isNull);
    });

    test('malformed JSON is reported explicitly', () async {
      final backup = await Directory(
        p.join(h.temp.path, 'malformed-json'),
      ).create();
      await File(
        p.join(backup.path, VaultBackupService.manifestName),
      ).writeAsString('{not-json');
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup.path),
        throwsA(backupError(VaultBackupErrorCode.malformedManifest)),
      );
    });

    test('invalid v5 dates are rejected at the manifest boundary', () async {
      final backup = await h.exportFixture(directoryName: 'invalid-date');
      final manifest = await h.readManifest(backup);
      manifest['verifiedAt'] = 'not-a-date';
      await h.writeManifest(backup, manifest);
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.malformedManifest)),
      );
    });

    test('missing v5 structural list is rejected at the manifest boundary',
        () async {
      final backup = await h.exportFixture(directoryName: 'missing-list');
      final manifest = await h.readManifest(backup);
      manifest.remove('membership');
      await h.writeManifest(backup, manifest);
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.malformedManifest)),
      );
    });

    test('dangling v5 membership is rejected before file installation',
        () async {
      final backup = await h.exportFixture(directoryName: 'dangling-member');
      final manifest = await h.readManifest(backup);
      (manifest['membership'] as List<dynamic>).add({
        'albumId': 'missing-album-id',
        'mediaId': 'fixture-media-id',
        'addedAt': '2026-07-22T00:00:00.000Z',
      });
      await h.writeManifest(backup, manifest);
      final database = h.newDatabase();

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.malformedManifest)),
      );

      expect(await database.getMediaById('fixture-media-id'), isNull);
      expect(await h.vaultFiles(), isEmpty);
    });

    test(
      'manifest symlink is rejected',
      () async {
        final backup = await h.exportFixture(directoryName: 'manifest-link');
        final manifest = File(
          p.join(backup, VaultBackupService.manifestName),
        );
        final external = File(p.join(h.temp.path, 'linked-manifest.json'));
        await external.writeAsBytes(await manifest.readAsBytes());
        await manifest.delete();
        await Link(manifest.path).create(external.path);
        final database = h.newDatabase();

        await expectLater(
          h.service(database).importFromDirectory(backup),
          throwsA(backupError(VaultBackupErrorCode.unsafePath)),
        );
      },
      skip: Platform.isWindows ? 'Symbolic link test requires POSIX.' : false,
    );

    test(
      'media directory symlink is rejected',
      () async {
        final backup = await h.exportFixture(directoryName: 'media-dir-link');
        final media = Directory(p.join(backup, 'media'));
        final target = await media.rename(p.join(backup, 'real-media'));
        await Link(media.path).create(target.path);
        final database = h.newDatabase();

        await expectLater(
          h.service(database).importFromDirectory(backup),
          throwsA(backupError(VaultBackupErrorCode.unsafePath)),
        );

        expect(await database.getMediaById('fixture-media-id'), isNull);
      },
      skip: Platform.isWindows ? 'Symbolic link test requires POSIX.' : false,
    );

    test(
      'payload symlink is rejected',
      () async {
        final backup = await h.exportFixture(directoryName: 'payload-link');
        final payload = await _restorePayload(h, backup);
        final external = File(p.join(h.temp.path, 'linked-payload.jpg'));
        await external.writeAsBytes(await payload.readAsBytes());
        await payload.delete();
        await Link(payload.path).create(external.path);
        final database = h.newDatabase();

        await expectLater(
          h.service(database).importFromDirectory(backup),
          throwsA(backupError(VaultBackupErrorCode.unsafePath)),
        );

        expect(await database.getMediaById('fixture-media-id'), isNull);
      },
      skip: Platform.isWindows ? 'Symbolic link test requires POSIX.' : false,
    );

    test('structural preflight failure leaves existing state untouched',
        () async {
      final backup = await h.exportFixture(directoryName: 'preflight-state');
      final manifest = await h.readManifest(backup);
      (manifest['membership'] as List<dynamic>).add({
        'albumId': 'unknown-album',
        'mediaId': 'fixture-media-id',
        'addedAt': '2026-07-22T00:00:00.000Z',
      });
      await h.writeManifest(backup, manifest);
      final database = h.newDatabase();
      await h.addMedia(database, id: 'existing-media', contents: 'existing');

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(backupError(VaultBackupErrorCode.malformedManifest)),
      );

      expect(await database.getMediaById('existing-media'), isNotNull);
      expect(await database.getMediaById('fixture-media-id'), isNull);
      expect(await h.vaultFiles(), isEmpty);
    });

    test('existing media id with different bytes fails as a conflict',
        () async {
      final backup = await h.exportFixture(directoryName: 'existing-conflict');
      final database = h.newDatabase();
      final existingPath = await h.addMedia(
        database,
        id: 'fixture-media-id',
        contents: 'different-existing-bytes',
      );

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(
          backupErrorAt(
            VaultBackupErrorCode.destinationConflict,
            VaultBackupStage.checkingBackup,
          ),
        ),
      );

      expect(
        await File(existingPath).readAsString(),
        'different-existing-bytes',
      );
      expect(await h.vaultFiles(), isEmpty);
    });

    test('database failure rolls back media albums memberships and files',
        () async {
      final sourceDb = h.newDatabase();
      final sourceAlbums = AlbumRepository(sourceDb);
      await sourceAlbums.insertWithId(
        id: 'rollback-album',
        name: 'Rollback Album',
        createdAt: DateTime.utc(2026, 7, 22),
      );
      await h.addMedia(sourceDb, id: 'rollback-media');
      await sourceAlbums.addMediaToUserAlbum(
        'rollback-album',
        'rollback-media',
      );
      final backup = p.join(h.temp.path, 'database-rollback');
      await h.service(sourceDb).exportToDirectory(backup);
      await sourceDb.close();
      h.databases.remove(sourceDb);
      final database = h.newDatabase(interceptor: FailingMembershipInsert());

      await expectLater(
        h.service(database).importFromDirectory(backup),
        throwsA(
          backupErrorAt(
            VaultBackupErrorCode.databaseWriteFailed,
            VaultBackupStage.restoring,
          ),
        ),
      );

      expect(await database.getMediaById('rollback-media'), isNull);
      expect(await database.getAlbumById('rollback-album'), isNull);
      expect(await h.vaultFiles(), isEmpty);
    });

    test('restore cancellation removes installed files and skips database',
        () async {
      final backup = await h.exportFixture(directoryName: 'cancel-restore');
      final database = h.newDatabase();
      final session = VaultBackupSession();

      final result = await h.service(database).importFromDirectory(
        backup,
        session: session,
        onProgress: (progress) {
          if (progress.stage == VaultBackupStage.restoring &&
              progress.completed == 0) {
            session.cancel();
          }
        },
      );

      expect(result.status, VaultBackupResultStatus.cancelled);
      expect(result.itemCount, 0);
      expect(await database.getMediaById('fixture-media-id'), isNull);
      expect(await h.vaultFiles(), isEmpty);
    });

    test('completed progress observer failure does not roll back restore',
        () async {
      final backup = await h.exportFixture(directoryName: 'observer-restore');
      final database = h.newDatabase();

      final result = await h.service(database).importFromDirectory(
        backup,
        onProgress: (progress) {
          if (progress.stage == VaultBackupStage.completed) {
            throw StateError('disposed observer');
          }
        },
      );

      expect(result.status, VaultBackupResultStatus.completed);
      expect(result.itemCount, 1);
      expect(await database.getMediaById('fixture-media-id'), isNotNull);
      expect(await h.vaultFiles(), hasLength(1));
    });
  });
}

Future<File> _restorePayload(
  VaultBackupTestHarness h,
  String backup,
) async {
  final manifest = await h.readManifest(backup);
  return File(p.join(backup, 'media', h.onlyMedia(manifest)['file'] as String));
}
