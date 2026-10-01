import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../domain/models/advanced_video_state.dart';

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
  final size = displaySizeFromPlayer(player);
  if (!_validDisplaySize(size)) {
    throw StateError('Video display dimensions are unavailable: $size');
  }
  return VideoEvent(
    eventType: VideoEventType.initialized,
    duration: player.state.duration,
    size: size,
    rotationCorrection: 0,
  );
}

/// These dimensions already include mpv's sample aspect ratio and rotation.
Size displaySizeFromPlayer(Player player) => Size(
      (player.state.width ?? 0).toDouble(),
      (player.state.height ?? 0).toDouble(),
    );

bool _validDisplaySize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

/// Replaces Android ExoPlayer/MediaCodec with libmpv so in-app playback can
/// software-decode formats the device hardware rejects.
void installVaultVideoPlayer() {
  if (!Platform.isAndroid) return;
  MediaKit.ensureInitialized();
  VideoPlayerPlatform.instance = MediaKitVideoPlayerPlatform();
}

class MediaKitVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, _PlayerSlot> _players = {};
  final Map<int, PlatformException> _initializationErrors = {};
  int _nextId = 1;

  @visibleForTesting
  int get activePlayerCount => _players.length;

  AdvancedVideoPort? advancedPortFor(int playerId) =>
      _players[playerId]?.advanced;

  @override
  Future<void> init() async {
    _initializationErrors.clear();
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
    final id = _nextId++;
    _PlayerSlot? slot;
    try {
      final uri = mediaUriForDataSource(options.dataSource);
      slot = await _openSlot(uri, hardware: true);
      if (slot.error != null) {
        final failedHardware = slot;
        slot = null;
        await failedHardware.dispose();
        slot = await _openSlot(uri, hardware: false);
      }
      if (slot.error != null) {
        throw PlatformException(code: 'video_player', message: slot.error);
      }
      _players[id] = slot;
    } catch (error) {
      var message = error is PlatformException
          ? error.message ?? error.toString()
          : error.toString();
      if (slot != null) {
        try {
          await slot.dispose();
        } catch (cleanupError) {
          message = '$message; releasing failed player: $cleanupError';
        }
      }
      // video_player completes its creation barrier only after receiving an id.
      // Throwing here would leave its dispose() waiting forever. Failed players
      // own no live slot: report the failure through the event stream instead.
      _initializationErrors[id] = PlatformException(
        code: 'video_player',
        message: message,
      );
    }
    return id;
  }

  Future<_PlayerSlot> _openSlot(String uri, {required bool hardware}) async {
    final watch = Stopwatch()..start();
    var phase = 'constructing';
    void trace(String message) {
      assert(() {
        debugPrint(
            'Video initialization (${hardware ? 'hardware' : 'software'}, '
            '${watch.elapsedMilliseconds}ms): $message');
        return true;
      }());
    }

    trace(phase);
    final player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
        libassAndroidFont: 'assets/fonts/NotoSansCJKsc-Regular.ttf',
        libassAndroidFontName: 'Noto Sans CJK SC',
      ),
    );
    final VideoController controller;
    try {
      controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: hardware,
          hwdec: hardware ? 'auto-safe' : 'no',
        ),
      );
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    Timer? watchdog;
    assert(() {
      var playerReady = false;
      var outputReady = false;
      unawaited(
        player.platform!.waitForPlayerInitialization.then<void>(
          (_) {
            playerReady = true;
            trace('native player ready');
          },
          onError: (Object error) => trace('native player failed: $error'),
        ),
      );
      unawaited(
        controller.platform.future.then<void>(
          (_) {
            outputReady = true;
            trace('video output ready');
          },
          onError: (Object error) => trace('video output failed: $error'),
        ),
      );
      watchdog = Timer(const Duration(seconds: 5), () {
        trace('waiting at $phase; player=$playerReady, output=$outputReady');
      });
      return true;
    }());
    // Closed in [_PlayerSlot.dispose] when the player id is released.
    // ignore: close_sinks
    final events = StreamController<VideoEvent>.broadcast();
    final advanced = MediaKitAdvancedVideoPort(player);
    String? runtimeError;
    final subscriptions = <StreamSubscription<dynamic>>[
      player.stream.error.listen((message) {
        runtimeError = message;
        if (!events.isClosed) {
          events.addError(
            PlatformException(code: 'video_player', message: message),
          );
        }
      }),
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
      phase = 'configure';
      trace(phase);
      final native = player.platform;
      if (native is NativePlayer) {
        await native.setProperty('vd-lavc-software-fallback', 'yes');
      }
      phase = 'open';
      trace(phase);
      await player.open(Media(uri), play: false);
      if (runtimeError != null) {
        throw PlatformException(code: 'video_player', message: runtimeError);
      }
      phase = 'metadata';
      trace(phase);
      ready = await waitUntilPlaybackReady(player);
      phase = 'advanced controls';
      trace(phase);
      await advanced.refresh();
      trace('ready');
    } catch (e) {
      error = e is PlatformException ? (e.message ?? '$e') : '$e';
      trace('failed at $phase: $error');
    } finally {
      watchdog?.cancel();
      watch.stop();
    }
    return _PlayerSlot(
      player: player,
      controller: controller,
      events: events,
      subscriptions: subscriptions,
      advanced: advanced,
      runtimeError: () => runtimeError,
      ready: ready,
      error: error ?? runtimeError,
    );
  }

  @override
  Future<void> dispose(int playerId) async {
    _initializationErrors.remove(playerId);
    final slot = _players.remove(playerId);
    if (slot != null) await slot.dispose();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    final initializationError = _initializationErrors[playerId];
    if (initializationError != null) throw initializationError;
    final slot = _players[playerId];
    if (slot == null) return;
    final ready = slot.ready;
    if (ready != null) yield ready;
    final error = slot.runtimeError();
    if (error != null) {
      throw PlatformException(code: 'video_player', message: error);
    }
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
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async {
    final slot = _players[playerId];
    if (slot == null) throw StateError('Unknown video player $playerId');
    await slot.advanced.refresh();
    final selectedIds = {
      for (final track in slot.advanced.value.audioTracks)
        if (track.isSelected) track.id,
    };
    return [
      for (final track in _player(playerId).state.tracks.audio)
        if (track.id != 'auto' && track.id != 'no')
          VideoAudioTrack(
            id: track.id,
            label: track.title,
            language: track.language,
            isSelected: selectedIds.contains(track.id),
            bitrate: track.bitrate,
            sampleRate: track.samplerate,
            channelCount: track.channelscount,
            codec: track.codec,
          ),
    ];
  }

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) {
    final slot = _players[playerId];
    if (slot == null) throw StateError('Unknown video player $playerId');
    return slot.advanced.selectAudioTrack(trackId);
  }

  @override
  bool isAudioTrackSupportAvailable() => true;

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
    required this.advanced,
    required this.runtimeError,
    required this.ready,
    required this.error,
  });

  final Player player;
  final VideoController controller;
  final StreamController<VideoEvent> events;
  final List<StreamSubscription<dynamic>> subscriptions;
  final MediaKitAdvancedVideoPort advanced;
  final String? Function() runtimeError;
  final VideoEvent? ready;
  final String? error;

  Future<void> dispose() async {
    try {
      await advanced.close();
    } finally {
      try {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      } finally {
        try {
          await events.close();
        } finally {
          try {
            await player.dispose();
          } finally {
            await advanced.deleteTemporarySubtitles();
          }
        }
      }
    }
  }
}

@visibleForTesting
Future<VideoEvent> waitUntilPlaybackReady(
  Player player, {
  Duration timeout = const Duration(seconds: 20),
}) =>
    waitForPlaybackMetadata(
      duration: () => player.state.duration,
      displaySize: () => displaySizeFromPlayer(player),
      metadataChanges: [
        player.stream.duration,
        player.stream.width,
        player.stream.height,
        player.stream.videoParams,
      ],
      errors: player.stream.error,
      timeout: timeout,
    );

/// Injectable metadata streams let tests reproduce delayed video discovery.
@visibleForTesting
Future<VideoEvent> waitForPlaybackMetadata({
  required Duration Function() duration,
  required Size Function() displaySize,
  required List<Stream<dynamic>> metadataChanges,
  required Stream<String> errors,
  Duration timeout = const Duration(seconds: 20),
}) {
  final completer = Completer<VideoEvent>();
  final subscriptions = <StreamSubscription<dynamic>>[];

  void tryComplete() {
    if (completer.isCompleted) return;
    final size = displaySize();
    final mediaDuration = duration();
    // Privi plays finite media files. video_player caches duration from this
    // one-shot initialized event, so width arriving first must not freeze the
    // timeline at zero for the rest of the controller's lifetime.
    if (!_validDisplaySize(size) || mediaDuration <= Duration.zero) return;
    completer.complete(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: mediaDuration,
        size: size,
        rotationCorrection: 0,
      ),
    );
  }

  subscriptions.add(
    errors.listen((message) {
      if (!completer.isCompleted) {
        completer.completeError(
          PlatformException(code: 'video_player', message: message),
        );
      }
    }),
  );
  for (final stream in metadataChanges) {
    subscriptions.add(stream.listen((_) => tryComplete()));
  }
  tryComplete();

  return completer.future
      .timeout(
    timeout,
    onTimeout: () => throw PlatformException(
      code: 'video_player',
      message: 'Timed out opening media after ${timeout.inMilliseconds}ms: '
          'duration=${duration().inMilliseconds}ms, '
          'display=${displaySize().width}×${displaySize().height}',
    ),
  )
      .whenComplete(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });
}

/// A player-owned port. Mutations are serialized so disposal never races a
/// property write or the creation of a private subtitle copy.
class MediaKitAdvancedVideoPort extends ValueNotifier<AdvancedVideoState>
    implements AdvancedVideoPort {
  MediaKitAdvancedVideoPort(
    this.player, {
    Future<void> Function(String, String)? writeProperty,
    Future<String> Function(String)? readProperty,
    Future<Directory> Function()? createSubtitleDirectory,
  })  : _writeProperty = writeProperty ??
            (player.platform is NativePlayer
                ? (player.platform! as NativePlayer).setProperty
                : null),
        _readProperty = readProperty ??
            (player.platform is NativePlayer
                ? (player.platform! as NativePlayer).getProperty
                : null),
        _createSubtitleDirectory =
            createSubtitleDirectory ?? _createPrivateSubtitleDirectory,
        super(const AdvancedVideoState()) {
    _subscriptions.addAll([
      player.stream.width.listen((_) => _updateMetadata()),
      player.stream.height.listen((_) => _updateMetadata()),
      player.stream.tracks.listen((_) => _onTracksChanged()),
      player.stream.track.listen((_) => _onTracksChanged()),
      player.stream.error.listen((message) {
        _runtimeError = message;
        reportError(message);
      }),
    ]);
    _updateMetadata();
  }

  final Player player;
  final Future<void> Function(String, String)? _writeProperty;
  final Future<String> Function(String)? _readProperty;
  final Future<Directory> Function() _createSubtitleDirectory;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _pending = Future<void>.value();
  Directory? _subtitleDirectory;
  int _subtitleSequence = 0;
  bool _closing = false;
  bool _closed = false;
  bool _trackRefreshQueued = false;
  String? _selectedAudioId;
  String? _selectedSubtitleId;
  String? _runtimeError;

  static Future<Directory> _createPrivateSubtitleDirectory() async {
    final cache = await getTemporaryDirectory();
    return cache.createTemp('privi-subtitles-');
  }

  void reportError(String message) {
    if (!_closed) value = value.copyWith(error: message);
  }

  void _onTracksChanged() {
    _updateMetadata();
    if (_closing || _trackRefreshQueued || _readProperty == null) return;
    _trackRefreshQueued = true;
    unawaited(
      _enqueue(
        () async {
          try {
            await _refreshSelectedTracks();
          } finally {
            _trackRefreshQueued = false;
          }
        },
        clearError: false,
      ).catchError((Object _) {}),
    );
  }

  Future<void> _refreshSelectedTracks() async {
    final read = _readProperty;
    if (read == null) return;
    final audioId = await read('aid');
    final subtitleId = await read('sid');
    _selectedAudioId = audioId.isEmpty ? null : audioId;
    _selectedSubtitleId = subtitleId.isEmpty ? null : subtitleId;
    _updateMetadata();
  }

  void _updateMetadata() {
    if (_closing) return;
    final state = player.state;
    final native = _readProperty != null && _writeProperty != null;
    value = value.copyWith(
      displaySize: displaySizeFromPlayer(player),
      supportsAudioTracks: true,
      supportsSubtitles: native,
      supportsExternalSubtitles: native,
      audioTracks: [
        for (final track in state.tracks.audio)
          if (track.id != 'auto' && track.id != 'no')
            AdvancedVideoTrack(
              id: track.id,
              title: track.title,
              language: track.language,
              isSelected:
                  track.id == (_selectedAudioId ?? state.track.audio.id),
            ),
      ],
      subtitleTracks: [
        AdvancedVideoTrack(
          id: 'no',
          isSelected: (_selectedSubtitleId ?? state.track.subtitle.id) == 'no',
        ),
        for (final track in state.tracks.subtitle)
          if (track.id != 'auto' && track.id != 'no')
            AdvancedVideoTrack(
              id: track.id,
              title: track.title,
              language: track.language,
              isSelected:
                  track.id == (_selectedSubtitleId ?? state.track.subtitle.id),
            ),
      ],
    );
  }

  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool clearError = true,
  }) {
    if (_closing) {
      return Future<void>.error(StateError('Video player is disposed'));
    }
    final result = _pending.then((_) async {
      try {
        await operation();
        if (!_closed && clearError) {
          value = value.copyWith(
            error: _runtimeError,
            clearError: _runtimeError == null,
          );
        }
      } catch (error) {
        reportError(error.toString());
        rethrow;
      }
    });
    // The caller receives the failure; the queue stays usable for Retry.
    _pending = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> refresh() => _enqueue(() async {
        _updateMetadata();
        await _refreshSelectedTracks();
        await _refreshProperties();
      });

  Future<void> _refreshProperties() async {
    final read = _readProperty;
    if (read == null) return;
    final audio = _durationFromSeconds(await read('audio-delay'));
    final subtitle = _durationFromSeconds(await read('sub-delay'));
    final start = await read('ab-loop-a');
    final end = await read('ab-loop-b');
    final hasAbLoop = _validLoopProperty(start) && _validLoopProperty(end);
    value = value.copyWith(
      supportsAudioDelay: audio != null,
      supportsSubtitleDelay: subtitle != null,
      supportsAbLoop: hasAbLoop,
      audioDelay: audio,
      subtitleDelay: subtitle,
      abLoopStart: _durationFromSeconds(start),
      abLoopEnd: _durationFromSeconds(end),
      clearAbLoop: true,
    );
  }

  @override
  Future<void> selectAudioTrack(String id) => _enqueue(() async {
        final matches = player.state.tracks.audio.where((t) => t.id == id);
        if (matches.isEmpty || id == 'auto' || id == 'no') {
          throw ArgumentError.value(id, 'id', 'Unknown audio track');
        }
        await player.setAudioTrack(matches.first);
        await _refreshSelectedTracks();
        _updateMetadata();
      });

  @override
  Future<void> selectSubtitleTrack(String id) => _enqueue(() async {
        _require(value.supportsSubtitles, 'Subtitles');
        final matches = player.state.tracks.subtitle.where((t) => t.id == id);
        if (id != 'no' && (matches.isEmpty || id == 'auto')) {
          throw ArgumentError.value(id, 'id', 'Unknown subtitle track');
        }
        await player.setSubtitleTrack(
          id == 'no' ? SubtitleTrack.no() : matches.first,
        );
        await _refreshSelectedTracks();
        _updateMetadata();
      });

  @override
  Future<void> importSubtitle(String path) => _enqueue(() async {
        _require(value.supportsExternalSubtitles, 'External subtitles');
        final source = File(path);
        if (!await source.exists()) {
          throw FileSystemException('Subtitle file does not exist', path);
        }
        _subtitleDirectory ??= await _createSubtitleDirectory();
        final destination = p.join(
          _subtitleDirectory!.path,
          'subtitle-${_subtitleSequence++}${p.extension(path)}',
        );
        final copy = await source.copy(destination);
        // Retain the directory until disposal even on failure: libmpv may have
        // started reading the file before reporting an error.
        await player.setSubtitleTrack(
          SubtitleTrack.uri(copy.uri.toString(), title: p.basename(path)),
        );
        await _refreshSelectedTracks();
        _updateMetadata();
      });

  @override
  Future<void> setAudioDelay(Duration delay) => _enqueue(() async {
        _require(value.supportsAudioDelay, 'Audio delay');
        try {
          await _writeVerified('audio-delay', _seconds(delay));
        } finally {
          await _refreshProperties();
        }
      });

  @override
  Future<void> setSubtitleDelay(Duration delay) => _enqueue(() async {
        _require(value.supportsSubtitleDelay, 'Subtitle delay');
        try {
          await _writeVerified('sub-delay', _seconds(delay));
        } finally {
          await _refreshProperties();
        }
      });

  @override
  Future<void> setAbLoop(Duration? start, Duration? end) => _enqueue(() async {
        _require(value.supportsAbLoop, 'A–B repeat');
        if ((start != null && start < Duration.zero) ||
            (end != null && (start == null || end <= start))) {
          throw ArgumentError('A–B repeat requires 0 ≤ A < B');
        }
        try {
          // Disable the old end first, preventing an intermediate A > B loop.
          await _writeVerified('ab-loop-b', 'no');
          await _writeVerified(
            'ab-loop-a',
            start == null ? 'no' : _seconds(start),
          );
          if (end != null) await _writeVerified('ab-loop-b', _seconds(end));
        } finally {
          // A partial native failure must publish the actual remaining loop.
          await _refreshProperties();
        }
      });

  void _require(bool supported, String feature) {
    if (!supported) throw UnsupportedError('$feature is unavailable');
  }

  Future<void> _writeVerified(String name, String expected) async {
    final write = _writeProperty;
    final read = _readProperty;
    if (write == null || read == null) {
      throw UnsupportedError('Native property $name is unavailable');
    }
    await write(name, expected);
    final actual = await read(name);
    final expectedNumber = double.tryParse(expected);
    final actualNumber = double.tryParse(actual);
    final matches = expectedNumber != null && actualNumber != null
        ? actualNumber.isFinite &&
            (actualNumber - expectedNumber).abs() <= 0.000001
        : actual == expected;
    if (!matches) {
      throw StateError(
        'mpv rejected $name=$expected (read back ${actual.isEmpty ? 'unavailable' : actual})',
      );
    }
  }

  static String _seconds(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerSecond).toString();

  static Duration? _durationFromSeconds(String value) {
    final seconds = double.tryParse(value);
    if (seconds == null || !seconds.isFinite) return null;
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  static bool _validLoopProperty(String value) =>
      value == 'no' || _durationFromSeconds(value) != null;

  /// Called by the slot before releasing libmpv.
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _pending;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _closed = true;
    super.dispose();
  }

  /// Called only after libmpv has stopped using the imported subtitle files.
  Future<void> deleteTemporarySubtitles() async {
    final directory = _subtitleDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _subtitleDirectory = null;
  }
}
