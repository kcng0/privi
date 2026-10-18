import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/advanced_video_controller.dart';
import '../../core/l10n.dart';
import '../../domain/models/video_playback_settings.dart';
import 'video_player_surface.dart';

int? _parseDelayMilliseconds(String input) {
  final milliseconds = BigInt.tryParse(input);
  if (milliseconds == null) return null;
  // Duration and the native channel store signed 64-bit microseconds. Check
  // before converting units so an out-of-range input cannot wrap its sign.
  final microseconds = milliseconds * BigInt.from(1000);
  if (microseconds < BigInt.parse('-9223372036854775808') ||
      microseconds > BigInt.parse('9223372036854775807')) {
    return null;
  }
  return milliseconds.toInt();
}

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
  VideoHardwareDecodingInfo? _hardwareDecodingInfo;
  bool _hardwareDecodingReadAttempted = false;
  bool _hardwareDecodingReadScheduled = false;
  bool _hardwareDecodingNeedsRetry = false;

  @override
  void initState() {
    super.initState();
    widget.advanced.addListener(_scheduleInitialHardwareDecodingRead);
    _scheduleInitialHardwareDecodingRead();
  }

  @override
  void didUpdateWidget(covariant _AdvancedSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.advanced, widget.advanced)) return;
    oldWidget.advanced.removeListener(_scheduleInitialHardwareDecodingRead);
    widget.advanced.addListener(_scheduleInitialHardwareDecodingRead);
    _busy = false;
    _error = null;
    _hardwareDecodingInfo = null;
    _hardwareDecodingReadAttempted = false;
    _hardwareDecodingReadScheduled = false;
    _hardwareDecodingNeedsRetry = false;
    _scheduleInitialHardwareDecodingRead();
  }

  bool _isActive(AdvancedVideoController advanced) =>
      mounted &&
      identical(advanced, widget.advanced) &&
      ModalRoute.of(context)?.isCurrent == true;

  void _scheduleInitialHardwareDecodingRead() {
    if (!mounted ||
        _busy ||
        _hardwareDecodingReadAttempted ||
        _hardwareDecodingReadScheduled ||
        !widget.advanced.supportsHardwareDecodingControl) {
      return;
    }
    _hardwareDecodingReadScheduled = true;
    final advanced = widget.advanced;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(advanced, widget.advanced)) return;
      _hardwareDecodingReadScheduled = false;
      if (!_isActive(advanced) || _hardwareDecodingReadAttempted) return;
      unawaited(_readHardwareDecodingInfo());
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    final advanced = widget.advanced;
    if (_busy || !_isActive(advanced)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (_isActive(advanced)) setState(() => _error = error.toString());
    } finally {
      if (mounted && identical(advanced, widget.advanced)) {
        setState(() => _busy = false);
        if (_isActive(advanced)) _scheduleInitialHardwareDecodingRead();
      }
    }
  }

  Future<void> _readHardwareDecodingInfo() {
    final advanced = widget.advanced;
    if (!advanced.supportsHardwareDecodingControl) return Future.value();
    return _run(() async {
      _hardwareDecodingReadAttempted = true;
      _hardwareDecodingNeedsRetry = false;
      try {
        final info = await advanced.readHardwareDecodingInfo();
        if (!_isActive(advanced)) return;
        setState(() => _hardwareDecodingInfo = info);
      } catch (_) {
        if (_isActive(advanced)) {
          setState(() => _hardwareDecodingNeedsRetry = true);
        }
        rethrow;
      }
    });
  }

  Future<void> _setHardwareDecodingMode(VideoHardwareDecodingMode mode) {
    final advanced = widget.advanced;
    final info = _hardwareDecodingInfo;
    if (!advanced.supportsHardwareDecodingControl ||
        info == null ||
        info.mode == null ||
        info.mode == mode ||
        (mode == VideoHardwareDecodingMode.direct && !info.canTryDirect)) {
      return Future.value();
    }
    return _run(() async {
      _hardwareDecodingNeedsRetry = false;
      try {
        final updated = await advanced.setHardwareDecodingMode(mode);
        if (!_isActive(advanced)) return;
        setState(() => _hardwareDecodingInfo = updated);
      } catch (_) {
        if (_isActive(advanced)) {
          setState(() {
            // The native request may have changed before its status read failed.
            _hardwareDecodingInfo = null;
            _hardwareDecodingNeedsRetry = true;
          });
        }
        rethrow;
      }
    });
  }

  String _hardwareDecodingValue(String value) =>
      value.trim().isEmpty || value.trim().toLowerCase() == 'unknown'
          ? context.l10n.videoHardwareDecodingUnknown
          : value;

  Widget _hardwareDecodingControls() {
    final info = _hardwareDecodingInfo;
    final mode = info?.mode;
    final compatibleEnabled = !_busy && mode != null;
    final directEnabled = compatibleEnabled &&
        (info!.canTryDirect || mode == VideoHardwareDecodingMode.direct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: Text(context.l10n.videoHardwareDecoding),
          trailing: IconButton(
            tooltip: context.l10n.videoHardwareDecodingRefresh,
            onPressed: _busy ? null : _readHardwareDecodingInfo,
            icon: const Icon(Icons.refresh),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(context.l10n.videoHardwareDecodingSessionHelp),
        ),
        if (info != null) ...[
          ListTile(
            title: Text(context.l10n.videoHardwareDecodingRequested),
            subtitle: Text(_hardwareDecodingValue(info.requestedHwdec)),
          ),
        ],
        if (info?.hasUnspecifiedColor == true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(context.l10n.videoHardwareDecodingUnspecifiedColor),
          ),
        ListTile(
          enabled: compatibleEnabled,
          title: Text(context.l10n.videoHardwareDecodingCompatible),
          trailing: mode == VideoHardwareDecodingMode.compatible
              ? const Icon(Icons.check)
              : null,
          onTap:
              compatibleEnabled && mode != VideoHardwareDecodingMode.compatible
                  ? () => _setHardwareDecodingMode(
                        VideoHardwareDecodingMode.compatible,
                      )
                  : null,
        ),
        ListTile(
          enabled: directEnabled,
          title: Text(context.l10n.videoHardwareDecodingDirect),
          trailing: mode == VideoHardwareDecodingMode.direct
              ? const Icon(Icons.check)
              : null,
          onTap: directEnabled && mode != VideoHardwareDecodingMode.direct
              ? () => _setHardwareDecodingMode(VideoHardwareDecodingMode.direct)
              : null,
        ),
        if (info != null)
          ListTile(
            title: Text(context.l10n.videoHardwareDecodingActual),
            subtitle: Text(_hardwareDecodingValue(info.currentHwdec)),
          ),
        if (info != null &&
            !info.canTryDirect &&
            mode != VideoHardwareDecodingMode.direct)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(context.l10n.videoHardwareDecodingDirectUnavailable),
          ),
        if (info != null && mode == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(context.l10n.videoHardwareDecodingModeUnavailable),
          ),
        if (_hardwareDecodingNeedsRetry)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _busy ? null : _readHardwareDecodingInfo,
                child: Text(context.l10n.retry),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _delay(bool audio) async {
    final advanced = widget.advanced;
    final state = advanced.value;
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
            validator: (value) => _parseDelayMilliseconds(value ?? '') == null
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
                Navigator.pop(context, _parseDelayMilliseconds(input)!);
              }
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (value == null || !_isActive(advanced)) return;
    await _run(
      () => audio
          ? advanced.setAudioDelay(Duration(milliseconds: value))
          : advanced.setSubtitleDelay(Duration(milliseconds: value)),
    );
  }

  Future<void> _importSubtitle() => _run(() async {
        final advanced = widget.advanced;
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
        );
        if (picked == null || !_isActive(advanced)) return;
        final path = picked.files.single.path;
        if (path == null) {
          throw StateError('The selected subtitle has no readable path.');
        }
        await advanced.importSubtitle(path);
      });

  Future<void> _copyPlaybackDiagnostics() => _run(() async {
        final advanced = widget.advanced;
        final diagnostics = await advanced.readPlaybackDiagnostics();
        if (!mounted || !_isActive(advanced)) return;
        await Clipboard.setData(ClipboardData(text: jsonEncode(diagnostics)));
        if (!mounted || !_isActive(advanced)) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.videoPlaybackDiagnosticsCopied)),
        );
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
              if (widget.advanced.supportsHardwareDecodingControl)
                _hardwareDecodingControls(),
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
              if (widget.advanced.supportsPlaybackDiagnostics)
                ListTile(
                  key: const ValueKey('video-copy-playback-diagnostics'),
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(context.l10n.videoCopyPlaybackDiagnostics),
                  onTap: _busy ? null : _copyPlaybackDiagnostics,
                ),
              if (!state.supportsAudioTracks &&
                  !state.supportsSubtitles &&
                  !state.supportsAbLoop &&
                  !widget.advanced.supportsHardwareDecodingControl &&
                  !widget.advanced.supportsPlaybackDiagnostics)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.l10n.videoAdvancedUnavailable),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    widget.advanced.removeListener(_scheduleInitialHardwareDecodingRead);
    super.dispose();
  }
}
