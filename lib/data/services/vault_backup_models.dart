part of 'vault_backup_service.dart';

abstract interface class VaultBackupOperations {
  Future<VaultBackupResult> exportToDirectory(
    String destinationDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  });

  Future<VaultBackupResult> importFromDirectory(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  });
}

typedef VaultBackupProgressCallback = void Function(
  VaultBackupProgress progress,
);

enum VaultBackupStage {
  preparing,
  checkingSource,
  copying,
  writingManifest,
  checkingBackup,
  restoring,
  completed,
}

enum VaultBackupErrorCode {
  manifestMissing,
  malformedManifest,
  unsupportedManifestVersion,
  sourceMissing,
  sourceUnreadable,
  sourceEmpty,
  sourceChanged,
  payloadMissing,
  payloadUnreadable,
  payloadEmpty,
  payloadLengthMismatch,
  payloadDigestMismatch,
  unsafePath,
  destinationConflict,
  destinationWriteFailed,
  databaseWriteFailed,
}

enum VaultBackupResultStatus { completed, cancelled }

final class VaultBackupProgress {
  const VaultBackupProgress({
    required this.stage,
    required this.completed,
    required this.total,
    this.currentFile,
  });

  final VaultBackupStage stage;
  final int completed;
  final int total;
  final String? currentFile;

  double get fraction {
    if (total <= 0) return stage == VaultBackupStage.completed ? 1 : 0;
    return (completed / total).clamp(0.0, 1.0);
  }
}

final class VaultBackupSession {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

final class VaultBackupResult {
  const VaultBackupResult({
    required this.itemCount,
    this.totalBytes = 0,
    required this.checksumsVerified,
    required this.status,
  });

  final int itemCount;
  final int totalBytes;
  final bool checksumsVerified;
  final VaultBackupResultStatus status;

  bool get cancelled => status == VaultBackupResultStatus.cancelled;
}

final class VaultBackupException implements Exception {
  const VaultBackupException(
    this.code, {
    this.fileName,
    this.stage,
    this.cause,
  });

  final VaultBackupErrorCode code;
  final String? fileName;
  final VaultBackupStage? stage;
  final Object? cause;

  @override
  String toString() {
    final suffix = fileName == null ? '' : ' ($fileName)';
    return 'VaultBackupException.${code.name}$suffix';
  }
}

final class _VaultBackupCancelled implements Exception {}

final class _HashedFile {
  const _HashedFile({required this.length, required this.digest});

  final int length;
  final String digest;
}

final class _ExportSnapshot {
  const _ExportSnapshot({
    required this.media,
    required this.albums,
    required this.groups,
    required this.memberships,
  });

  final List<MediaItemRow> media;
  final List<AlbumRow> albums;
  final List<AlbumGroupRow> groups;
  final List<AlbumMediaRow> memberships;
}

final class _ExportEntry {
  const _ExportEntry({
    required this.row,
    required this.source,
    required this.fileName,
    required this.byteLength,
    required this.sha256,
    this.thumbnailName,
  });

  final MediaItemRow row;
  final File source;
  final String fileName;
  final int byteLength;
  final String sha256;
  final String? thumbnailName;

  _ExportEntry withThumbnail(String? value) => _ExportEntry(
        row: row,
        source: source,
        fileName: fileName,
        byteLength: byteLength,
        sha256: sha256,
        thumbnailName: value,
      );
}

final class _BackupManifest {
  const _BackupManifest({
    required this.version,
    required this.exportedAt,
    required this.verifiedAt,
    required this.declaredItemCount,
    required this.declaredTotalBytes,
    required this.media,
    required this.albums,
    required this.groups,
    required this.memberships,
  });

  final int version;
  final DateTime? exportedAt;
  final DateTime? verifiedAt;
  final int? declaredItemCount;
  final int? declaredTotalBytes;
  final List<_ManifestMedia> media;
  final List<_ManifestAlbum> albums;
  final List<_ManifestGroup> groups;
  final List<_ManifestMembership> memberships;

  int get payloadBytes => media.fold(
        0,
        (sum, item) => sum + (item.byteLength ?? 0),
      );
}

final class _ManifestSource {
  const _ManifestSource({required this.platform, required this.libraryId});

  final String platform;
  final String libraryId;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'libraryId': libraryId,
      };
}

final class _ManifestMedia {
  const _ManifestMedia({
    required this.id,
    required this.fileName,
    required this.thumbnailName,
    required this.sha256,
    required this.byteLength,
    required this.originalPath,
    required this.source,
    required this.sourceRemovalPending,
    required this.contentDigest,
    required this.originalName,
    required this.mimeType,
    required this.isVideo,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.rating,
    required this.dateAdded,
    required this.dateTaken,
    required this.sizeBytes,
    required this.deletedAt,
  });

  final String? id;
  final String fileName;
  final String? thumbnailName;
  final String? sha256;
  final int? byteLength;
  final String? originalPath;
  final _ManifestSource? source;
  final bool sourceRemovalPending;
  final String? contentDigest;
  final String? originalName;
  final String? mimeType;
  final bool? isVideo;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? rating;
  final DateTime? dateAdded;
  final DateTime? dateTaken;
  final int? sizeBytes;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'file': fileName,
        'thumb': thumbnailName,
        'sha256': sha256,
        'byteLength': byteLength,
        'originalPath': originalPath,
        'source': source?.toJson(),
        'sourceRemovalPending': sourceRemovalPending,
        'contentDigest': contentDigest,
        'originalName': originalName,
        'mimeType': mimeType,
        'isVideo': isVideo,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'rating': rating,
        'dateAdded': dateAdded?.toIso8601String(),
        'dateTaken': dateTaken?.toIso8601String(),
        'sizeBytes': sizeBytes,
        'deletedAt': deletedAt?.toIso8601String(),
      };
}

final class _ManifestAlbum {
  const _ManifestAlbum({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.coverMediaId,
    required this.createdAt,
    required this.systemKind,
    required this.pinnedAt,
    required this.rating,
    required this.sortIndex,
    required this.groupId,
  });

  final String? id;
  final String? name;
  final bool isSystem;
  final String? coverMediaId;
  final DateTime? createdAt;
  final String? systemKind;
  final DateTime? pinnedAt;
  final int? rating;
  final int? sortIndex;
  final String? groupId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isSystem': isSystem,
        'coverMediaId': coverMediaId,
        'createdAt': createdAt?.toIso8601String(),
        'systemKind': systemKind,
        'pinnedAt': pinnedAt?.toIso8601String(),
        'rating': rating,
        'sortIndex': sortIndex,
        'groupId': groupId,
      };
}

final class _ManifestGroup {
  const _ManifestGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sortIndex,
  });

  final String? id;
  final String? name;
  final DateTime? createdAt;
  final int? sortIndex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt?.toIso8601String(),
        'sortIndex': sortIndex,
      };
}

final class _ManifestMembership {
  const _ManifestMembership({
    required this.albumId,
    required this.mediaId,
    required this.addedAt,
  });

  final String? albumId;
  final String? mediaId;
  final DateTime? addedAt;

  Map<String, dynamic> toJson() => {
        'albumId': albumId,
        'mediaId': mediaId,
        'addedAt': addedAt?.toIso8601String(),
      };
}

final class _RestoreMediaPlan {
  const _RestoreMediaPlan({
    required this.media,
    required this.id,
    required this.originalName,
    required this.originalPath,
    required this.sourceFolder,
    required this.source,
    required this.thumbnail,
    required this.expectedLength,
    required this.expectedDigest,
    required this.skipExisting,
  });

  final _ManifestMedia media;
  final String id;
  final String originalName;
  final String? originalPath;
  final String sourceFolder;
  final File source;
  final File? thumbnail;
  final int expectedLength;
  final String expectedDigest;
  final bool skipExisting;
}

final class _InstalledFile {
  const _InstalledFile({required this.file, required this.created});

  final File file;
  final bool created;
}

final class _InstalledMedia {
  const _InstalledMedia({
    required this.plan,
    required this.destination,
    required this.thumbnailPath,
    required this.createdFiles,
  });

  final _RestoreMediaPlan plan;
  final File destination;
  final String? thumbnailPath;
  final List<File> createdFiles;
}
