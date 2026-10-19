import 'dart:io';

import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'libvlc_video_player_platform.dart';

/// Android renders through LibVLC's native surfaces; iOS keeps AVFoundation.
void installVaultVideoPlayer() {
  if (Platform.isAndroid) {
    VideoPlayerPlatform.instance = LibVlcVideoPlayerPlatform();
  }
}

/// Keeps asynchronous controller callbacks within their owner's lifetime.
///
/// video_player 2.13 cancels its position timer at disposal, but an already
/// pending query can still return and update the disposed ValueNotifier.
/// Position's existing null-on-disposal contract also applies after the await.
class VaultVideoPlayerController extends VideoPlayerController {
  VaultVideoPlayerController.file(
    super.file, {
    super.closedCaptionFile,
    super.videoPlayerOptions,
    super.httpHeaders,
    super.viewType,
  }) : super.file();

  bool _releasing = false;
  Future<void>? _releaseFuture;
  final Set<Future<void>> _pendingCommands = {};

  @override
  Future<Duration?> get position async {
    if (_releasing) return null;
    try {
      final current = await super.position;
      return _releasing ? null : current;
    } catch (_) {
      // A native query released with its owner is cancelled. Active playback
      // errors remain errors; they must not become an invented zero position.
      if (_releasing) return null;
      rethrow;
    }
  }

  Future<void> _command(Future<void> Function() operation) {
    if (_releasing) return Future<void>.value();
    late final Future<void> pending;
    pending = operation().whenComplete(() => _pendingCommands.remove(pending));
    _pendingCommands.add(pending);
    return pending;
  }

  // play creates the upstream timer after an await; seek updates position after
  // an await. Let already accepted commands finish before disposing that state.
  @override
  Future<void> play() => _command(super.play);

  @override
  Future<void> seekTo(Duration position) =>
      _command(() => super.seekTo(position));

  @override
  Future<void> dispose() {
    final existing = _releaseFuture;
    if (existing != null) return existing;
    _releasing = true;
    // Release native resources even when an accepted command failed. The
    // command error still propagates; disposal never reports fake success.
    return _releaseFuture = Future.wait(List.of(_pendingCommands)).whenComplete(
      () => super.dispose(),
    );
  }
}
