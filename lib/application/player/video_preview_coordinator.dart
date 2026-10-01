import 'dart:async';

import 'package:flutter/foundation.dart';

/// A decoded preview belongs to one playback session and one point in time.
class VideoPreview {
  const VideoPreview({required this.position, required this.bytes});

  final Duration position;
  final Uint8List bytes;
}

/// Shares preview work between the timeline and the horizontal seek gesture.
///
/// Only one decoder call is active. Queued requests replace older requests,
/// whose futures complete with null, so an old frame cannot acquire a new label.
/// The small memory cache is discarded with the media session.
class VideoPreviewCoordinator extends ValueNotifier<VideoPreview?> {
  VideoPreviewCoordinator({
    required Future<Uint8List?> Function(Duration) load,
    this.delay = const Duration(milliseconds: 110),
    this.cacheCapacity = 16,
    this.maxCacheBytes = 2 * 1024 * 1024,
    void Function(Object, StackTrace)? onError,
  })  : _load = load,
        _onError = onError,
        super(null);

  final Future<Uint8List?> Function(Duration) _load;
  final void Function(Object, StackTrace)? _onError;
  final Duration delay;
  final int cacheCapacity;
  final int maxCacheBytes;
  final _cache = <int, Uint8List>{};
  int _cacheBytes = 0;
  Timer? _timer;
  _PreviewRequest? _pending;
  _PreviewRequest? _active;
  int _generation = 0;
  bool _disposed = false;

  Future<Uint8List?> requestFrame(Duration position) {
    if (_disposed) return Future.value();
    final milliseconds = position.isNegative ? 0 : position.inMilliseconds;
    final key = (milliseconds ~/ 250) * 250;
    final target = Duration(milliseconds: key);
    final active = _active;
    if (active != null &&
        active.key == key &&
        active.generation == _generation &&
        _pending == null) {
      return active.result.future;
    }
    final pending = _pending;
    if (pending != null && pending.key == key) return pending.result.future;

    _generation++;
    _pending?.finish(null);
    _active?.finish(null);
    _pending = null;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      value = VideoPreview(position: target, bytes: cached);
      return Future.value(cached);
    }
    final request = _PreviewRequest(key, _generation);
    _pending = request;
    _schedule();
    return request.result.future;
  }

  void request(Duration position) => unawaited(requestFrame(position));

  void _schedule() {
    if (_disposed || _active != null || _pending == null || _timer != null) {
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_decode());
    });
  }

  Future<void> _decode() async {
    final request = _pending;
    if (_disposed || request == null || _active != null) return;
    _pending = null;
    _active = request;
    try {
      final position = Duration(milliseconds: request.key);
      final bytes = await _load(position);
      if (_disposed || request.generation != _generation) {
        request.finish(null);
        return;
      }
      if (bytes != null && bytes.isNotEmpty) {
        _remember(request.key, bytes);
        value = VideoPreview(position: position, bytes: bytes);
        request.finish(bytes);
      } else {
        value = null;
        request.finish(null);
      }
    } catch (error, stackTrace) {
      if (!_disposed && request.generation == _generation) {
        value = null;
        if (_onError != null) {
          _onError(error, stackTrace);
        } else {
          debugPrint('Video preview failed: $error\n$stackTrace');
        }
      }
      // A preview failure must not interrupt seeking or video playback.
      request.finish(null);
    } finally {
      request.finish(null);
      _active = null;
      _schedule();
    }
  }

  void _remember(int key, Uint8List bytes) {
    if (cacheCapacity <= 0 || bytes.lengthInBytes > maxCacheBytes) return;
    final previous = _cache.remove(key);
    if (previous != null) _cacheBytes -= previous.lengthInBytes;
    _cache[key] = bytes;
    _cacheBytes += bytes.lengthInBytes;
    while (_cache.length > cacheCapacity || _cacheBytes > maxCacheBytes) {
      _cacheBytes -= _cache.remove(_cache.keys.first)!.lengthInBytes;
    }
  }

  /// Cancels display of pending work, without starting a competing decoder.
  void clear() {
    if (_disposed) return;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending?.finish(null);
    _active?.finish(null);
    _pending = null;
    value = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    clear();
    _disposed = true;
    _cache.clear();
    _cacheBytes = 0;
    super.dispose();
  }
}

class _PreviewRequest {
  _PreviewRequest(this.key, this.generation);

  final int key;
  final int generation;
  final result = Completer<Uint8List?>();

  void finish(Uint8List? bytes) {
    if (!result.isCompleted) result.complete(bytes);
  }
}
