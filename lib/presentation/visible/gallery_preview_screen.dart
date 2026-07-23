import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../application/settings/settings_controller.dart';
import '../../data/services/video_frame_service.dart';
import '../common/keep_vault_unlocked.dart';
import '../player/video_player_controls.dart';
import '../player/video_player_surface.dart';

/// Fullscreen preview for a Visible-tab gallery asset (tap to open).
class GalleryPreviewScreen extends ConsumerStatefulWidget {
  const GalleryPreviewScreen({
    super.key,
    required this.assetId,
    required this.title,
    required this.isVideo,
  });

  final String assetId;
  final String title;
  final bool isVideo;

  @override
  ConsumerState<GalleryPreviewScreen> createState() =>
      _GalleryPreviewScreenState();
}

class _GalleryPreviewScreenState extends ConsumerState<GalleryPreviewScreen> {
  VideoPlayerController? _video;
  File? _file;
  String? _error;
  bool _loading = true;
  bool _chrome = true;
  bool _programmaticPopAllowed = false;
  bool _muted = false;
  bool _looping = false;
  double _playbackSpeed = 1;
  VideoFitMode _fitMode = VideoFitMode.fit;
  bool? _lastImmersive;

  @override
  void initState() {
    super.initState();
    _playbackSpeed = ref.read(settingsControllerProvider).playerPlaybackSpeed;
    unawaited(VideoSystemUi.apply(false));
    _load();
  }

  Future<void> _load() async {
    try {
      final entity = await AssetEntity.fromId(widget.assetId);
      if (entity == null) {
        setState(() {
          _error = 'Media not found';
          _loading = false;
        });
        return;
      }
      final file = await entity.file;
      if (file == null || !await file.exists()) {
        setState(() {
          _error = 'Could not open file';
          _loading = false;
        });
        return;
      }
      if (widget.isVideo) {
        final c = VideoPlayerController.file(file);
        await c.initialize();
        await c.setLooping(_looping);
        await c.setVolume(_muted ? 0 : 1);
        await c.setPlaybackSpeed(_playbackSpeed);
        await c.play();
        if (!mounted) {
          await c.dispose();
          return;
        }
        setState(() {
          _video = c;
          _file = file;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _file = file;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _stopVideo() async {
    final c = _video;
    _video = null;
    if (c != null) {
      try {
        await c.pause();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    final c = _video;
    _video = null;
    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
      // ignore: discarded_futures
      c.dispose();
    }
    unawaited(VideoSystemUi.restore());
    super.dispose();
  }

  bool _isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  void _syncSystemUi(bool immersive) {
    if (_lastImmersive == immersive) return;
    _lastImmersive = immersive;
    unawaited(VideoSystemUi.apply(immersive));
  }

  Future<void> _toggleOrientation(BuildContext context) async {
    await VideoSystemUi.toggle(_isLandscape(context));
  }

  Future<void> _chooseFit() async {
    final selected = await showVideoFitModeSheet(context, current: _fitMode);
    if (selected != null && mounted) setState(() => _fitMode = selected);
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setPlayerPlaybackSpeed(speed),
    );
    final video = _video;
    if (video != null) unawaited(video.setPlaybackSpeed(speed));
  }

  void _setMuted(bool muted) {
    setState(() => _muted = muted);
    final video = _video;
    if (video != null) unawaited(video.setVolume(muted ? 0 : 1));
  }

  void _setLooping(bool looping) {
    setState(() => _looping = looping);
    final video = _video;
    if (video != null) unawaited(video.setLooping(looping));
  }

  void _togglePlayPause() {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      unawaited(video.pause());
      return;
    }
    unawaited(_playFromCurrentPosition(video));
  }

  Future<void> _playFromCurrentPosition(VideoPlayerController video) async {
    final value = video.value;
    if (value.isCompleted ||
        (value.duration > Duration.zero && value.position >= value.duration)) {
      await video.seekTo(Duration.zero);
    }
    await video.play();
    await video.setPlaybackSpeed(_playbackSpeed);
  }

  Future<void> _seekTo(Duration position) async {
    final video = _video;
    if (video != null) await video.seekTo(position);
  }

  Future<void> _openSettings() async {
    final settings = ref.read(settingsControllerProvider);
    await showVideoSettingsSheet(
      context,
      seekSeconds: settings.playerSeekSeconds,
      onSeekSecondsChanged: (seconds) => unawaited(
        ref.read(settingsControllerProvider.notifier).setPlayerSeekSeconds(
              seconds,
            ),
      ),
      playbackSpeed: _playbackSpeed,
      onPlaybackSpeedChanged: _setPlaybackSpeed,
      muted: _muted,
      onMutedChanged: _setMuted,
      looping: _looping,
      onLoopingChanged: _setLooping,
    );
  }

  void _exit() {
    final video = _video;
    if (video != null) unawaited(video.pause());
    setState(() {
      _chrome = false;
      _programmaticPopAllowed = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape = _isLandscape(context);
    final immersive = landscape && widget.isVideo;
    _syncSystemUi(immersive);
    return KeepVaultUnlocked(
      child: PopScope(
        canPop: !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          await _stopVideo();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _content(),
              if (_chrome && !immersive) _topBar(),
              if (_chrome &&
                  widget.isVideo &&
                  _video != null &&
                  _video!.value.isInitialized)
                _videoBottomBar(landscape),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final video = _video;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white70)),
      );
    }
    if (widget.isVideo && video != null && video.value.isInitialized) {
      return VideoGestureSurface(
        controller: video,
        seekSeconds: ref.watch(settingsControllerProvider).playerSeekSeconds,
        onTap: () => setState(() => _chrome = !_chrome),
        onPreviewFrameRequested: (position) => VideoFrameService().frameAtTime(
          path: _file!.path,
          position: position,
        ),
        child: VideoViewport(controller: video, fitMode: _fitMode),
      );
    }
    if (_file != null) {
      return InteractiveViewer(
        child: Image.file(_file!, fit: BoxFit.contain),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _topBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          child: SizedBox(
            height: kToolbarHeight,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _exit,
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoBottomBar(bool landscape) {
    final video = _video!;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: video,
        builder: (context, value, _) => VideoBottomControls(
          value: value,
          landscape: landscape,
          fitMode: _fitMode,
          title: widget.title,
          hasPrevious: false,
          hasNext: false,
          onPrevious: () {},
          onSeek: _seekTo,
          onPlayPause: _togglePlayPause,
          onNext: () {},
          onToggleOrientation: () => unawaited(_toggleOrientation(context)),
          onChooseFit: () => unawaited(_chooseFit()),
          onOpenSettings: () => unawaited(_openSettings()),
          onPreviewFrameRequested: (position) =>
              VideoFrameService().frameAtTime(
            path: _file!.path,
            position: position,
          ),
        ),
      ),
    );
  }
}
