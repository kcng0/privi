import 'dart:io';

import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

/// One outbound share item. Android uses [mediaId] or [path] directly in a
/// system chooser; iOS falls back to [path] or a photo_manager file URL.
class OutboundShareFile {
  const OutboundShareFile({
    this.path,
    this.mediaId,
    required this.mimeType,
    this.name,
    this.isVideo = false,
  });

  final String? path;
  final String? mediaId;
  final String mimeType;
  final String? name;
  final bool isVideo;

  Map<String, Object?> toChannelArguments() {
    return {
      if (path != null) 'path': path,
      if (mediaId != null) 'mediaId': mediaId,
      'mimeType': mimeType,
      if (name != null) 'name': name,
      'isVideo': isVideo,
    };
  }
}

/// System share-sheet sender. Android opens `ACTION_SEND` via
/// `Intent.createChooser` without copying files or remembering the last
/// destination. Other platforms keep `share_plus`.
class OutboundShareService {
  OutboundShareService({
    MethodChannel? channel,
    bool? useSystemChooser,
    Future<void> Function(List<XFile> files)? shareXFiles,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _useSystemChooser = useSystemChooser ?? Platform.isAndroid,
        _shareXFiles = shareXFiles ??
            ((files) async {
              await Share.shareXFiles(files);
            });

  static const channelName = 'com.privi.app/share';

  final MethodChannel _channel;
  final bool _useSystemChooser;
  final Future<void> Function(List<XFile> files) _shareXFiles;

  Future<void> share(List<OutboundShareFile> files) async {
    if (files.isEmpty) return;
    if (_useSystemChooser) {
      await _channel.invokeMethod<void>('share', {
        'items': [
          for (final file in files) file.toChannelArguments(),
        ],
      });
      return;
    }
    final xFiles = <XFile>[];
    for (final file in files) {
      final resolved = await _resolveXFile(file);
      if (resolved != null) xFiles.add(resolved);
    }
    if (xFiles.isEmpty) return;
    await _shareXFiles(xFiles);
  }

  Future<XFile?> _resolveXFile(OutboundShareFile file) async {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return XFile(path, mimeType: file.mimeType, name: file.name);
    }
    final mediaId = file.mediaId;
    if (mediaId == null) return null;
    final entity = await AssetEntity.fromId(mediaId);
    if (entity == null) return null;
    final url = await entity.getMediaUrl();
    if (url != null) {
      final uri = Uri.parse(url);
      if (uri.isScheme('file')) {
        return XFile(
          uri.toFilePath(),
          mimeType: file.mimeType,
          name: file.name ?? entity.title,
        );
      }
    }
    final exported = await entity.file;
    if (exported == null) return null;
    return XFile(
      exported.path,
      mimeType: file.mimeType,
      name: file.name ?? entity.title,
    );
  }
}
