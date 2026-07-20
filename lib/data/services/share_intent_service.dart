import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../application/platform/share_source_stager.dart';
import 'import_service.dart';

/// Listens for platform shares and emits sources with a durable lifetime.
class ShareIntentService {
  ShareIntentService({required ShareSourceStager stager}) : _stager = stager;

  final ShareSourceStager _stager;
  StreamSubscription<List<SharedMediaFile>>? _sub;
  Future<void> _processing = Future.value();

  /// Call once after UI is ready. [onShared] receives importable sources.
  Future<void> start(
    FutureOr<void> Function(List<ImportSource> sources) onShared,
  ) async {
    if (_sub != null) {
      throw StateError('ShareIntentService.start may only be called once');
    }

    final recovered = await _stager.recoverPending();
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      final staged = await _stageIncoming(initial);
      final pending = _mergeByPath(recovered, staged);
      if (pending.isNotEmpty) await onShared(pending);
      await ReceiveSharingIntent.instance.reset();
    } else if (recovered.isNotEmpty) {
      await onShared(recovered);
    }

    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        if (files.isEmpty) return;
        _processing = _processing
            .then((_) => _handleIncoming(files, onShared))
            .catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'share intent',
              context: ErrorDescription('while staging a warm share'),
            ),
          );
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'share intent',
            context: ErrorDescription('while receiving a platform share'),
          ),
        );
      },
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _processing;
  }

  Future<void> _handleIncoming(
    List<SharedMediaFile> files,
    FutureOr<void> Function(List<ImportSource> sources) onShared,
  ) async {
    final staged = await _stageIncoming(files);
    if (staged.isNotEmpty) await onShared(staged);
    await ReceiveSharingIntent.instance.reset();
  }

  Future<List<ImportSource>> _stageIncoming(
    List<SharedMediaFile> files,
  ) {
    return _stager.stage(_map(files));
  }

  static List<ImportSource> _mergeByPath(
    List<ImportSource> recovered,
    List<ImportSource> staged,
  ) {
    final byPath = <String, ImportSource>{};
    for (final source in [...recovered, ...staged]) {
      byPath[source.path] = source;
    }
    return List.unmodifiable(byPath.values);
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
          temporaryThumbnailPath: f.thumbnail,
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
