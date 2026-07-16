import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a platform rename / hide.
class MediaRenameResult {
  const MediaRenameResult({
    required this.ok,
    this.newPath,
    this.error,
    this.needManageStorage = false,
    this.size,
  });

  final bool ok;
  final String? newPath;
  final String? error;
  final bool needManageStorage;
  final int? size;
}

/// Android MediaStore / filesystem hide helpers.
class MediaRenameService {
  static const _channel = MethodChannel('com.privateheart.vault/mediastore');

  Future<bool> isExternalStorageManager() async {
    try {
      final v = await _channel.invokeMethod<bool>('isExternalStorageManager');
      return v ?? false;
    } catch (e) {
      debugPrint('isExternalStorageManager: $e');
      return false;
    }
  }

  Future<void> openManageAllFilesSettings() async {
    try {
      await _channel.invokeMethod<void>('openManageAllFilesSettings');
    } catch (e) {
      debugPrint('openManageAllFilesSettings: $e');
    }
  }

  Future<MediaRenameResult> rename({
    required String path,
    required String newPath,
    required bool isVideo,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('renameMedia', {
        'path': path,
        'newPath': newPath,
        'isVideo': isVideo,
      });
      if (raw is! Map) {
        return const MediaRenameResult(ok: false, error: 'bad_response');
      }
      final map = Map<String, dynamic>.from(raw);
      return MediaRenameResult(
        ok: map['ok'] == true,
        newPath: map['newPath'] as String?,
        error: map['error'] as String?,
        needManageStorage: map['needManageStorage'] == true,
      );
    } catch (e) {
      debugPrint('renameMedia: $e');
      return MediaRenameResult(ok: false, error: '$e');
    }
  }

  /// Preferred hide: move/copy into `.privateheart_vault` and de-index original.
  Future<MediaRenameResult> hideToVault({
    String? path,
    String? mediaId,
    required String newPath,
    required bool isVideo,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('hideToVault', {
        'path': path,
        'mediaId': mediaId,
        'newPath': newPath,
        'isVideo': isVideo,
      });
      if (raw is! Map) {
        return const MediaRenameResult(ok: false, error: 'bad_response');
      }
      final map = Map<String, dynamic>.from(raw);
      final sizeVal = map['size'];
      return MediaRenameResult(
        ok: map['ok'] == true,
        newPath: map['newPath'] as String?,
        error: map['error'] as String?,
        needManageStorage: map['needManageStorage'] == true,
        size: sizeVal is int ? sizeVal : int.tryParse('$sizeVal'),
      );
    } catch (e) {
      debugPrint('hideToVault: $e');
      return MediaRenameResult(ok: false, error: '$e');
    }
  }

  /// Extract a JPEG still from a local video path into [destPath].
  /// Returns true when a non-empty file was written.
  Future<bool> videoThumbnail({
    required String path,
    required String destPath,
    int maxSize = 256,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('videoThumbnail', {
        'path': path,
        'destPath': destPath,
        'maxSize': maxSize,
      });
      return ok == true;
    } catch (e) {
      debugPrint('videoThumbnail: $e');
      return false;
    }
  }
}
