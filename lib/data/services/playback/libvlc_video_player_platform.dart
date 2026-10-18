import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../domain/models/advanced_video_state.dart';
import '../../../domain/models/video_playback_settings.dart';
import '../../../domain/models/video_player_capabilities.dart';

/// The video_player facade backed by Android LibVLC and a native SurfaceView.
class LibVlcVideoPlayerPlatform extends VideoPlayerPlatform
    implements AdvancedVideoPortProvider, NativeVideoPresentationPlatform {
  LibVlcVideoPlayerPlatform({
    MethodChannel channel = const MethodChannel('com.privi.app/libvlc'),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Map<int, _LibVlcPlayer> _players = {};
  // -1 belongs to video_player's uninitialized sentinel. Local failures must
  // still return a disposable id without colliding with a native player.
  int _nextFailedId = -2;
  bool _mixWithOthers = false;
  Future<void>? _initialization;

  @override
  AdvancedVideoPort? advancedPortFor(int playerId) =>
      _players[playerId]?.advanced;

  @override
  Future<void> init() => _initialization = _reset();

  Future<void> _reset() async {
    try {
      await Future.wait(_players.keys.toList().map(dispose));
    } finally {
      await _channel.invokeMethod<void>('init');
    }
  }

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
        VideoCreationOptions(
          dataSource: dataSource,
          viewType: VideoViewType.platformView,
        ),
      );

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    _LibVlcPlayer? player;
    try {
      // video_player calls platform.init() without awaiting it. In particular,
      // the reset must finish before a new native id can be allocated.
      if (_initialization case final initialization?) await initialization;
      final source = options.dataSource;
      final arguments = <String, Object?>{
        'uri': _uriForDataSource(source),
        if (source.sourceType == DataSourceType.asset &&
            source.package != null &&
            source.package!.isNotEmpty)
          'package': source.package,
        if (source.httpHeaders.isNotEmpty)
          'httpHeaders': Map<String, String>.of(source.httpHeaders),
      };
      final id = await _channel.invokeMethod<int>('create', arguments);
      if (id == null || id < 0 || _players.containsKey(id)) {
        throw const FormatException('LibVLC returned an invalid player id');
      }
      player = _LibVlcPlayer(id: id, channel: _channel, isNative: true);
      _players[id] = player;
      // Listen before awaiting any setup call. Native metadata/errors can be
      // emitted while those calls are in flight and belong to this player.
      player.listen();
      await player.invoke<void>('setMixWithOthers', {
        'mixWithOthers':
            options.videoPlayerOptions?.mixWithOthers ?? _mixWithOthers,
      });
      await player.invoke<void>('setPreventsDisplaySleepDuringVideoPlayback', {
        'preventsDisplaySleepDuringVideoPlayback': options
                .videoPlayerOptions?.preventsDisplaySleepDuringVideoPlayback ??
            true,
      });
      return id;
    } catch (error, stackTrace) {
      // Throwing from create leaves video_player's creation barrier unresolved
      // and can hang dispose. Initialization failures belong on its event stream.
      player ??= _LibVlcPlayer(
        id: _nextFailedId--,
        channel: _channel,
        isNative: false,
      );
      _players[player.id] = player;
      player.fail(error, stackTrace);
      return player.id;
    }
  }

  @override
  Future<void> dispose(int playerId) async {
    final player = _players.remove(playerId);
    if (player != null) await player.dispose();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _player(playerId).events;

  @override
  Future<void> setLooping(int playerId, bool looping) =>
      _player(playerId).invoke<void>('setLooping', {'looping': looping});

  @override
  Future<void> play(int playerId) => _player(playerId).invoke<void>('play');

  @override
  Future<void> pause(int playerId) => _player(playerId).invoke<void>('pause');

  @override
  Future<void> setVolume(int playerId, double volume) =>
      _player(playerId).invoke<void>('setVolume', {'volume': volume});

  @override
  Future<void> seekTo(int playerId, Duration position) =>
      _player(playerId).invoke<void>(
        'seekTo',
        {'position': position.inMilliseconds},
      );

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _player(playerId).invoke<void>('setPlaybackSpeed', {'speed': speed});

  @override
  Future<Duration> getPosition(int playerId) async {
    final position = await _player(playerId).invoke<int>('getPosition');
    return Duration(milliseconds: _number(position, 'position').toInt());
  }

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async {
    final advanced = _player(playerId).advanced;
    await advanced.refresh();
    return List.unmodifiable([
      for (final track in advanced.value.audioTracks)
        VideoAudioTrack(
          id: track.id,
          label: track.title,
          language: track.language,
          isSelected: track.isSelected,
        ),
    ]);
  }

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) =>
      _player(playerId).advanced.selectAudioTrack(trackId);

  @override
  bool isAudioTrackSupportAvailable() => true;

  @override
  Widget buildView(int playerId) =>
      buildNativeViewport(playerId, VideoFitMode.bestFit);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      buildView(options.playerId);

  @override
  Widget buildNativeViewport(int playerId, VideoFitMode fitMode) {
    final player = _players[playerId];
    if (player == null || !player.isNative) return const SizedBox.shrink();
    return _LibVlcViewport(
      key: ObjectKey(player),
      player: player,
      fitMode: fitMode,
    );
  }

  @override
  Future<void> setPresentationAllowed(int playerId, bool allowed) =>
      _player(playerId).invoke<void>(
        'setPresentationAllowed',
        {'allowed': allowed},
      );

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {
    final player = _player(playerId);
    // The facade applies this option before subscribing to initialization
    // events. A local failed id has no native screen to configure; retain its
    // original error for that subscription instead of throwing prematurely.
    if (!player.isNative) return;
    await player.invoke<void>('setPreventsDisplaySleepDuringVideoPlayback', {
      'preventsDisplaySleepDuringVideoPlayback':
          preventsDisplaySleepDuringVideoPlayback,
    });
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    _mixWithOthers = mixWithOthers;
    await Future.wait([
      for (final player in _players.values.toList())
        if (player.isNative)
          player.invoke<void>('setMixWithOthers', {
            'mixWithOthers': mixWithOthers,
          }),
    ]);
  }

  // Root authentication/PiP and video_player's lifecycle observer own pausing;
  // the native SurfaceView must not independently resume in the background.
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  _LibVlcPlayer _player(int id) {
    final player = _players[id];
    if (player == null) throw StateError('Unknown LibVLC video player $id');
    return player;
  }
}

String _uriForDataSource(DataSource source) {
  switch (source.sourceType) {
    case DataSourceType.asset:
      final asset = source.asset;
      if (asset == null || asset.isEmpty) {
        throw ArgumentError('Missing video asset path');
      }
      // FlutterAssets resolves the separately supplied package namespace.
      return Uri(scheme: 'asset', host: '', path: '/$asset').toString();
    case DataSourceType.file:
      final uri = source.uri;
      if (uri == null || uri.isEmpty) {
        throw ArgumentError('Missing video file URI');
      }
      return Uri.tryParse(uri)?.scheme.isNotEmpty == true
          ? uri
          : Uri.file(uri).toString();
    case DataSourceType.network:
    case DataSourceType.contentUri:
      final uri = source.uri;
      if (uri == null || uri.isEmpty) {
        throw ArgumentError('Missing video URI');
      }
      return uri;
  }
}

class _LibVlcPlayer {
  _LibVlcPlayer({
    required this.id,
    required this.channel,
    required this.isNative,
  }) {
    advanced = _LibVlcAdvancedVideoPort(this);
  }

  final int id;
  final MethodChannel channel;
  final bool isNative;
  final _events = StreamController<VideoEvent>.broadcast();
  late final _LibVlcAdvancedVideoPort advanced;
  StreamSubscription<Object?>? _subscription;
  VideoEvent? _initialized;
  PlatformException? _error;
  StackTrace? _errorStack;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Subscribe to live events and replay metadata/errors already received while
  /// video_player was completing creation, without reopening the native stream.
  Stream<VideoEvent> get events => Stream<VideoEvent>.multi(
        (listener) {
          final subscription = _events.stream.listen(
            listener.addSync,
            onError: listener.addErrorSync,
            onDone: listener.closeSync,
          );
          listener.onCancel = subscription.cancel;
          listener.onPause = subscription.pause;
          listener.onResume = subscription.resume;
          if (_error case final error?) {
            listener.addErrorSync(error, _errorStack);
          } else if (_initialized case final initialized?) {
            listener.addSync(initialized);
          }
        },
        isBroadcast: true,
      );

  void listen() {
    _subscription = EventChannel(
      'com.privi.app/libvlc/events/$id',
      const StandardMethodCodec(),
      channel.binaryMessenger,
    ).receiveBroadcastStream().listen(
      (Object? event) {
        if (_disposed) return;
        try {
          _handleEvent(_map(event, 'event'));
        } catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed) fail(error, stackTrace);
      },
      onDone: () {
        if (!_disposed) {
          fail(
            PlatformException(
              code: 'libvlc_event_stream_closed',
              message: 'LibVLC playback events closed unexpectedly',
            ),
            StackTrace.current,
          );
        }
      },
    );
  }

  void _handleEvent(Map<Object?, Object?> event) {
    if (_error != null) return;
    final VideoEvent videoEvent;
    switch (event['event']) {
      case 'advanced':
        try {
          advanced.update(_map(event['state'], 'advanced state'));
        } catch (error, stackTrace) {
          reportControlError(error, stackTrace, 'Reading advanced video state');
        }
        return;
      case 'initialized':
        if (_initialized != null) return;
        final width = _number(event['width'], 'width').toDouble();
        final height = _number(event['height'], 'height').toDouble();
        if (width <= 0 || height <= 0) {
          throw const FormatException(
            'LibVLC video dimensions are unavailable',
          );
        }
        videoEvent = VideoEvent(
          eventType: VideoEventType.initialized,
          duration: Duration(
            milliseconds: _number(event['duration'], 'duration').toInt(),
          ),
          // LibVLC supplies final display dimensions, including SAR/rotation.
          size: Size(width, height),
          rotationCorrection: 0,
        );
        _initialized = videoEvent;
      case 'completed':
        videoEvent = VideoEvent(eventType: VideoEventType.completed);
      case 'isPlayingStateUpdate':
        final isPlaying = event['isPlaying'];
        if (isPlaying is! bool) {
          throw const FormatException('Invalid LibVLC playing state');
        }
        videoEvent = VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: isPlaying,
        );
      case 'bufferingStart':
        videoEvent = VideoEvent(eventType: VideoEventType.bufferingStart);
      case 'bufferingEnd':
        videoEvent = VideoEvent(eventType: VideoEventType.bufferingEnd);
      case 'bufferingUpdate':
        final ranges = event['values'];
        if (ranges is! List<Object?>) {
          throw const FormatException('Invalid LibVLC buffered ranges');
        }
        videoEvent = VideoEvent(
          eventType: VideoEventType.bufferingUpdate,
          buffered: [
            for (final range in ranges) _bufferedRange(range),
          ],
        );
      default:
        videoEvent = VideoEvent(eventType: VideoEventType.unknown);
    }
    _events.add(videoEvent);
  }

  Future<T?> invoke<T>(
    String method, [
    Map<String, Object?> values = const {},
  ]) {
    if (_disposed) throw StateError('LibVLC video player $id was disposed');
    if (!isNative) throw _error!;
    return channel.invokeMethod<T>(method, {'id': id, ...values});
  }

  void reportControlError(
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    if (_disposed) return;
    advanced.reportError('$operation: $error');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Privi LibVLC',
        context: ErrorDescription('$operation for video player $id'),
      ),
    );
  }

  void fail(Object error, StackTrace stackTrace) {
    // The first fatal native/protocol error remains authoritative. A later
    // setup failure or stream closure must not hide the original cause.
    if (_disposed || _error != null) return;
    final exception = error is PlatformException
        ? PlatformException(
            code: error.code,
            message: error.message ?? 'LibVLC playback failed (${error.code})',
            details: error.details,
            stacktrace: error.stacktrace,
          )
        : PlatformException(code: 'libvlc_video_player', message: '$error');
    _error = exception;
    _errorStack = stackTrace;
    advanced.reportError(exception.message!);
    _events.addError(exception, stackTrace);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _subscription?.cancel();
    } finally {
      advanced.dispose();
      // A paused facade subscription must not hold native decoder cleanup open.
      unawaited(_events.close());
      if (isNative) await channel.invokeMethod<void>('dispose', {'id': id});
    }
  }
}

class _LibVlcAdvancedVideoPort extends ValueNotifier<AdvancedVideoState>
    implements AdvancedVideoPort, VideoPlaybackDiagnosticsPort {
  _LibVlcAdvancedVideoPort(this._player) : super(const AdvancedVideoState());

  final _LibVlcPlayer _player;
  bool _disposed = false;
  int _revision = 0;
  int _refreshSequence = 0;

  void update(Map<Object?, Object?> state) {
    if (_disposed) return;
    final displaySize = Size(
      _number(state['displayWidth'] ?? 0, 'display width').toDouble(),
      _number(state['displayHeight'] ?? 0, 'display height').toDouble(),
    );
    final next = AdvancedVideoState(
      displaySize: displaySize,
      audioTracks: _tracks(state['audioTracks']),
      subtitleTracks: _tracks(state['subtitleTracks']),
      supportsAudioTracks: state['supportsAudioTracks'] == true,
      supportsSubtitles: state['supportsSubtitles'] == true,
      supportsExternalSubtitles: state['supportsExternalSubtitles'] == true,
      supportsAudioDelay: state['supportsAudioDelay'] == true,
      supportsSubtitleDelay: state['supportsSubtitleDelay'] == true,
      supportsAbLoop: state['supportsAbLoop'] == true,
      audioDelay: Duration(
        microseconds: _number(state['audioDelay'] ?? 0, 'audio delay').toInt(),
      ),
      subtitleDelay: Duration(
        microseconds:
            _number(state['subtitleDelay'] ?? 0, 'subtitle delay').toInt(),
      ),
      abLoopStart: _optionalMilliseconds(state['abLoopStart']),
      abLoopEnd: _optionalMilliseconds(state['abLoopEnd']),
      error: state['error'] as String?,
    );
    _revision++;
    value = next;
  }

  void reportError(String error) {
    if (_disposed) return;
    _revision++;
    value = value.copyWith(error: error);
  }

  @override
  Future<void> refresh() async {
    final sequence = ++_refreshSequence;
    final revision = _revision;
    final state = await _player.invoke<Object?>('getAdvancedState');
    if (!_disposed && sequence == _refreshSequence && revision == _revision) {
      update(_map(state, 'advanced state'));
    }
  }

  Future<void> _change(String method, Map<String, Object?> arguments) async {
    await _player.invoke<void>(method, arguments);
    if (!_disposed) await refresh();
  }

  @override
  Future<void> selectAudioTrack(String id) =>
      _change('selectAudioTrack', {'trackId': id});

  @override
  Future<void> selectSubtitleTrack(String id) =>
      _change('selectSubtitleTrack', {'trackId': id});

  @override
  Future<void> importSubtitle(String path) =>
      _change('importSubtitle', {'path': path});

  @override
  Future<void> setAudioDelay(Duration delay) =>
      _change('setAudioDelay', {'delay': delay.inMicroseconds});

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _change('setSubtitleDelay', {'delay': delay.inMicroseconds});

  @override
  Future<void> setAbLoop(Duration? start, Duration? end) =>
      _change('setAbLoop', {
        'start': start?.inMilliseconds,
        'end': end?.inMilliseconds,
      });

  @override
  Future<Map<String, String>> readPlaybackDiagnostics() async {
    final result = await _player.invoke<Object?>('readPlaybackDiagnostics');
    final diagnostics = _map(result, 'playback diagnostics');
    return Map.unmodifiable(
      diagnostics.map((key, value) {
        if (key is! String || value is! String) {
          throw const FormatException('Invalid LibVLC playback diagnostics');
        }
        return MapEntry(key, value);
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _LibVlcViewport extends StatefulWidget {
  const _LibVlcViewport({
    super.key,
    required this.player,
    required this.fitMode,
  });

  final _LibVlcPlayer player;
  final VideoFitMode fitMode;

  @override
  State<_LibVlcViewport> createState() => _LibVlcViewportState();
}

class _LibVlcViewportState extends State<_LibVlcViewport> {
  Widget? _platformView;
  int? _viewId;
  bool _created = false;
  VideoFitMode? _requestedFitMode;

  @override
  void didUpdateWidget(_LibVlcViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitMode != oldWidget.fitMode) _updateFitMode();
  }

  void _updateFitMode() {
    final viewId = _viewId;
    if (!_created ||
        viewId == null ||
        widget.player.isDisposed ||
        _requestedFitMode == widget.fitMode) {
      return;
    }
    _requestedFitMode = widget.fitMode;
    unawaited(_setFitMode(viewId, widget.fitMode));
  }

  Future<void> _setFitMode(int viewId, VideoFitMode mode) async {
    try {
      await widget.player.invoke<void>('setFitMode', {
        'viewId': viewId,
        'fitMode': mode.name,
      });
    } catch (error, stackTrace) {
      // An update for a removed host has no active presentation to affect.
      if (!mounted || widget.player.isDisposed) return;
      widget.player.reportControlError(
        error,
        stackTrace,
        'Setting video fit mode ${mode.name} for viewport $viewId',
      );
    }
  }

  @override
  Widget build(BuildContext context) => _platformView ??= PlatformViewLink(
        viewType: 'com.privi.app/libvlc/view',
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        ),
        onCreatePlatformView: (params) {
          _viewId = params.id;
          _requestedFitMode = widget.fitMode;
          // Force real hybrid composition: neither Flutter textures nor virtual
          // displays can preserve the SurfaceView's native presentation path.
          return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: params.viewType,
            layoutDirection: Directionality.of(context),
            creationParams: {
              'id': widget.player.id,
              'fitMode': widget.fitMode.name,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )..addOnPlatformViewCreatedListener((viewId) {
              params.onPlatformViewCreated(viewId);
              if (!mounted) return;
              _created = true;
              // A setting may change while native creation is still awaiting
              // layout/channel completion. Apply only this mount's latest mode.
              _updateFitMode();
            });
          // PlatformViewLink creates on its first nonempty layout and owns
          // disposal. A new mount may replace a PiP host for the same player;
          // the native host is responsible for detaching its previous surface.
        },
      );
}

Map<Object?, Object?> _map(Object? value, String field) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Invalid LibVLC $field');
  }
  return value;
}

num _number(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid LibVLC $field');
  }
  return value;
}

Duration? _optionalMilliseconds(Object? value) => value == null
    ? null
    : Duration(milliseconds: _number(value, 'AB loop position').toInt());

DurationRange _bufferedRange(Object? value) {
  if (value is! List<Object?> || value.length != 2) {
    throw const FormatException('Invalid LibVLC buffered range');
  }
  return DurationRange(
    Duration(milliseconds: _number(value[0], 'buffered start').toInt()),
    Duration(milliseconds: _number(value[1], 'buffered end').toInt()),
  );
}

List<AdvancedVideoTrack> _tracks(Object? value) {
  if (value == null) return const [];
  if (value is! List<Object?>) {
    throw const FormatException('Invalid LibVLC tracks');
  }
  return List.unmodifiable(
    value.map((entry) {
      final track = _map(entry, 'track');
      final id = track['id'];
      if (id is! String) throw const FormatException('Invalid LibVLC track id');
      return AdvancedVideoTrack(
        id: id,
        title: track['title'] as String?,
        language: track['language'] as String?,
        isSelected: track['isSelected'] == true,
      );
    }),
  );
}
