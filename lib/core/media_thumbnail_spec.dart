/// Shared thumbnail contract for Visible and Invisible media surfaces.
abstract final class MediaThumbnailSpec {
  /// Covers a two-column grid on common high-density Android displays without
  /// retaining full-resolution video frames in memory.
  static const int dimension = 768;

  /// Unified decode size for grid tiles in both the Visible and Invisible
  /// tabs. Smaller than [dimension] so on-demand video decoding is cheaper,
  /// while [dimension] stays the persisted poster / viewer resolution.
  static const int gridDimension = 512;

  static const int quality = 90;

  /// Video poster frame selector passed to photo_manager/Glide.
  ///
  /// `-1` is Glide's `DEFAULT_FRAME`, which makes `MediaMetadataRetriever`
  /// return `getFrameAtTime()`'s representative frame — the exact frame the
  /// built-in system gallery/media browser shows. A positive value would target
  /// that microsecond timestamp instead (e.g. the 1s frame) and diverge from the
  /// system poster. The native fallback mirrors this via `ThumbnailUtils`.
  static const int videoFrameUs = -1;

  static const int memoryCacheEntries = 120;

  /// v3 = posters use the platform representative frame (see [videoFrameUs]).
  /// Bumping invalidates v2 video posters so launch repair regenerates them to
  /// match the built-in system gallery.
  static const int fileVersion = 3;

  static String fileName(String mediaId) => '$mediaId.v$fileVersion.jpg';

  static bool isCurrentPath(String? path) =>
      path?.toLowerCase().endsWith('.v$fileVersion.jpg') ?? false;
}
