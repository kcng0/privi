/// Domain media item. Maps from Drift rows at the repository boundary.
/// See docs/03-architecture/data-model.md.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.privatePath,
    this.originalPath,
    required this.originalName,
    required this.mimeType,
    required this.isVideo,
    required this.rating,
    required this.dateAdded,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.dateTaken,
    this.thumbnailPath,
    this.deletedAt,
    this.sourcePlatformId,
    this.sourceRemovalPending = false,
    this.contentDigest,
  });

  final String id;
  final String privatePath;

  /// Pre-hide absolute path for unhide; null on legacy rows.
  final String? originalPath;
  final String originalName;
  final String mimeType;
  final bool isVideo;
  final int? width;
  final int? height;
  final int? durationMs;
  final int rating; // 0–3
  final DateTime dateAdded;
  final DateTime? dateTaken;
  final int sizeBytes;
  final String? thumbnailPath;
  final DateTime? deletedAt;

  /// Opaque platform identity (for example a PhotoKit localIdentifier).
  /// Never use this value as a filesystem path.
  final String? sourcePlatformId;

  /// True when a verified vault copy exists but the system-library source has
  /// not yet been removed. This is a recoverable, non-success state.
  final bool sourceRemovalPending;

  /// SHA-256 digest of the verified vault bytes, when available.
  final String? contentDigest;

  bool get isDeleted => deletedAt != null;
  bool get isFavorite => rating >= 1;

  /// Prefer thumbnail. Videos without a still fall back to [privatePath]
  /// (grid should treat that as missing and show a placeholder).
  String get displayPath => (thumbnailPath != null && thumbnailPath!.isNotEmpty)
      ? thumbnailPath!
      : privatePath;

  /// True when we have a dedicated still to show in grids.
  bool get hasThumbnail =>
      thumbnailPath != null && thumbnailPath!.trim().isNotEmpty;

  MediaItem copyWith({
    String? id,
    String? privatePath,
    String? originalPath,
    String? originalName,
    String? mimeType,
    bool? isVideo,
    int? width,
    int? height,
    int? durationMs,
    int? rating,
    DateTime? dateAdded,
    DateTime? dateTaken,
    int? sizeBytes,
    String? thumbnailPath,
    DateTime? deletedAt,
    String? sourcePlatformId,
    bool? sourceRemovalPending,
    String? contentDigest,
    bool clearDeletedAt = false,
  }) {
    return MediaItem(
      id: id ?? this.id,
      privatePath: privatePath ?? this.privatePath,
      originalPath: originalPath ?? this.originalPath,
      originalName: originalName ?? this.originalName,
      mimeType: mimeType ?? this.mimeType,
      isVideo: isVideo ?? this.isVideo,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      rating: rating ?? this.rating,
      dateAdded: dateAdded ?? this.dateAdded,
      dateTaken: dateTaken ?? this.dateTaken,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      sourcePlatformId: sourcePlatformId ?? this.sourcePlatformId,
      sourceRemovalPending: sourceRemovalPending ?? this.sourceRemovalPending,
      contentDigest: contentDigest ?? this.contentDigest,
    );
  }
}
