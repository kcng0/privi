import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MediaStore index maintenance for hide / unhide.
///
/// Hide must **remove** MediaStore rows (not re-scan the hidden path), otherwise
/// Gallery / 媒体浏览器 keep showing the item under the new name.
class MediaStoreService {
  static const _channel = MethodChannel('com.privateheart.vault/mediastore');

  /// Attempt to delete a content URI from MediaStore.
  Future<bool> removeOriginal(String? contentUri) async {
    if (contentUri == null || contentUri.isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'removeOriginal',
        {'uri': contentUri},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Soft-hide / drop MediaStore index for a path.
  /// After a vault move the original path no longer exists → index rows deleted.
  Future<bool> purgePath(String path) async {
    if (path.isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'purgeMediaStorePath',
        {'path': path},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('purgePath: $e');
      return false;
    }
  }

  /// Absolute path for a MediaStore / photo_manager asset id.
  Future<String?> resolveMediaPath({
    required String id,
    required bool isVideo,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'resolveMediaPath',
        {'id': id, 'isVideo': isVideo},
      );
      return result;
    } catch (e) {
      debugPrint('resolveMediaPath: $e');
      return null;
    }
  }

  /// Capture/taken time in Unix **seconds**.
  ///
  /// Sources (never mtime): MediaStore DATE_TAKEN → EXIF → video metadata.
  /// Returns null when unknown.
  Future<int?> resolveCaptureDateSec({
    String? path,
    String? mediaId,
    required bool isVideo,
  }) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'resolveCaptureDate',
        {
          'path': path,
          'mediaId': mediaId,
          'isVideo': isVideo,
        },
      );
      if (result is int) return result;
      if (result is num) return result.toInt();
      return int.tryParse('$result');
    } catch (e) {
      debugPrint('resolveCaptureDate: $e');
      return null;
    }
  }

  /// Re-index a path into MediaStore (unhide).
  ///
  /// When [dateTakenSec] / [dateAddedSec] are set (Unix seconds), they are
  /// written onto the MediaStore row so Gallery sorts by original capture time
  /// instead of scan/unhide time.
  Future<bool> scanPath(
    String path, {
    String? mimeType,
    int? dateTakenSec,
    int? dateAddedSec,
  }) async {
    if (path.isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'scanMediaPath',
        {
          'path': path,
          'mimeType': mimeType,
          if (dateTakenSec != null) 'dateTakenSec': dateTakenSec,
          if (dateAddedSec != null) 'dateAddedSec': dateAddedSec,
        },
      );
      return result ?? false;
    } catch (e) {
      debugPrint('scanPath: $e');
      return false;
    }
  }
}
