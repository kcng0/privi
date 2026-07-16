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

  bool get isDeleted => deletedAt != null;
  bool get isFavorite => rating >= 1;

  /// Prefer thumbnail; fall back to full file for images.
  String get displayPath => (thumbnailPath != null && thumbnailPath!.isNotEmpty)
      ? thumbnailPath!
      : privatePath;

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
    );
  }
}
