import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/advanced_video_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../domain/models/video_playback_settings.dart';
import '../common/heart_rating_bar.dart';
import 'video_advanced_controls.dart';
import 'video_player_surface.dart';

String formatPlaybackSpeed(double speed) {
  final text = speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '${text}x';
}

const videoControlsAutoHideDelay = Duration(seconds: 3);

/// Keeps visible video controls on screen while a pointer is down, then hides
/// them after [delay] without interaction.
class AutoHideVideoControls extends StatefulWidget {
  const AutoHideVideoControls({
    super.key,
    required this.enabled,
    required this.visible,
    required this.onHide,
    required this.child,
    this.delay = videoControlsAutoHideDelay,
  });

  final bool enabled;
  final bool visible;
  final VoidCallback onHide;
  final Widget child;
  final Duration delay;

  @override
  State<AutoHideVideoControls> createState() => _AutoHideVideoControlsState();
}

class _AutoHideVideoControlsState extends State<AutoHideVideoControls> {
  final Set<int> _activePointers = <int>{};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant AutoHideVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || !widget.visible) {
      _activePointers.clear();
      _timer?.cancel();
      return;
    }
    if (!oldWidget.enabled ||
        !oldWidget.visible ||
        oldWidget.delay != widget.delay) {
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _timer?.cancel();
    if (!widget.enabled || !widget.visible || _activePointers.isNotEmpty) {
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted && widget.enabled && widget.visible) {
        widget.onHide();
      }
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || !widget.visible) return;
    _activePointers.add(event.pointer);
    _timer?.cancel();
  }

  void _onPointerReleased(PointerEvent event) {
    if (!_activePointers.remove(event.pointer)) return;
    if (_activePointers.isEmpty) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerReleased,
      onPointerCancel: _onPointerReleased,
      child: widget.child,
    );
  }
}

class VideoBottomControls extends StatefulWidget {
  const VideoBottomControls({
    super.key,
    required this.value,
    required this.landscape,
    required this.fitMode,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onPlayPause,
    required this.onNext,
    required this.onToggleOrientation,
    required this.onChooseFit,
    required this.onOpenSettings,
    this.onPreviewFrameRequested,
    this.showTransport = true,
    this.onOpenTracks,
    this.onPictureInPicture,
  });

  final bool showTransport;
  final VoidCallback? onOpenTracks;
  final VoidCallback? onPictureInPicture;
  final VideoPlayerValue value;
  final bool landscape;
  final VideoFitMode fitMode;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onToggleOrientation;
  final VoidCallback onChooseFit;
  final VoidCallback onOpenSettings;
  final Future<Uint8List?> Function(Duration position)? onPreviewFrameRequested;

  @override
  State<VideoBottomControls> createState() => _VideoBottomControlsState();
}

class _VideoBottomControlsState extends State<VideoBottomControls> {
  double? _scrubPositionMs;
  bool _scrubbing = false;
  Uint8List? _previewFrame;
  Duration? _previewPosition;
  int _previewGeneration = 0;

  @override
  void dispose() {
    _previewGeneration++;
    super.dispose();
  }

  Future<void> _finishScrub(double positionMs) async {
    await widget.onSeek(Duration(milliseconds: positionMs.round()));
    if (mounted) {
      setState(() {
        _scrubbing = false;
        _scrubPositionMs = null;
        _clearPreview();
      });
    }
  }

  void _schedulePreview(double positionMs) {
    final request = widget.onPreviewFrameRequested;
    if (request == null) return;
    final position = Duration(milliseconds: positionMs.round());
    final generation = ++_previewGeneration;
    unawaited(() async {
      try {
        final frame = await request(position);
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewFrame = frame;
          _previewPosition = frame == null ? null : position;
        });
      } catch (error, stackTrace) {
        // Preview failure must not interrupt seeking or the playing engine.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'Privi video preview',
          ),
        );
      }
    }());
  }

  void _clearPreview() {
    _previewGeneration++;
    _previewFrame = null;
    _previewPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final durationMs = value.duration.inMilliseconds.toDouble();
    final positionMs = durationMs <= 0
        ? 0.0
        : (_scrubPositionMs ?? value.position.inMilliseconds)
            .clamp(0, value.duration.inMilliseconds)
            .toDouble();
    return SafeArea(
      top: false,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.78),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: durationMs <= 0 ? 1 : durationMs,
                      value: durationMs <= 0 ? 0 : positionMs,
                      onChanged: durationMs <= 0
                          ? null
                          : (next) {
                              setState(() => _scrubPositionMs = next);
                              _schedulePreview(next);
                            },
                      onChangeStart: durationMs <= 0
                          ? null
                          : (next) => setState(() {
                                _scrubbing = true;
                                _scrubPositionMs = next;
                              }),
                      onChangeEnd: durationMs <= 0
                          ? null
                          : (next) => unawaited(_finishScrub(next)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _timeLabel(
                              formatVideoProgress(
                                _scrubbing
                                    ? Duration(
                                        milliseconds: positionMs.round(),
                                      )
                                    : value.position,
                                value.duration,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (widget.showTransport)
                    VideoTransportControls(
                      value: value,
                      hasPrevious: widget.hasPrevious,
                      hasNext: widget.hasNext,
                      onPrevious: widget.onPrevious,
                      onPlayPause: widget.onPlayPause,
                      onNext: widget.onNext,
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.onOpenTracks != null)
                          _iconButton(
                            context,
                            icon: Icons.subtitles_outlined,
                            tooltip: context.l10n.videoTracks,
                            onPressed: widget.onOpenTracks,
                          ),
                        _iconButton(
                          context,
                          icon: videoFitModeIcon(widget.fitMode),
                          tooltip: context.l10n.videoDisplayMode,
                          onPressed: widget.onChooseFit,
                        ),
                        _iconButton(
                          context,
                          icon: Icons.screen_rotation,
                          tooltip: context.l10n.videoOrientation,
                          onPressed: widget.onToggleOrientation,
                        ),
                        _iconButton(
                          context,
                          icon: Icons.settings_outlined,
                          tooltip: context.l10n.playerSettings,
                          onPressed: widget.onOpenSettings,
                        ),
                        if (widget.onPictureInPicture != null)
                          _iconButton(
                            context,
                            icon: Icons.picture_in_picture_alt,
                            tooltip: context.l10n.videoPictureInPicture,
                            onPressed: widget.onPictureInPicture,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_previewFrame != null && _previewPosition != null)
            Positioned(
              top: -132,
              child: _VideoFramePreview(
                frame: _previewFrame!,
                position: _previewPosition!,
                duration: value.duration,
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    double size = 26,
  }) {
    return SizedBox(
      width: 52,
      child: SizedBox(
        height: 44,
        child: IconButton(
          icon: Icon(icon, size: size),
          tooltip: tooltip,
          color: Colors.white,
          disabledColor: Colors.white24,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

Future<VideoFitMode?> showVideoFitModeSheet(
  BuildContext context, {
  required VideoFitMode current,
}) {
  return showModalBottomSheet<VideoFitMode>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(context.l10n.videoDisplayMode),
            leading: const Icon(Icons.aspect_ratio),
          ),
          for (final option in [
            ...videoFitQuickModes,
            ...VideoFitMode.values
                .where((mode) => !videoFitQuickModes.contains(mode)),
          ])
            ListTile(
              leading: Icon(_fitIcon(option)),
              title: Text(_fitLabel(context, option)),
              trailing: option == current
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

IconData videoFitModeIcon(VideoFitMode mode) => switch (mode) {
      VideoFitMode.bestFit => Icons.fit_screen,
      VideoFitMode.fitScreen => Icons.crop,
      VideoFitMode.fill => Icons.fullscreen,
      VideoFitMode.original => Icons.crop_free,
      _ => Icons.aspect_ratio,
    };

IconData _fitIcon(VideoFitMode mode) => videoFitModeIcon(mode);

String _fitLabel(BuildContext context, VideoFitMode mode) => switch (mode) {
      VideoFitMode.bestFit => context.l10n.videoFit,
      VideoFitMode.fitScreen => context.l10n.videoFitScreen,
      VideoFitMode.fill => context.l10n.videoFill,
      VideoFitMode.original => context.l10n.videoOriginal,
      VideoFitMode.ratio4x3 => '4:3',
      VideoFitMode.ratio16x9 => '16:9',
      VideoFitMode.ratio16x10 => '16:10',
      VideoFitMode.ratio2x1 => '2:1',
      VideoFitMode.ratio221x1 => '2.21:1',
      VideoFitMode.ratio235x1 => '2.35:1',
      VideoFitMode.ratio239x1 => '2.39:1',
      VideoFitMode.ratio5x4 => '5:4',
    };

/// Reserves top and bottom chrome before centering transport in the video.
class VideoTransportRegion extends StatelessWidget {
  const VideoTransportRegion({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned.fill(
        top: MediaQuery.paddingOf(context).top + kToolbarHeight,
        bottom: MediaQuery.paddingOf(context).bottom +
            106 +
            MediaQuery.textScalerOf(context).scale(16),
        child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: child)),
      );
}

class VideoTransportControls extends StatelessWidget {
  const VideoTransportControls({
    super.key,
    required this.value,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });
  final VideoPlayerValue value;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: context.l10n.previousMedia,
            icon: const Icon(Icons.skip_previous, size: 32),
            color: Colors.white,
            disabledColor: Colors.white24,
            onPressed: hasPrevious ? onPrevious : null,
          ),
          const SizedBox(width: 20),
          IconButton(
            tooltip: value.isPlaying ? context.l10n.pause : context.l10n.play,
            icon: Icon(
              value.isPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 48,
            ),
            color: Colors.white,
            onPressed: onPlayPause,
          ),
          const SizedBox(width: 20),
          IconButton(
            tooltip: context.l10n.nextMedia,
            icon: const Icon(Icons.skip_next, size: 32),
            color: Colors.white,
            disabledColor: Colors.white24,
            onPressed: hasNext ? onNext : null,
          ),
        ],
      );
}

class _VideoFramePreview extends StatelessWidget {
  const _VideoFramePreview({
    required this.frame,
    required this.position,
    required this.duration,
  });

  final Uint8List frame;
  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE61C1C1E),
        border: Border.all(color: Colors.white54),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(
              frame,
              key: const Key('video-frame-preview'),
              width: 180,
              height: 101,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                formatVideoProgress(position, duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showVideoSettingsSheet(
  BuildContext context, {
  required int seekSeconds,
  required ValueChanged<int> onSeekSecondsChanged,
  required int dragSeekSeconds,
  required ValueChanged<int> onDragSeekSecondsChanged,
  required double playbackSpeed,
  required Future<void> Function(double) onPlaybackSpeedChanged,
  required bool muted,
  required ValueChanged<bool> onMutedChanged,
  bool? looping,
  ValueChanged<bool>? onLoopingChanged,
  bool? shuffle,
  ValueChanged<bool>? onShuffleChanged,
  VoidCallback? onOpenExternal,
  int? rating,
  ValueChanged<int>? onRatingChanged,
  AdvancedVideoController? advanced,
  VideoPlayerController? controller,
  String defaultOrientation = 'auto',
  ValueChanged<String>? onDefaultOrientationChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _VideoSettingsSheet(
      seekSeconds: seekSeconds,
      onSeekSecondsChanged: onSeekSecondsChanged,
      dragSeekSeconds: dragSeekSeconds,
      onDragSeekSecondsChanged: onDragSeekSecondsChanged,
      playbackSpeed: playbackSpeed,
      onPlaybackSpeedChanged: onPlaybackSpeedChanged,
      muted: muted,
      onMutedChanged: onMutedChanged,
      looping: looping,
      onLoopingChanged: onLoopingChanged,
      shuffle: shuffle,
      onShuffleChanged: onShuffleChanged,
      onOpenExternal: onOpenExternal,
      rating: rating,
      onRatingChanged: onRatingChanged,
      advanced: advanced,
      controller: controller,
      defaultOrientation: defaultOrientation,
      onDefaultOrientationChanged: onDefaultOrientationChanged,
    ),
  );
}

class _VideoSettingsSheet extends StatefulWidget {
  const _VideoSettingsSheet({
    required this.seekSeconds,
    required this.onSeekSecondsChanged,
    required this.dragSeekSeconds,
    required this.onDragSeekSecondsChanged,
    required this.playbackSpeed,
    required this.onPlaybackSpeedChanged,
    required this.muted,
    required this.onMutedChanged,
    this.looping,
    this.onLoopingChanged,
    this.shuffle,
    this.onShuffleChanged,
    this.onOpenExternal,
    this.rating,
    this.onRatingChanged,
    this.advanced,
    this.controller,
    this.defaultOrientation = 'auto',
    this.onDefaultOrientationChanged,
  });

  final AdvancedVideoController? advanced;
  final VideoPlayerController? controller;
  final String defaultOrientation;
  final ValueChanged<String>? onDefaultOrientationChanged;
  final int seekSeconds;
  final ValueChanged<int> onSeekSecondsChanged;
  final int dragSeekSeconds;
  final ValueChanged<int> onDragSeekSecondsChanged;
  final double playbackSpeed;
  final Future<void> Function(double) onPlaybackSpeedChanged;
  final bool muted;
  final ValueChanged<bool> onMutedChanged;
  final bool? looping;
  final ValueChanged<bool>? onLoopingChanged;
  final bool? shuffle;
  final ValueChanged<bool>? onShuffleChanged;
  final VoidCallback? onOpenExternal;
  final int? rating;
  final ValueChanged<int>? onRatingChanged;

  @override
  State<_VideoSettingsSheet> createState() => _VideoSettingsSheetState();
}

class _VideoSettingsSheetState extends State<_VideoSettingsSheet> {
  late int _seekSeconds = widget.seekSeconds;
  late int _dragSeekSeconds = widget.dragSeekSeconds;
  late double _playbackSpeed = widget.playbackSpeed;
  bool _changingPlaybackSpeed = false;
  String? _playbackSpeedError;
  late bool _muted = widget.muted;
  late bool? _looping = widget.looping;
  late bool? _shuffle = widget.shuffle;
  late int? _rating = widget.rating;
  late String _defaultOrientation = widget.defaultOrientation;

  Future<void> _changePlaybackSpeed(double speed) async {
    if (_changingPlaybackSpeed || speed == _playbackSpeed) return;
    setState(() {
      _changingPlaybackSpeed = true;
      _playbackSpeedError = null;
    });
    try {
      await widget.onPlaybackSpeedChanged(speed);
      if (mounted) setState(() => _playbackSpeed = speed);
    } catch (error) {
      if (mounted) setState(() => _playbackSpeedError = error.toString());
    } finally {
      if (mounted) setState(() => _changingPlaybackSpeed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.playerSettings,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_rating != null && widget.onRatingChanged != null) ...[
                Text(context.l10n.rate),
                const SizedBox(height: AppSpacing.xs),
                HeartRatingBar(
                  rating: _rating!,
                  size: 28,
                  interactive: true,
                  scrim: false,
                  onRate: (value) {
                    setState(() => _rating = value);
                    widget.onRatingChanged!(value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(context.l10n.doubleTapSeek),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final seconds in videoSeekSecondOptions)
                    ChoiceChip(
                      label: Text('${seconds}s'),
                      selected: _seekSeconds == seconds,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _seekSeconds = seconds);
                        widget.onSeekSecondsChanged(seconds);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.dragSeek),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final seconds in videoDragSeekSecondOptions)
                    ChoiceChip(
                      label: Text(formatDragSeekOption(seconds)),
                      selected: _dragSeekSeconds == seconds,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _dragSeekSeconds = seconds);
                        widget.onDragSeekSecondsChanged(seconds);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: Text(context.l10n.playbackSpeed)),
                  Text(
                    formatPlaybackSpeed(_playbackSpeed),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Slider(
                min: videoPlaybackSpeedOptions.first,
                max: videoPlaybackSpeedOptions.last,
                divisions: videoPlaybackSpeedOptions.length - 1,
                value: _playbackSpeed,
                label: formatPlaybackSpeed(_playbackSpeed),
                onChanged: _changingPlaybackSpeed
                    ? null
                    : (value) => unawaited(_changePlaybackSpeed(value)),
              ),
              if (_playbackSpeedError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    context.l10n.errorWithDetails(_playbackSpeedError!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.mute),
                value: _muted,
                onChanged: (value) {
                  setState(() => _muted = value);
                  widget.onMutedChanged(value);
                },
              ),
              if (_looping != null && widget.onLoopingChanged != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.loopVideo),
                  value: _looping!,
                  onChanged: (value) {
                    setState(() => _looping = value);
                    widget.onLoopingChanged!(value);
                  },
                ),
              if (_shuffle != null && widget.onShuffleChanged != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.shuffle),
                  value: _shuffle!,
                  onChanged: (value) {
                    setState(() => _shuffle = value);
                    widget.onShuffleChanged!(value);
                  },
                ),
              if (widget.onDefaultOrientationChanged != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.screen_rotation),
                  title: Text(context.l10n.videoDefaultOrientation),
                  subtitle:
                      Text(videoOrientationLabel(context, _defaultOrientation)),
                  onTap: () async {
                    final mode = await showVideoOrientationSheet(
                      context,
                      current: _defaultOrientation,
                      defaults: true,
                    );
                    if (mode == null || !mounted) return;
                    setState(() => _defaultOrientation = mode);
                    widget.onDefaultOrientationChanged!(mode);
                  },
                ),
              if (widget.advanced != null && widget.controller != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune),
                  title: Text(context.l10n.videoAdvanced),
                  onTap: () => showVideoAdvancedSheet(
                    context,
                    advanced: widget.advanced!,
                    controller: widget.controller!,
                  ),
                ),
              if (widget.onOpenExternal != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.open_in_new),
                  title: Text(context.l10n.openExternal),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onOpenExternal!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
