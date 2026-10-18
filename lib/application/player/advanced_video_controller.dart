import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;

import '../../domain/models/advanced_video_state.dart';
import '../../domain/models/video_player_capabilities.dart';

export '../../domain/models/advanced_video_state.dart';

/// Adds platform capabilities without taking ownership of the video controller.
class AdvancedVideoController extends ValueNotifier<AdvancedVideoState>
    implements AdvancedVideoPort {
  AdvancedVideoController(
    this.controller, {
    AdvancedVideoPort? port,
  })  : _injectedPort = port,
        super(const AdvancedVideoState()) {
    controller.addListener(_onVideoChanged);
    _onVideoChanged();
  }

  final VideoPlayerController controller;
  final AdvancedVideoPort? _injectedPort;
  AdvancedVideoPort? _port;
  bool _disposed = false;
  bool _loadingTracks = false;
  bool _loadedTracks = false;

  bool get supportsPlaybackDiagnostics =>
      !_disposed && _port is VideoPlaybackDiagnosticsPort;

  bool get supportsHardwareDecodingControl =>
      !_disposed && _port is VideoHardwareDecodingPort;

  void _onVideoChanged() {
    if (_disposed) return;
    if (_port == null) {
      final Object platform = VideoPlayerPlatform.instance;
      final port = _injectedPort ??
          (platform is AdvancedVideoPortProvider
              // video_player exposes no public controller-to-platform handle.
              // Its own Video widget uses this same stable facade identifier.
              // ignore: invalid_use_of_visible_for_testing_member
              ? platform.advancedPortFor(controller.playerId)
              : null);
      if (port != null) {
        _port = port;
        port.addListener(_onPortChanged);
        _onPortChanged();
        return;
      }
    }
    if (_port != null) return;
    final size = _displaySize;
    final audioSupported = controller.isAudioTrackSupportAvailable();
    final runtimeError = controller.value.errorDescription;
    if (size != value.displaySize ||
        audioSupported != value.supportsAudioTracks ||
        (runtimeError != null && runtimeError != value.error)) {
      value = value.copyWith(
        displaySize: size,
        supportsAudioTracks: audioSupported,
        error: runtimeError,
      );
    }
    if (controller.value.isInitialized && !_loadedTracks && !_loadingTracks) {
      // Errors are retained in state, including during automatic discovery.
      unawaited(refresh().catchError((Object _) {}));
    }
  }

  void _onPortChanged() {
    if (!_disposed) value = _port!.value;
  }

  Size get _displaySize {
    final video = controller.value;
    final rotation = video.rotationCorrection % 360;
    return rotation == 90 || rotation == 270
        ? Size(video.size.height, video.size.width)
        : video.size;
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_disposed) throw StateError('Advanced video controller is disposed');
    try {
      final result = await action();
      if (!_disposed && _port == null) {
        value = value.copyWith(
          error: controller.value.errorDescription,
          clearError: controller.value.errorDescription == null,
        );
      } else if (!_disposed) {
        // The port remains authoritative, including runtime failures. This also
        // replaces controller-only errors after a successful explicit Retry.
        _onPortChanged();
      }
      return result;
    } catch (error) {
      if (!_disposed) value = value.copyWith(error: error.toString());
      rethrow;
    }
  }

  @override
  Future<void> refresh() => _run(() async {
        final port = _port;
        if (port != null) return port.refresh();
        if (!controller.value.isInitialized || _loadingTracks) return;
        _loadingTracks = true;
        // Discovery runs once automatically; a failure stays visible until an
        // explicit refresh rather than retrying on every playback tick.
        _loadedTracks = true;
        try {
          final supported = controller.isAudioTrackSupportAvailable();
          final tracks = supported
              ? await controller.getAudioTracks()
              : const <VideoAudioTrack>[];
          if (_disposed) return;
          value = value.copyWith(
            displaySize: _displaySize,
            supportsAudioTracks: supported,
            audioTracks: [
              for (final track in tracks)
                AdvancedVideoTrack(
                  id: track.id,
                  title: track.label,
                  language: track.language,
                  isSelected: track.isSelected,
                ),
            ],
          );
        } finally {
          _loadingTracks = false;
        }
      });

  @override
  Future<void> selectAudioTrack(String id) => _run(() async {
        final port = _port;
        if (port != null) return port.selectAudioTrack(id);
        if (!value.supportsAudioTracks) {
          throw UnsupportedError('Audio track selection is unavailable');
        }
        await controller.selectAudioTrack(id);
        await refresh();
      });

  AdvancedVideoPort _requirePort(String feature) {
    final port = _port;
    if (port == null) throw UnsupportedError('$feature is unavailable');
    return port;
  }

  @override
  Future<void> selectSubtitleTrack(String id) =>
      _run(() => _requirePort('Subtitles').selectSubtitleTrack(id));

  @override
  Future<void> importSubtitle(String path) =>
      _run(() => _requirePort('External subtitles').importSubtitle(path));

  @override
  Future<void> setAudioDelay(Duration delay) =>
      _run(() => _requirePort('Audio delay').setAudioDelay(delay));

  @override
  Future<void> setSubtitleDelay(Duration delay) =>
      _run(() => _requirePort('Subtitle delay').setSubtitleDelay(delay));

  @override
  Future<void> setAbLoop(Duration? start, Duration? end) =>
      _run(() => _requirePort('A–B repeat').setAbLoop(start, end));

  Future<Map<String, String>> readPlaybackDiagnostics() => _run(() async {
        final Object? port = _port;
        if (port is! VideoPlaybackDiagnosticsPort) {
          throw UnsupportedError('Playback diagnostics are unavailable');
        }
        final diagnostics = await port.readPlaybackDiagnostics();
        if (_disposed || !identical(port, _port)) {
          throw StateError('Playback diagnostics belong to an inactive player');
        }
        return diagnostics;
      });

  Future<VideoHardwareDecodingInfo> readHardwareDecodingInfo() =>
      _run(() async {
        final Object? port = _port;
        if (port is! VideoHardwareDecodingPort) {
          throw UnsupportedError('Hardware decoding control is unavailable');
        }
        final info = await port.readHardwareDecodingInfo();
        if (_disposed || !identical(port, _port)) {
          throw StateError('Decoder information belongs to an inactive player');
        }
        return info;
      });

  Future<VideoHardwareDecodingInfo> setHardwareDecodingMode(
    VideoHardwareDecodingMode mode,
  ) =>
      _run(() async {
        final Object? port = _port;
        if (port is! VideoHardwareDecodingPort) {
          throw UnsupportedError('Hardware decoding control is unavailable');
        }
        // Pause through the facade so playlist/viewer state observes the change.
        // Resuming is always a later user action, including after panel dismissal
        // or a lifecycle/lock transition while this operation is pending.
        await controller.pause();
        if (_disposed || !identical(port, _port)) {
          throw StateError('Decoder selection belongs to an inactive player');
        }
        final info = await port.setHardwareDecodingMode(mode);
        if (_disposed || !identical(port, _port)) {
          throw StateError('Decoder selection belongs to an inactive player');
        }
        return info;
      });

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onVideoChanged);
    _port?.removeListener(_onPortChanged);
    super.dispose();
  }
}
