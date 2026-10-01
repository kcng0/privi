import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/advanced_video_controller.dart';
import '../../core/l10n.dart';
import '../../domain/models/video_playback_settings.dart';
import 'video_player_surface.dart';

String videoOrientationLabel(BuildContext context, String mode) =>
    switch (mode) {
      'portrait' => context.l10n.portrait,
      'reversePortrait' => context.l10n.videoReversePortrait,
      'landscape' => context.l10n.landscape,
      'reverseLandscape' => context.l10n.videoReverseLandscape,
      'sensorLandscape' => context.l10n.videoSensorLandscape,
      'sensorPortrait' => context.l10n.videoSensorPortrait,
      'lastLocked' => context.l10n.videoLastLocked,
      _ => context.l10n.videoAutoOrientation,
    };

Future<String?> showVideoOrientationSheet(
  BuildContext context, {
  required String current,
  bool defaults = false,
}) =>
    showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                defaults
                    ? context.l10n.videoDefaultOrientation
                    : context.l10n.videoOrientation,
              ),
            ),
            for (final mode in defaults
                ? videoDefaultOrientationOptions
                : videoSessionOrientationOptions)
              ListTile(
                title: Text(videoOrientationLabel(context, mode)),
                trailing: current == mode ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );

Future<void> showVideoAdvancedSheet(
  BuildContext context, {
  required AdvancedVideoController advanced,
  required VideoPlayerController controller,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) =>
          _AdvancedSheet(advanced: advanced, controller: controller),
    );

class _AdvancedSheet extends StatefulWidget {
  const _AdvancedSheet({required this.advanced, required this.controller});
  final AdvancedVideoController advanced;
  final VideoPlayerController controller;
  @override
  State<_AdvancedSheet> createState() => _AdvancedSheetState();
}

class _AdvancedSheetState extends State<_AdvancedSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delay(bool audio) async {
    final state = widget.advanced.value;
    var input = (audio ? state.audioDelay : state.subtitleDelay)
        .inMilliseconds
        .toString();
    final form = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          audio
              ? context.l10n.videoAudioDelay
              : context.l10n.videoSubtitleDelay,
        ),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: input,
            onChanged: (value) => input = value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(
              suffixText: 'ms',
              helperText: context.l10n.videoDelayHelp,
            ),
            validator: (value) => int.tryParse(value ?? '') == null
                ? context.l10n.videoInvalidDelay
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(input));
              }
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await _run(
      () => audio
          ? widget.advanced.setAudioDelay(Duration(milliseconds: value))
          : widget.advanced.setSubtitleDelay(Duration(milliseconds: value)),
    );
  }

  Future<void> _importSubtitle() => _run(() async {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
        );
        if (picked == null) return;
        final path = picked.files.single.path;
        if (path == null) {
          throw StateError('The selected subtitle has no readable path.');
        }
        await widget.advanced.importSubtitle(path);
      });

  Widget _tracks(
    String title,
    List<AdvancedVideoTrack> tracks,
    Future<void> Function(String) select, {
    bool subtitles = false,
  }) {
    return ExpansionTile(
      title: Text(title),
      children: [
        if (subtitles)
          ListTile(
            title: Text(context.l10n.videoSubtitleOff),
            trailing:
                tracks.any((track) => track.id != 'no' && track.isSelected)
                    ? null
                    : const Icon(Icons.check),
            onTap: _busy ? null : () => _run(() => select('no')),
          ),
        for (final track in tracks.where((track) => track.id != 'no'))
          ListTile(
            title: Text(
              track.title == null || track.title!.isEmpty
                  ? track.id
                  : track.title!,
            ),
            subtitle: track.language == null || track.language!.isEmpty
                ? null
                : Text(track.language!),
            trailing: track.isSelected ? const Icon(Icons.check) : null,
            onTap: _busy ? null : () => _run(() => select(track.id)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AdvancedVideoState>(
        valueListenable: widget.advanced,
        builder: (context, state, _) => ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(context.l10n.videoAdvanced),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null || state.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.l10n.errorWithDetails(_error ?? state.error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (state.supportsAudioTracks)
                _tracks(
                  context.l10n.videoAudioTracks,
                  state.audioTracks,
                  widget.advanced.selectAudioTrack,
                ),
              if (state.supportsSubtitles)
                _tracks(
                  context.l10n.videoSubtitles,
                  state.subtitleTracks,
                  widget.advanced.selectSubtitleTrack,
                  subtitles: true,
                ),
              if (state.supportsExternalSubtitles)
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: Text(context.l10n.videoImportSubtitle),
                  onTap: _busy ? null : _importSubtitle,
                ),
              if (state.supportsAudioDelay)
                ListTile(
                  title: Text(context.l10n.videoAudioDelay),
                  subtitle: Text('${state.audioDelay.inMilliseconds} ms'),
                  onTap: _busy ? null : () => _delay(true),
                ),
              if (state.supportsSubtitleDelay)
                ListTile(
                  title: Text(context.l10n.videoSubtitleDelay),
                  subtitle: Text('${state.subtitleDelay.inMilliseconds} ms'),
                  onTap: _busy ? null : () => _delay(false),
                ),
              if (state.supportsAbLoop) ...[
                ListTile(
                  title: Text(context.l10n.videoAbLoop),
                  subtitle: Text(
                      'A: ${state.abLoopStart == null ? '—' : formatVideoTime(state.abLoopStart!)}'
                      '   B: ${state.abLoopEnd == null ? '—' : formatVideoTime(state.abLoopEnd!)}'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => widget.advanced.setAbLoop(
                                    widget.controller.value.position,
                                    null,
                                  ),
                                ),
                        child: Text(context.l10n.videoSetA),
                      ),
                      OutlinedButton(
                        onPressed: _busy || state.abLoopStart == null
                            ? null
                            : () => _run(
                                  () => widget.advanced.setAbLoop(
                                    state.abLoopStart,
                                    widget.controller.value.position,
                                  ),
                                ),
                        child: Text(context.l10n.videoSetB),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => widget.advanced.setAbLoop(null, null),
                                ),
                        child: Text(context.l10n.videoClearAb),
                      ),
                    ],
                  ),
                ),
              ],
              if (!state.supportsAudioTracks &&
                  !state.supportsSubtitles &&
                  !state.supportsAbLoop)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.l10n.videoAdvancedUnavailable),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
}
