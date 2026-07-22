part of 'vault_backup_service.dart';

final class _VaultBackupManifestValidator {
  const _VaultBackupManifestValidator();

  void validateSummary(_BackupManifest manifest) {
    if (manifest.version < VaultBackupService.manifestVersion) return;
    final itemCount = manifest.declaredItemCount;
    final totalBytes = manifest.declaredTotalBytes;
    if (manifest.exportedAt == null ||
        manifest.verifiedAt == null ||
        itemCount == null ||
        totalBytes == null ||
        itemCount < 0 ||
        totalBytes < 0 ||
        itemCount != manifest.media.length ||
        totalBytes != manifest.payloadBytes) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        stage: VaultBackupStage.checkingBackup,
      );
    }
  }

  void validate(_BackupManifest manifest) {
    validateSummary(manifest);
    if (manifest.version < VaultBackupService.manifestVersion) return;

    final mediaIds = <String>{};
    final referencedNames = <String>{};
    for (final media in manifest.media) {
      final id = media.id!;
      _requireUnique(mediaIds, id, media.originalName ?? media.fileName);
      _requireUnique(referencedNames, media.fileName, media.fileName);
      final thumbnailName = media.thumbnailName;
      if (thumbnailName != null) {
        _requireUnique(referencedNames, thumbnailName, thumbnailName);
      }
    }

    final groupIds = <String>{};
    for (final group in manifest.groups) {
      _requireUnique(groupIds, group.id!, group.name!);
    }

    final userAlbumIds = <String>{};
    final albumIds = <String>{};
    for (final album in manifest.albums) {
      final id = album.id!;
      _requireUnique(albumIds, id, album.name!);
      if (!album.isSystem) userAlbumIds.add(id);
      _requireReference(mediaIds, album.coverMediaId);
      _requireReference(groupIds, album.groupId);
    }

    final membershipKeys = <String>{};
    for (final membership in manifest.memberships) {
      final albumId = membership.albumId!;
      final mediaId = membership.mediaId!;
      _requireUnique(
        membershipKeys,
        '$albumId\u0000$mediaId',
        mediaId,
      );
      if (!userAlbumIds.contains(albumId) || !mediaIds.contains(mediaId)) {
        _throwMalformedManifest(mediaId);
      }
    }
  }

  void _requireUnique(Set<String> values, String value, String fileName) {
    if (!values.add(value)) _throwMalformedManifest(fileName);
  }

  void _requireReference(Set<String> ids, String? referencedId) {
    if (referencedId != null && !ids.contains(referencedId)) {
      _throwMalformedManifest(referencedId);
    }
  }
}

Never _throwMalformedManifest(String fileName) {
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: fileName,
    stage: VaultBackupStage.checkingBackup,
  );
}
