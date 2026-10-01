import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;

import '../../data/services/playback/media_kit_video_player_platform.dart';
import '../../domain/models/advanced_video_state.dart';

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

  void _onVideoChanged() {
    if (_disposed) return;
    if (_port == null) {
      final platform = VideoPlayerPlatform.instance;
      final port = _injectedPort ??
          (platform is MediaKitVideoPlayerPlatform
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

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed) throw StateError('Advanced video controller is disposed');
    try {
      await action();
      if (!_disposed && _port == null) {
        value = value.copyWith(
          error: controller.value.errorDescription,
          clearError: controller.value.errorDescription == null,
        );
      }
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

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onVideoChanged);
    _port?.removeListener(_onPortChanged);
    super.dispose();
  }
}
