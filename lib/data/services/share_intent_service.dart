import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'import_service.dart';

/// Listens for Android Share → app (share-to-hide entry).
class ShareIntentService {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  /// Call once after UI is ready. [onShared] receives importable sources.
  Future<void> start(void Function(List<ImportSource> sources) onShared) async {
    // Cold start
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        onShared(_map(initial));
        await ReceiveSharingIntent.instance.reset();
      }
    } catch (e) {
      debugPrint('share initial: $e');
    }

    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        if (files.isEmpty) return;
        onShared(_map(files));
        ReceiveSharingIntent.instance.reset();
      },
      onError: (Object e) => debugPrint('share stream: $e'),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  List<ImportSource> _map(List<SharedMediaFile> files) {
    final out = <ImportSource>[];
    for (final f in files) {
      final path = f.path;
      if (path.isEmpty) continue;
      // Content URIs may not be real files; file_picker path works when shared
      // as a file path. For content:// we still pass path for plugins that copy.
      out.add(
        ImportSource(
          path: path,
          name: p.basename(path),
          mimeType: f.mimeType,
          contentUri: path.startsWith('content:') ? path : null,
        ),
      );
    }
    return out;
  }

  /// True if path is a regular file we can openRead.
  static bool isReadableFile(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
