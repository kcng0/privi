part of 'vault_backup_service.dart';

final class _VaultBackupManifestCodec {
  const _VaultBackupManifestCodec();

  static const _parser = _VaultBackupManifestParser();
  static const _validator = _VaultBackupManifestValidator();

  _BackupManifest fromExport({
    required List<_ExportEntry> entries,
    required List<AlbumRow> albums,
    required List<AlbumGroupRow> groups,
    required List<AlbumMediaRow> memberships,
    required String platformName,
    required DateTime verifiedAt,
  }) {
    final media = entries
        .map(
          (entry) => _ManifestMedia(
            id: entry.row.id,
            fileName: entry.fileName,
            thumbnailName: entry.thumbnailName,
            sha256: entry.sha256,
            byteLength: entry.byteLength,
            originalPath: entry.row.originalPath,
            source: entry.row.sourcePlatformId == null
                ? null
                : _ManifestSource(
                    platform: platformName,
                    libraryId: entry.row.sourcePlatformId!,
                  ),
            sourceRemovalPending: entry.row.sourceRemovalPending,
            contentDigest: entry.row.contentDigest,
            originalName: entry.row.originalName,
            mimeType: entry.row.mimeType,
            isVideo: entry.row.isVideo,
            width: entry.row.width,
            height: entry.row.height,
            durationMs: entry.row.durationMs,
            rating: entry.row.rating,
            dateAdded: entry.row.dateAdded,
            dateTaken: entry.row.dateTaken,
            sizeBytes: entry.byteLength,
            deletedAt: entry.row.deletedAt,
          ),
        )
        .toList(growable: false);
    final manifest = _BackupManifest(
      version: VaultBackupService.manifestVersion,
      exportedAt: verifiedAt,
      verifiedAt: verifiedAt,
      declaredItemCount: media.length,
      declaredTotalBytes: entries.fold<int>(
        0,
        (sum, entry) => sum + entry.byteLength,
      ),
      media: List.unmodifiable(media),
      albums: List.unmodifiable(
        albums.map(
          (album) => _ManifestAlbum(
            id: album.id,
            name: album.name,
            isSystem: album.isSystem,
            coverMediaId: album.coverMediaId,
            createdAt: album.createdAt,
            systemKind: album.systemKind,
            pinnedAt: album.pinnedAt,
            rating: album.rating,
            sortIndex: album.sortIndex,
            groupId: album.groupId,
          ),
        ),
      ),
      groups: List.unmodifiable(
        groups.map(
          (group) => _ManifestGroup(
            id: group.id,
            name: group.name,
            createdAt: group.createdAt,
            sortIndex: group.sortIndex,
          ),
        ),
      ),
      memberships: List.unmodifiable(
        memberships.map(
          (membership) => _ManifestMembership(
            albumId: membership.albumId,
            mediaId: membership.mediaId,
            addedAt: membership.addedAt,
          ),
        ),
      ),
    );
    validateV5(manifest);
    return manifest;
  }

  Future<_BackupManifest> read(String sourceDirectory) async {
    final manifestFile = await _validatedManifestFile(sourceDirectory);
    dynamic decoded;
    try {
      decoded = jsonDecode(await manifestFile.readAsString());
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
    if (decoded is! Map) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final manifest = _parser.parse(Map<String, dynamic>.from(decoded));
    validateV5(manifest);
    return manifest;
  }

  Future<void> write(File file, _BackupManifest manifest) async {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson(manifest)),
      flush: true,
    );
    if (!await file.exists() || await file.length() == 0) {
      throw const VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        stage: VaultBackupStage.writingManifest,
      );
    }
  }

  Map<String, dynamic> toJson(_BackupManifest manifest) => {
        'version': manifest.version,
        'exportedAt': manifest.exportedAt?.toIso8601String(),
        'verifiedAt': manifest.verifiedAt?.toIso8601String(),
        'itemCount': manifest.declaredItemCount,
        'totalBytes': manifest.declaredTotalBytes,
        'media': manifest.media.map((item) => item.toJson()).toList(),
        'albums': manifest.albums.map((item) => item.toJson()).toList(),
        'albumGroups': manifest.groups.map((item) => item.toJson()).toList(),
        'membership':
            manifest.memberships.map((item) => item.toJson()).toList(),
      };

  void validateV5Summary(_BackupManifest manifest) {
    _validator.validateSummary(manifest);
  }

  void validateV5(_BackupManifest manifest) => _validator.validate(manifest);

  Future<File> _validatedManifestFile(String sourceDirectory) async {
    final root = Directory(sourceDirectory);
    if (!await root.exists()) {
      throw const VaultBackupException(
        VaultBackupErrorCode.manifestMissing,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final file = File(
      p.join(sourceDirectory, VaultBackupService.manifestName),
    );
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const VaultBackupException(
        VaultBackupErrorCode.manifestMissing,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (type == FileSystemEntityType.link) {
      throw const VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: VaultBackupService.manifestName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (type != FileSystemEntityType.file) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: VaultBackupService.manifestName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      final canonicalRoot = await root.resolveSymbolicLinks();
      final canonicalFile = await file.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalFile)) {
        throw const VaultBackupException(
          VaultBackupErrorCode.unsafePath,
          fileName: VaultBackupService.manifestName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return file;
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: VaultBackupService.manifestName,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }
}
