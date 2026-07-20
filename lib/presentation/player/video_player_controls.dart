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

class VideoBottomControls extends StatelessWidget {
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
  });

  final VideoPlayerValue value;
  final bool landscape;
  final VideoFitMode fitMode;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onToggleOrientation;
  final VoidCallback onChooseFit;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final durationMs = value.duration.inMilliseconds.toDouble();
    final positionMs = durationMs <= 0
        ? 0.0
        : value.position.inMilliseconds
            .clamp(0, value.duration.inMilliseconds)
            .toDouble();
    return SafeArea(
      top: false,
      child: Material(
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
                      : (next) => onSeek(
                            Duration(milliseconds: next.round()),
                          ),
                ),
              ),
              if (!landscape)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _timeLabel(formatVideoTime(value.position)),
                      _timeLabel(formatVideoTime(value.duration)),
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
                    onPressed: hasPrevious ? onPrevious : null,
                  ),
                  _iconButton(
                    context,
                    icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
                    tooltip: value.isPlaying
                        ? context.l10n.pause
                        : context.l10n.play,
                    onPressed: onPlayPause,
                    size: 30,
                  ),
                  _iconButton(
                    context,
                    icon: Icons.skip_next,
                    tooltip: context.l10n.nextMedia,
                    onPressed: hasNext ? onNext : null,
                  ),
                  _iconButton(
                    context,
                    icon: landscape
                        ? Icons.stay_current_portrait
                        : Icons.stay_current_landscape,
                    tooltip: landscape
                        ? context.l10n.portrait
                        : context.l10n.landscape,
                    onPressed: onToggleOrientation,
                  ),
                  _iconButton(
                    context,
                    icon: videoFitModeIcon(fitMode),
                    tooltip: context.l10n.videoDisplayMode,
                    onPressed: onChooseFit,
                  ),
                  _iconButton(
                    context,
                    icon: Icons.settings_outlined,
                    tooltip: context.l10n.playerSettings,
                    onPressed: onOpenSettings,
                  ),
                ],
              ),
            ],
          ),
        ),
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
                min: 0.5,
                max: 2,
                divisions: 6,
                value: _playbackSpeed,
                label: '${_playbackSpeed}x',
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
