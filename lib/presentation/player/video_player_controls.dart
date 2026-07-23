import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../domain/models/video_playback_settings.dart';
import 'video_player_surface.dart';

String formatPlaybackSpeed(double speed) {
  final text = speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '${text}x';
}

class VideoBottomControls extends StatefulWidget {
  const VideoBottomControls({
    super.key,
    required this.value,
    required this.landscape,
    required this.fitMode,
    this.title,
    this.playlistPosition,
    this.playlistLength,
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
  });

  final VideoPlayerValue value;
  final bool landscape;
  final VideoFitMode fitMode;
  final String? title;
  final int? playlistPosition;
  final int? playlistLength;
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
  Timer? _previewTimer;
  Uint8List? _previewFrame;
  Duration? _previewPosition;
  Duration? _pendingPreviewPosition;
  bool _previewInFlight = false;
  int _previewGeneration = 0;

  @override
  void dispose() {
    _previewGeneration++;
    _previewTimer?.cancel();
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
    if (widget.onPreviewFrameRequested == null) return;
    _pendingPreviewPosition = Duration(milliseconds: positionMs.round());
    if (_previewInFlight || (_previewTimer?.isActive ?? false)) return;
    _previewTimer = Timer(const Duration(milliseconds: 110), _requestPreview);
  }

  void _requestPreview() {
    final request = widget.onPreviewFrameRequested;
    final position = _pendingPreviewPosition;
    if (request == null || position == null || !mounted) return;
    _pendingPreviewPosition = null;
    _previewInFlight = true;
    final generation = ++_previewGeneration;
    unawaited(() async {
      try {
        final frame = await request(position);
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewFrame = frame;
          _previewPosition = position;
        });
      } finally {
        _previewInFlight = false;
        if (_pendingPreviewPosition != null && mounted) {
          _previewTimer =
              Timer(const Duration(milliseconds: 40), _requestPreview);
        }
      }
    }());
  }

  void _clearPreview() {
    _previewGeneration++;
    _previewTimer?.cancel();
    _previewTimer = null;
    _pendingPreviewPosition = null;
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
                  if (widget.landscape &&
                      (widget.title != null ||
                          (widget.playlistPosition != null &&
                              widget.playlistLength != null)))
                    _landscapeHeader(),
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
                  if (!widget.landscape)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          _timeLabel(
                            formatVideoProgress(
                              _scrubbing
                                  ? Duration(milliseconds: positionMs.round())
                                  : value.position,
                              value.duration,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _iconButton(
                        context,
                        icon: Icons.skip_previous,
                        tooltip: context.l10n.previousMedia,
                        onPressed:
                            widget.hasPrevious ? widget.onPrevious : null,
                      ),
                      _iconButton(
                        context,
                        icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
                        tooltip: value.isPlaying
                            ? context.l10n.pause
                            : context.l10n.play,
                        onPressed: widget.onPlayPause,
                        size: 30,
                      ),
                      _iconButton(
                        context,
                        icon: Icons.skip_next,
                        tooltip: context.l10n.nextMedia,
                        onPressed: widget.hasNext ? widget.onNext : null,
                      ),
                      _iconButton(
                        context,
                        icon: widget.landscape
                            ? Icons.stay_current_portrait
                            : Icons.stay_current_landscape,
                        tooltip: widget.landscape
                            ? context.l10n.portrait
                            : context.l10n.landscape,
                        onPressed: widget.onToggleOrientation,
                      ),
                      _iconButton(
                        context,
                        icon: videoFitModeIcon(widget.fitMode),
                        tooltip: context.l10n.videoDisplayMode,
                        onPressed: widget.onChooseFit,
                      ),
                      _iconButton(
                        context,
                        icon: Icons.settings_outlined,
                        tooltip: context.l10n.playerSettings,
                        onPressed: widget.onOpenSettings,
                      ),
                    ],
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

  Widget _landscapeHeader() {
    final hasProgress =
        widget.playlistPosition != null && widget.playlistLength != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          if (widget.title != null)
            Expanded(
              child: Text(
                widget.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (hasProgress) ...[
            if (widget.title != null) const SizedBox(width: AppSpacing.sm),
            Text(
              '${widget.playlistPosition}/${widget.playlistLength}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
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
    return Expanded(
      child: SizedBox(
        height: 48,
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
          for (final option in VideoFitMode.values)
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

IconData videoFitModeIcon(VideoFitMode mode) {
  return switch (mode) {
    VideoFitMode.fit => Icons.fit_screen,
    VideoFitMode.fill => Icons.fullscreen,
    VideoFitMode.original => Icons.crop_free,
    VideoFitMode.ratio4x3 => Icons.crop_3_2,
    VideoFitMode.ratio16x9 => Icons.crop_16_9,
  };
}

IconData _fitIcon(VideoFitMode mode) => videoFitModeIcon(mode);

String _fitLabel(BuildContext context, VideoFitMode mode) {
  return switch (mode) {
    VideoFitMode.fit => context.l10n.videoFit,
    VideoFitMode.fill => context.l10n.videoFill,
    VideoFitMode.original => context.l10n.videoOriginal,
    VideoFitMode.ratio4x3 => context.l10n.videoRatioFourThree,
    VideoFitMode.ratio16x9 => context.l10n.videoRatioSixteenNine,
  };
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
  required double playbackSpeed,
  required ValueChanged<double> onPlaybackSpeedChanged,
  required bool muted,
  required ValueChanged<bool> onMutedChanged,
  bool? looping,
  ValueChanged<bool>? onLoopingChanged,
  bool? shuffle,
  ValueChanged<bool>? onShuffleChanged,
  VoidCallback? onOpenExternal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _VideoSettingsSheet(
      seekSeconds: seekSeconds,
      onSeekSecondsChanged: onSeekSecondsChanged,
      playbackSpeed: playbackSpeed,
      onPlaybackSpeedChanged: onPlaybackSpeedChanged,
      muted: muted,
      onMutedChanged: onMutedChanged,
      looping: looping,
      onLoopingChanged: onLoopingChanged,
      shuffle: shuffle,
      onShuffleChanged: onShuffleChanged,
      onOpenExternal: onOpenExternal,
    ),
  );
}

class _VideoSettingsSheet extends StatefulWidget {
  const _VideoSettingsSheet({
    required this.seekSeconds,
    required this.onSeekSecondsChanged,
    required this.playbackSpeed,
    required this.onPlaybackSpeedChanged,
    required this.muted,
    required this.onMutedChanged,
    this.looping,
    this.onLoopingChanged,
    this.shuffle,
    this.onShuffleChanged,
    this.onOpenExternal,
  });

  final int seekSeconds;
  final ValueChanged<int> onSeekSecondsChanged;
  final double playbackSpeed;
  final ValueChanged<double> onPlaybackSpeedChanged;
  final bool muted;
  final ValueChanged<bool> onMutedChanged;
  final bool? looping;
  final ValueChanged<bool>? onLoopingChanged;
  final bool? shuffle;
  final ValueChanged<bool>? onShuffleChanged;
  final VoidCallback? onOpenExternal;

  @override
  State<_VideoSettingsSheet> createState() => _VideoSettingsSheetState();
}

class _VideoSettingsSheetState extends State<_VideoSettingsSheet> {
  late int _seekSeconds = widget.seekSeconds;
  late double _playbackSpeed = widget.playbackSpeed;
  late bool _muted = widget.muted;
  late bool? _looping = widget.looping;
  late bool? _shuffle = widget.shuffle;

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
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(context.l10n.doubleTapSeek),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<int>(
                segments: [
                  for (final seconds in videoSeekSecondOptions)
                    ButtonSegment<int>(
                      value: seconds,
                      label: Text('${seconds}s'),
                    ),
                ],
                selected: {_seekSeconds},
                showSelectedIcon: false,
                onSelectionChanged: (selected) {
                  final value = selected.first;
                  setState(() => _seekSeconds = value);
                  widget.onSeekSecondsChanged(value);
                },
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
                onChanged: (value) {
                  setState(() => _playbackSpeed = value);
                  widget.onPlaybackSpeedChanged(value);
                },
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
