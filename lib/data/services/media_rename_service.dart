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
    this.clientId,
    this.method,
  });

  final bool ok;
  final String? newPath;
  final String? error;
  final bool needManageStorage;
  final int? size;

  /// Echo of the request [MediaHideRequest.clientId] (batch path).
  final String? clientId;

  /// Native transfer method (`Files.move`, `renameTo`, `uri-copy`, …).
  final String? method;
}

/// One item for [MediaRenameService.hideToVaultBatch].
class MediaHideRequest {
  const MediaHideRequest({
    required this.clientId,
    this.path,
    this.mediaId,
    required this.newPath,
    required this.isVideo,
  });

  /// Opaque id (usually vault media uuid) so Dart can match results.
  final String clientId;
  final String? path;
  final String? mediaId;
  final String newPath;
  final bool isVideo;
}

/// One item for [MediaRenameService.unhideFromVaultBatch].
class MediaUnhideRequest {
  const MediaUnhideRequest({
    required this.clientId,
    required this.path,
    required this.newPath,
    this.mimeType,
    this.dateTakenSec,
    this.dateAddedSec,
  });

  final String clientId;
  final String path;
  final String newPath;
  final String? mimeType;
  final int? dateTakenSec;
  final int? dateAddedSec;
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
      return _parseResult(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('hideToVault: $e');
      return MediaRenameResult(ok: false, error: '$e');
    }
  }

  /// One IPC for many hides. [clientId] on each request is echoed in the result.
  ///
  /// Keep chunk sizes modest (see [ImportService]) so Cancel can stop between
  /// chunks — a single giant native call cannot be interrupted mid-flight.
  Future<List<MediaRenameResult>> hideToVaultBatch(
    List<MediaHideRequest> items,
  ) async {
    if (items.isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<dynamic>('hideToVaultBatch', {
        'items': [
          for (final i in items)
            {
              'clientId': i.clientId,
              'path': i.path,
              'mediaId': i.mediaId,
              'newPath': i.newPath,
              'isVideo': i.isVideo,
            },
        ],
      });
      if (raw is! List) {
        return [
          for (final i in items)
            MediaRenameResult(
              ok: false,
              error: 'bad_response',
              clientId: i.clientId,
            ),
        ];
      }
      return [
        for (final entry in raw)
          if (entry is Map)
            _parseResult(Map<String, dynamic>.from(entry))
          else
            const MediaRenameResult(ok: false, error: 'bad_item'),
      ];
    } catch (e) {
      debugPrint('hideToVaultBatch: $e');
      return [
        for (final i in items)
          MediaRenameResult(ok: false, error: '$e', clientId: i.clientId),
      ];
    }
  }

  MediaRenameResult _parseResult(Map<String, dynamic> map) {
    final sizeVal = map['size'];
    return MediaRenameResult(
      ok: map['ok'] == true,
      newPath: map['newPath'] as String?,
      error: map['error'] as String?,
      needManageStorage: map['needManageStorage'] == true,
      size: sizeVal is int ? sizeVal : int.tryParse('$sizeVal'),
      clientId: map['clientId'] as String?,
      method: map['method'] as String?,
    );
  }

  /// One item for [unhideFromVaultBatch].
  ///
  /// [path] is the vault private path; [newPath] is the public restore target.
  Future<MediaRenameResult> unhideFromVault({
    required String path,
    required String newPath,
    String? mimeType,
    int? dateTakenSec,
    int? dateAddedSec,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('unhideFromVault', {
        'path': path,
        'newPath': newPath,
        'mimeType': mimeType,
        if (dateTakenSec != null) 'dateTakenSec': dateTakenSec,
        if (dateAddedSec != null) 'dateAddedSec': dateAddedSec,
      });
      if (raw is! Map) {
        return const MediaRenameResult(ok: false, error: 'bad_response');
      }
      return _parseResult(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('unhideFromVault: $e');
      return MediaRenameResult(ok: false, error: '$e');
    }
  }

  /// One IPC for many unhides. Keep chunks modest so Cancel can stop between.
  Future<List<MediaRenameResult>> unhideFromVaultBatch(
    List<MediaUnhideRequest> items,
  ) async {
    if (items.isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<dynamic>('unhideFromVaultBatch', {
        'items': [
          for (final i in items)
            {
              'clientId': i.clientId,
              'path': i.path,
              'newPath': i.newPath,
              'mimeType': i.mimeType,
              if (i.dateTakenSec != null) 'dateTakenSec': i.dateTakenSec,
              if (i.dateAddedSec != null) 'dateAddedSec': i.dateAddedSec,
            },
        ],
      });
      if (raw is! List) {
        return [
          for (final i in items)
            MediaRenameResult(
              ok: false,
              error: 'bad_response',
              clientId: i.clientId,
            ),
        ];
      }
      return [
        for (final entry in raw)
          if (entry is Map)
            _parseResult(Map<String, dynamic>.from(entry))
          else
            const MediaRenameResult(ok: false, error: 'bad_item'),
      ];
    } catch (e) {
      debugPrint('unhideFromVaultBatch: $e');
      return [
        for (final i in items)
          MediaRenameResult(ok: false, error: '$e', clientId: i.clientId),
      ];
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
