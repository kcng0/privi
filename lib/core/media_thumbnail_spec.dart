/// Shared thumbnail contract for Visible and Invisible media surfaces.
abstract final class MediaThumbnailSpec {
  /// Covers a two-column grid on common high-density Android displays without
  /// retaining full-resolution video frames in memory.
  static const int dimension = 768;

  static const int quality = 90;

  /// Android's thumbnail API expects a video frame timestamp in microseconds.
  static const int videoFrameUs = 1000000;

  static const int memoryCacheEntries = 120;

  static const int fileVersion = 2;

  static String fileName(String mediaId) => '$mediaId.v$fileVersion.jpg';

  static bool isCurrentPath(String? path) =>
      path?.toLowerCase().endsWith('.v$fileVersion.jpg') ?? false;
}
