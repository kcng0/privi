import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class AdvancedVideoTrack {
  const AdvancedVideoTrack({
    required this.id,
    this.title,
    this.language,
    this.isSelected = false,
  });

  final String id;
  final String? title;
  final String? language;
  final bool isSelected;
}

/// Per-player metadata and capabilities. Unknown dimensions remain zero.
@immutable
class AdvancedVideoState {
  const AdvancedVideoState({
    this.displaySize = Size.zero,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.supportsAudioTracks = false,
    this.supportsSubtitles = false,
    this.supportsExternalSubtitles = false,
    this.supportsAudioDelay = false,
    this.supportsSubtitleDelay = false,
    this.supportsAbLoop = false,
    this.audioDelay = Duration.zero,
    this.subtitleDelay = Duration.zero,
    this.abLoopStart,
    this.abLoopEnd,
    this.error,
  });

  final Size displaySize;
  final List<AdvancedVideoTrack> audioTracks;
  final List<AdvancedVideoTrack> subtitleTracks;
  final bool supportsAudioTracks;
  final bool supportsSubtitles;
  final bool supportsExternalSubtitles;
  final bool supportsAudioDelay;
  final bool supportsSubtitleDelay;
  final bool supportsAbLoop;
  final Duration audioDelay;
  final Duration subtitleDelay;
  final Duration? abLoopStart;
  final Duration? abLoopEnd;
  final String? error;

  AdvancedVideoState copyWith({
    Size? displaySize,
    List<AdvancedVideoTrack>? audioTracks,
    List<AdvancedVideoTrack>? subtitleTracks,
    bool? supportsAudioTracks,
    bool? supportsSubtitles,
    bool? supportsExternalSubtitles,
    bool? supportsAudioDelay,
    bool? supportsSubtitleDelay,
    bool? supportsAbLoop,
    Duration? audioDelay,
    Duration? subtitleDelay,
    Duration? abLoopStart,
    Duration? abLoopEnd,
    bool clearAbLoop = false,
    String? error,
    bool clearError = false,
  }) =>
      AdvancedVideoState(
        displaySize: displaySize ?? this.displaySize,
        audioTracks: audioTracks == null
            ? this.audioTracks
            : List.unmodifiable(audioTracks),
        subtitleTracks: subtitleTracks == null
            ? this.subtitleTracks
            : List.unmodifiable(subtitleTracks),
        supportsAudioTracks: supportsAudioTracks ?? this.supportsAudioTracks,
        supportsSubtitles: supportsSubtitles ?? this.supportsSubtitles,
        supportsExternalSubtitles:
            supportsExternalSubtitles ?? this.supportsExternalSubtitles,
        supportsAudioDelay: supportsAudioDelay ?? this.supportsAudioDelay,
        supportsSubtitleDelay:
            supportsSubtitleDelay ?? this.supportsSubtitleDelay,
        supportsAbLoop: supportsAbLoop ?? this.supportsAbLoop,
        audioDelay: audioDelay ?? this.audioDelay,
        subtitleDelay: subtitleDelay ?? this.subtitleDelay,
        abLoopStart:
            clearAbLoop ? abLoopStart : abLoopStart ?? this.abLoopStart,
        abLoopEnd: clearAbLoop ? abLoopEnd : abLoopEnd ?? this.abLoopEnd,
        error: clearError ? null : error ?? this.error,
      );
}

/// The platform owns this port and its resources; UI only owns subscriptions.
abstract interface class AdvancedVideoPort
    implements ValueListenable<AdvancedVideoState> {
  Future<void> refresh();
  Future<void> selectAudioTrack(String id);
  Future<void> selectSubtitleTrack(String id);
  Future<void> importSubtitle(String path);
  Future<void> setAudioDelay(Duration delay);
  Future<void> setSubtitleDelay(Duration delay);
  Future<void> setAbLoop(Duration? start, Duration? end);
}
