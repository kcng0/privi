import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// ExoPlayer/MediaCodec refused the stream because the device decoder cannot
/// handle that profile, size, or frame rate (e.g. 2560x1440 @ 120fps H.264
/// High@L5.2 / `avc1.640034`).
bool isDecoderCapabilityError(String message) {
  final text = message.toLowerCase();
  return text.contains('no_exceeds_capabilities') ||
      text.contains('exceeds_capabilities') ||
      text.contains('exceeds capabilities') ||
      text.contains('format_supported=no') ||
      text.contains('mediacodecvideorenderer') ||
      text.contains('avc1.640034') ||
      (text.contains('mediacodec') && text.contains('exceed')) ||
      (text.contains('decoder') && text.contains('exceed'));
}

/// Maps a [video_player] data source onto an mpv/FFmpeg URI.
String mediaUriForDataSource(DataSource source) {
  switch (source.sourceType) {
    case DataSourceType.asset:
      final asset = source.asset;
      if (asset == null || asset.isEmpty) {
        throw ArgumentError('Missing asset path');
      }
      if (source.package == null || source.package!.isEmpty) {
        return 'asset:///$asset';
      }
      return 'asset:///${source.package}/$asset';
    case DataSourceType.file:
    case DataSourceType.network:
    case DataSourceType.contentUri:
      final uri = source.uri;
      if (uri == null || uri.isEmpty) {
        throw ArgumentError('Missing media URI');
      }
      if (source.sourceType == DataSourceType.file && !uri.contains('://')) {
        return Uri.file(uri).toString();
      }
      return uri;
  }
}

/// mpv already swaps width/height for 90/270, so Flutter must not rotate again.
VideoEvent initializedEventFromPlayer(Player player) {
  final width = player.state.width ?? player.state.videoParams.dw ?? 0;
  final height = player.state.height ?? player.state.videoParams.dh ?? 0;
  return VideoEvent(
    eventType: VideoEventType.initialized,
    duration: player.state.duration,
    size: Size(
      width > 0 ? width.toDouble() : 16,
      height > 0 ? height.toDouble() : 9,
    ),
    rotationCorrection: 0,
  );
}

/// Replaces Android ExoPlayer/MediaCodec with libmpv so in-app playback can
/// software-decode formats the device hardware rejects.
void installVaultVideoPlayer() {
  if (!Platform.isAndroid) return;
  MediaKit.ensureInitialized();
  VideoPlayerPlatform.instance = MediaKitVideoPlayerPlatform();
}

class MediaKitVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, _PlayerSlot> _players = {};
  int _nextId = 1;

  @override
  Future<void> init() async {
    for (final id in _players.keys.toList()) {
      await dispose(id);
    }
  }

  @override
  Future<int?> create(DataSource dataSource) {
    return createWithOptions(
      VideoCreationOptions(
        dataSource: dataSource,
        viewType: VideoViewType.textureView,
      ),
    );
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final uri = mediaUriForDataSource(options.dataSource);
    var slot = await _openSlot(uri, hardware: true);
    if (slot.error != null) {
      await slot.dispose();
      slot = await _openSlot(uri, hardware: false);
    }
    if (slot.error != null) {
      final message = slot.error!;
      await slot.dispose();
      throw PlatformException(code: 'video_player', message: message);
    }
    final id = _nextId++;
    _players[id] = slot;
    return id;
  }

  Future<_PlayerSlot> _openSlot(String uri, {required bool hardware}) async {
    final player = Player();
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: hardware,
        hwdec: hardware ? 'auto-safe' : 'no',
      ),
    );
    // Closed in [_PlayerSlot.dispose] when the player id is released.
    // ignore: close_sinks
    final events = StreamController<VideoEvent>.broadcast();
    final subscriptions = <StreamSubscription<dynamic>>[
      player.stream.completed.listen((completed) {
        if (completed) {
          events.add(VideoEvent(eventType: VideoEventType.completed));
        }
      }),
      player.stream.playing.listen((playing) {
        events.add(
          VideoEvent(
            eventType: VideoEventType.isPlayingStateUpdate,
            isPlaying: playing,
          ),
        );
      }),
      player.stream.buffering.listen((buffering) {
        events.add(
          VideoEvent(
            eventType: buffering
                ? VideoEventType.bufferingStart
                : VideoEventType.bufferingEnd,
          ),
        );
      }),
    ];
    String? error;
    VideoEvent? ready;
    try {
      final native = player.platform;
      if (native is NativePlayer) {
        await native.setProperty('vd-lavc-software-fallback', 'yes');
      }
      await player.open(Media(uri), play: false);
      ready = await waitUntilPlaybackReady(player);
    } catch (e) {
      error = e is PlatformException ? (e.message ?? '$e') : '$e';
    }
    return _PlayerSlot(
      player: player,
      controller: controller,
      events: events,
      subscriptions: subscriptions,
      ready: ready,
      error: error,
    );
  }

  @override
  Future<void> dispose(int playerId) async {
    final slot = _players.remove(playerId);
    if (slot != null) await slot.dispose();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    final slot = _players[playerId];
    if (slot == null) return;
    final ready = slot.ready;
    if (ready != null) yield ready;
    yield* slot.events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) {
    return _player(playerId).setPlaylistMode(
      looping ? PlaylistMode.loop : PlaylistMode.none,
    );
  }

  @override
  Future<void> play(int playerId) => _player(playerId).play();

  @override
  Future<void> pause(int playerId) => _player(playerId).pause();

  @override
  Future<void> setVolume(int playerId, double volume) {
    return _player(playerId).setVolume((volume.clamp(0.0, 1.0)) * 100);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) {
    return _player(playerId).seek(position);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    return _player(playerId).setRate(speed);
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return _player(playerId).state.position;
  }

  @override
  Widget buildView(int playerId) {
    final slot = _players[playerId];
    if (slot == null) return const SizedBox.shrink();
    return Video(
      controller: slot.controller,
      fit: BoxFit.fill,
      fill: const Color(0xFF000000),
      controls: null,
      wakelock: true,
      pauseUponEnteringBackgroundMode: false,
    );
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  Player _player(int playerId) {
    final slot = _players[playerId];
    if (slot == null) {
      throw StateError('Unknown video player $playerId');
    }
    return slot.player;
  }
}

class _PlayerSlot {
  _PlayerSlot({
    required this.player,
    required this.controller,
    required this.events,
    required this.subscriptions,
    required this.ready,
    required this.error,
  });

  final Player player;
  final VideoController controller;
  final StreamController<VideoEvent> events;
  final List<StreamSubscription<dynamic>> subscriptions;
  final VideoEvent? ready;
  final String? error;

  Future<void> dispose() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await events.close();
    await player.dispose();
  }
}

@visibleForTesting
Future<VideoEvent> waitUntilPlaybackReady(
  Player player, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final completer = Completer<VideoEvent>();
  final subscriptions = <StreamSubscription<dynamic>>[];

  void tryComplete() {
    if (completer.isCompleted) return;
    final duration = player.state.duration;
    final width = player.state.width ?? player.state.videoParams.dw ?? 0;
    final height = player.state.height ?? player.state.videoParams.dh ?? 0;
    if (duration <= Duration.zero && width <= 0 && height <= 0) return;
    completer.complete(initializedEventFromPlayer(player));
  }

  subscriptions.add(
    player.stream.error.listen((message) {
      if (!completer.isCompleted) {
        completer.completeError(
          PlatformException(code: 'video_player', message: message),
        );
      }
    }),
  );
  subscriptions.add(player.stream.duration.listen((_) => tryComplete()));
  subscriptions.add(player.stream.width.listen((_) => tryComplete()));
  subscriptions.add(player.stream.height.listen((_) => tryComplete()));
  subscriptions.add(player.stream.videoParams.listen((_) => tryComplete()));
  tryComplete();

  return completer.future
      .timeout(
    timeout,
    onTimeout: () => throw PlatformException(
      code: 'video_player',
      message: 'Timed out opening media',
    ),
  )
      .whenComplete(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });
}
