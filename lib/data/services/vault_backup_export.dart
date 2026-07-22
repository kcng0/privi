part of 'vault_backup_service.dart';

final class _VaultBackupExporter {
  _VaultBackupExporter({
    required this.db,
    required this.uuid,
    required this.platformName,
  });

  final AppDatabase db;
  final Uuid uuid;
  final String platformName;
  final _VaultBackupFileOps files = const _VaultBackupFileOps();
  final _VaultBackupManifestCodec manifests = const _VaultBackupManifestCodec();

  Future<VaultBackupResult> run(
    String destinationPath, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) async {
    final activeSession = session ?? VaultBackupSession();
    Directory? staging;
    Directory? createdMediaDirectory;
    final committed = <File>[];
    var failureStage = VaultBackupStage.preparing;
    try {
      final snapshot = await _loadSnapshot();
      final rows = snapshot.media;
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.preparing,
        0,
        rows.length,
      );

      failureStage = VaultBackupStage.checkingSource;
      final entries = await _preflightSources(
        rows,
        activeSession,
        onProgress,
      );
      _checkBackupCancelled(activeSession);

      failureStage = VaultBackupStage.writingManifest;
      final destination = await _prepareDestination(
        destinationPath,
        entries,
      );
      final mediaDirectory = Directory(p.join(destination.path, 'media'));
      staging = Directory(
        p.join(destination.path, '.privi-export-${uuid.v4()}'),
      );
      final stagingMedia = Directory(p.join(staging.path, 'media'));
      await stagingMedia.create(recursive: true);

      failureStage = VaultBackupStage.copying;
      final stagedEntries = await _stagePayloads(
        entries,
        stagingMedia,
        activeSession,
        onProgress,
      );
      _checkBackupCancelled(activeSession);
      failureStage = VaultBackupStage.writingManifest;
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.writingManifest,
        rows.length,
        rows.length,
      );
      final manifest = manifests.fromExport(
        entries: stagedEntries,
        albums: snapshot.albums,
        groups: snapshot.groups,
        memberships: snapshot.memberships,
        platformName: platformName,
        verifiedAt: DateTime.now().toUtc(),
      );
      final stagedManifest = File(
        p.join(staging.path, VaultBackupService.manifestName),
      );
      await manifests.write(stagedManifest, manifest);
      await manifests.read(staging.path);

      if (!await mediaDirectory.exists()) {
        await mediaDirectory.create();
        createdMediaDirectory = mediaDirectory;
      }
      await _commitNewFiles(
        stagingMedia: stagingMedia,
        stagedManifest: stagedManifest,
        destination: destination,
        mediaDirectory: mediaDirectory,
        entries: stagedEntries,
        committed: committed,
      );
      failureStage = VaultBackupStage.checkingBackup;
      await _verifyCommittedExport(
        destination: destination,
        mediaDirectory: mediaDirectory,
        entries: stagedEntries,
        session: activeSession,
        onProgress: onProgress,
      );
      await files.removeDirectory(staging);
      staging = null;

      _emitBackupProgress(
        onProgress,
        VaultBackupStage.completed,
        rows.length,
        rows.length,
      );
      return VaultBackupResult(
        itemCount: stagedEntries.length,
        totalBytes: manifest.declaredTotalBytes!,
        checksumsVerified: true,
        status: VaultBackupResultStatus.completed,
      );
    } on _VaultBackupCancelled {
      await _rollback(
        committed,
        staging: staging,
        createdMediaDirectory: createdMediaDirectory,
      );
      return const VaultBackupResult(
        itemCount: 0,
        totalBytes: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      );
    } on VaultBackupException {
      await _rollback(
        committed,
        staging: staging,
        createdMediaDirectory: createdMediaDirectory,
      );
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('vault export failed: $error\n$stackTrace');
      await _rollback(
        committed,
        staging: staging,
        createdMediaDirectory: createdMediaDirectory,
      );
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        stage: failureStage,
        cause: error,
      );
    }
  }

  Future<_ExportSnapshot> _loadSnapshot() {
    return db.transaction(() async {
      final active = await db.listActiveMediaRows();
      final deleted = await db.listRecycleBinRows();
      return _ExportSnapshot(
        media: List.unmodifiable([...active, ...deleted]),
        albums: List.unmodifiable(await db.getAllAlbums()),
        groups: List.unmodifiable(await db.getAllAlbumGroups()),
        memberships: List.unmodifiable(await db.getAllMemberships()),
      );
    });
  }

  Future<List<_ExportEntry>> _preflightSources(
    List<MediaItemRow> rows,
    VaultBackupSession session,
    VaultBackupProgressCallback? onProgress,
  ) async {
    final entries = <_ExportEntry>[];
    final names = <String>{};
    for (var index = 0; index < rows.length; index++) {
      _checkBackupCancelled(session);
      final row = rows[index];
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.checkingSource,
        index,
        rows.length,
        row.originalName,
      );
      final id = _validatedBackupId(row.id, 'media id');
      final fileName = '$id${p.extension(row.privatePath)}';
      _validateBackupName(fileName);
      if (!names.add(fileName)) {
        throw VaultBackupException(
          VaultBackupErrorCode.destinationConflict,
          fileName: fileName,
          stage: VaultBackupStage.checkingSource,
        );
      }
      final source = File(row.privatePath);
      final sourceHash = await files.hashSource(
        source,
        row.originalName,
        expectedDigest: row.contentDigest,
      );
      entries.add(
        _ExportEntry(
          row: row,
          source: source,
          fileName: fileName,
          byteLength: sourceHash.length,
          sha256: sourceHash.digest,
        ),
      );
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.checkingSource,
        index + 1,
        rows.length,
      );
    }
    return List.unmodifiable(entries);
  }

  Future<Directory> _prepareDestination(
    String destinationPath,
    List<_ExportEntry> entries,
  ) async {
    final destination = Directory(destinationPath);
    final destinationType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (destinationType == FileSystemEntityType.notFound) {
      await destination.create(recursive: true);
    } else if (destinationType == FileSystemEntityType.link) {
      throw VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: p.basename(destination.path),
        stage: VaultBackupStage.writingManifest,
      );
    } else if (destinationType != FileSystemEntityType.directory) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: p.basename(destination.path),
        stage: VaultBackupStage.writingManifest,
      );
    }

    await _requireMissing(
      p.join(destination.path, VaultBackupService.manifestName),
    );
    final mediaDirectory = Directory(p.join(destination.path, 'media'));
    final mediaType = await FileSystemEntity.type(
      mediaDirectory.path,
      followLinks: false,
    );
    if (mediaType == FileSystemEntityType.link) {
      throw const VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: 'media',
        stage: VaultBackupStage.writingManifest,
      );
    }
    if (mediaType != FileSystemEntityType.notFound &&
        mediaType != FileSystemEntityType.directory) {
      throw const VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: 'media',
        stage: VaultBackupStage.writingManifest,
      );
    }
    if (mediaType == FileSystemEntityType.directory) {
      for (final entry in entries) {
        await _requireMissing(p.join(mediaDirectory.path, entry.fileName));
        final thumbnailName = '${entry.row.id}.thumb.png';
        await _requireMissing(p.join(mediaDirectory.path, thumbnailName));
      }
    }
    return destination;
  }

  Future<void> _requireMissing(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: p.basename(path),
        stage: VaultBackupStage.writingManifest,
      );
    }
  }

  Future<List<_ExportEntry>> _stagePayloads(
    List<_ExportEntry> entries,
    Directory stagingMedia,
    VaultBackupSession session,
    VaultBackupProgressCallback? onProgress,
  ) async {
    final staged = <_ExportEntry>[];
    for (var index = 0; index < entries.length; index++) {
      _checkBackupCancelled(session);
      final entry = entries[index];
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.copying,
        index,
        entries.length,
        entry.row.originalName,
      );
      await files.copyAndVerify(
        source: entry.source,
        target: File(p.join(stagingMedia.path, entry.fileName)),
        expectedLength: entry.byteLength,
        expectedDigest: entry.sha256,
        fileName: entry.row.originalName,
        mismatchCode: VaultBackupErrorCode.sourceChanged,
        stage: VaultBackupStage.copying,
      );
      final thumbnailName = await _copyOptionalThumbnail(
        entry.row,
        stagingMedia,
      );
      staged.add(entry.withThumbnail(thumbnailName));
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.copying,
        index + 1,
        entries.length,
      );
    }
    return List.unmodifiable(staged);
  }

  Future<String?> _copyOptionalThumbnail(
    MediaItemRow row,
    Directory stagingMedia,
  ) async {
    final rawPath = row.thumbnailPath;
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    final source = File(rawPath);
    if (!await source.exists()) return null;
    final name = '${_validatedBackupId(row.id, 'media id')}.thumb.png';
    final target = File(p.join(stagingMedia.path, name));
    try {
      await source.openRead().pipe(target.openWrite());
      if (await target.length() == 0) {
        await target.delete();
        return null;
      }
      return name;
    } catch (error, stackTrace) {
      debugPrint('optional backup thumbnail skipped: $error\n$stackTrace');
      if (await target.exists()) await target.delete();
      return null;
    }
  }

  Future<void> _commitNewFiles({
    required Directory stagingMedia,
    required File stagedManifest,
    required Directory destination,
    required Directory mediaDirectory,
    required List<_ExportEntry> entries,
    required List<File> committed,
  }) async {
    for (final entry in entries) {
      await _commitNewFile(
        File(p.join(stagingMedia.path, entry.fileName)),
        File(p.join(mediaDirectory.path, entry.fileName)),
        committed,
      );
      final thumbnailName = entry.thumbnailName;
      if (thumbnailName != null) {
        await _commitNewFile(
          File(p.join(stagingMedia.path, thumbnailName)),
          File(p.join(mediaDirectory.path, thumbnailName)),
          committed,
        );
      }
    }
    await _commitNewFile(
      stagedManifest,
      File(p.join(destination.path, VaultBackupService.manifestName)),
      committed,
    );
  }

  Future<void> _commitNewFile(
    File staged,
    File target,
    List<File> committed,
  ) async {
    await _requireMissing(target.path);
    await staged.rename(target.path);
    committed.add(target);
  }

  Future<void> _verifyCommittedExport({
    required Directory destination,
    required Directory mediaDirectory,
    required List<_ExportEntry> entries,
    required VaultBackupSession session,
    required VaultBackupProgressCallback? onProgress,
  }) async {
    try {
      final manifest = await manifests.read(destination.path);
      manifests.validateV5(manifest);
      if (manifest.media.length != entries.length) {
        throw const VaultBackupException(
          VaultBackupErrorCode.destinationWriteFailed,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final byFile = {for (final item in manifest.media) item.fileName: item};
      if (byFile.length != entries.length) {
        throw const VaultBackupException(
          VaultBackupErrorCode.destinationWriteFailed,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      for (var index = 0; index < entries.length; index++) {
        _checkBackupCancelled(session);
        final entry = entries[index];
        _emitBackupProgress(
          onProgress,
          VaultBackupStage.checkingBackup,
          index,
          entries.length,
          entry.row.originalName,
        );
        final manifestEntry = byFile[entry.fileName];
        if (manifestEntry == null ||
            manifestEntry.byteLength != entry.byteLength ||
            manifestEntry.sha256 != entry.sha256) {
          throw VaultBackupException(
            VaultBackupErrorCode.destinationWriteFailed,
            fileName: entry.row.originalName,
            stage: VaultBackupStage.checkingBackup,
          );
        }
        await files.hashPayload(
          File(p.join(mediaDirectory.path, entry.fileName)),
          entry.row.originalName,
          expectedLength: entry.byteLength,
          expectedDigest: entry.sha256,
        );
        _emitBackupProgress(
          onProgress,
          VaultBackupStage.checkingBackup,
          index + 1,
          entries.length,
        );
      }
      _checkBackupCancelled(session);
    } on _VaultBackupCancelled {
      rethrow;
    } on VaultBackupException catch (error) {
      if (error.code == VaultBackupErrorCode.destinationWriteFailed) rethrow;
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        fileName: error.fileName,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  Future<void> _rollback(
    List<File> committed, {
    required Directory? staging,
    required Directory? createdMediaDirectory,
  }) async {
    Object? firstError;
    try {
      await files.removeFiles(committed.reversed);
    } catch (error) {
      firstError = error;
    }
    if (createdMediaDirectory != null) {
      try {
        if (await createdMediaDirectory.exists() &&
            await createdMediaDirectory.list().isEmpty) {
          await createdMediaDirectory.delete();
        }
      } catch (error, stackTrace) {
        debugPrint(
          'vault backup directory rollback failed: $error\n$stackTrace',
        );
        firstError ??= error;
      }
    }
    if (staging != null) {
      try {
        await files.removeDirectory(staging);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        cause: firstError,
      );
    }
  }
}
