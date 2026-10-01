import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../application/lock/lock_controller.dart';
import '../../application/player/picture_in_picture_controller.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../data/services/gallery_service.dart';
import '../../domain/enums.dart';
import '../common/keep_vault_unlocked.dart';
import '../common/zoomable_media_image.dart';
import '../player/video_playback_speed.dart';
import '../player/video_player_controls.dart';
import '../player/video_player_surface.dart';
import '../player/video_presentation_session.dart';

typedef GalleryAssetFileResolver = Future<File?> Function(GalleryAsset asset);

Future<File?> resolveGalleryAssetFile(GalleryAsset asset) async {
  final entity = await AssetEntity.fromId(asset.id);
  return entity?.file;
}

/// Fullscreen preview for a Visible-tab gallery asset (tap to open).
class GalleryPreviewScreen extends ConsumerStatefulWidget {
  const GalleryPreviewScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.resolveFile = resolveGalleryAssetFile,
  }) : assert(items.length > 0);

  final List<GalleryAsset> items;
  final int initialIndex;
  final GalleryAssetFileResolver resolveFile;

  @override
  ConsumerState<GalleryPreviewScreen> createState() =>
      _GalleryPreviewScreenState();
}

class _GalleryPreviewScreenState extends ConsumerState<GalleryPreviewScreen>
    with VideoPresentationSession<GalleryPreviewScreen> {
  late final PageController _page;
  VideoPlayerController? _video;
  File? _file;
  String? _error;
  String? _completedForId;
  bool _loading = true;
  bool _chrome = true;
  bool _imageZoomed = false;
  late int _index;
  int _loadRequest = 0;
  final _videoOps = VideoControllerQueue();
  DateTime? _ignoreAutoAdvanceUntil;
  bool _programmaticPopAllowed = false;
  bool _muted = false;
  bool _looping = false;
  double _playbackSpeed = 1;
  VideoFitMode _fitMode = VideoFitMode.fit;
  bool? _lastImmersive;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _page = PageController(initialPage: _index);
    _playbackSpeed = ref.read(settingsControllerProvider).playerPlaybackSpeed;
    _fitMode = ref.read(settingsControllerProvider).playerFitMode;
    unawaited(VideoSystemUi.apply(false));
    _loadCurrent();
  }

  GalleryAsset get _current => widget.items[_index];
  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index < widget.items.length - 1;

  Future<void> _loadCurrent() {
    final request = ++_loadRequest;
    return _videoOps.enqueue(() => _loadCurrentBody(request));
  }

  Future<void> _loadCurrentBody(int request) async {
    if (!mounted || request != _loadRequest) return;
    await _stopVideo();
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _loading = true;
      _error = null;
      _file = null;
    });
    VideoPlayerController? candidate;
    try {
      final item = _current;
      final file = await widget.resolveFile(item);
      if (!mounted || request != _loadRequest) return;
      if (file == null || !await file.exists()) {
        setState(() {
          _error = 'Could not open file';
          _loading = false;
        });
        return;
      }
      if (item.isVideo) {
        final c = candidate = VideoPlayerController.file(
          file,
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
        );
        await c.initialize();
        if (!mounted || request != _loadRequest) {
          return;
        }
        await c.setLooping(_looping);
        if (!mounted || request != _loadRequest) return;
        await c.setVolume(_muted ? 0 : 1);
        if (!mounted || request != _loadRequest) return;
        await c.setPlaybackSpeed(_playbackSpeed);
        await playVideoWhenAllowed(
          c,
          item.id,
          isCurrent: () =>
              mounted && request == _loadRequest && _current.id == item.id,
        );
        if (!mounted || request != _loadRequest) {
          return;
        }
        c.addListener(() {
          if (!mounted) return;
          _maybeAdvanceOnVideoEnd(c, item.id);
        });
        setState(() {
          _video = c;
          _file = file;
          _loading = false;
          _completedForId = null;
        });
      } else {
        if (!mounted || request != _loadRequest) return;
        setState(() {
          _file = file;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    } finally {
      if (candidate != null && !identical(_video, candidate)) {
        releaseVideoPlayback(candidate);
        await candidate.dispose();
      }
    }
  }

  Future<void> _showItem(int index) async {
    if (index < 0 || index >= widget.items.length || index == _index) return;
    if (!mounted) return;
    if (!_page.hasClients) {
      setState(() => _index = index);
      await _loadCurrent();
      return;
    }
    try {
      await _page.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      if (!mounted || !_page.hasClients) return;
      _page.jumpToPage(index);
    }
  }

  Future<void> _onPageChanged(int index) async {
    if (index == _index) return;
    setState(() {
      _index = index;
      _imageZoomed = false;
    });
    await _loadCurrent();
  }

  void _markUserSeek() {
    _ignoreAutoAdvanceUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
  }

  void _maybeAdvanceOnVideoEnd(VideoPlayerController video, String itemId) {
    if (!videoMayAdvance ||
        !identical(_video, video) ||
        videoPipGranted ||
        videoAdvanced?.value.abLoopEnd != null) {
      return;
    }
    final unlocked =
        ref.read(lockControllerProvider).status == LockStatus.unlocked;
    if (!shouldAdvanceFolderVideoOnEnd(
      value: video.value,
      looping: _looping,
      vaultUnlocked: unlocked,
      isCurrentItem: _current.id == itemId,
      alreadyAdvanced: _completedForId == itemId,
      ignoreUntil: _ignoreAutoAdvanceUntil,
    )) {
      return;
    }
    _completedForId = itemId;
    final nextIndex = nextIndexAfterVideoEnd(
      index: _index,
      length: widget.items.length,
      looping: _looping,
      ended: true,
    );
    if (nextIndex == null) return;
    unawaited(_showItem(nextIndex));
  }

  Future<void> _stopVideo() async {
    detachVideoPresentation();
    final c = _video;
    _video = null;
    _completedForId = null;
    if (c != null) {
      releaseVideoPlayback(c);
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
    _loadRequest++;
    final c = _video;
    _video = null;
    _completedForId = null;
    if (c != null) {
      releaseVideoPlayback(c);
      try {
        c.pause();
      } catch (_) {}
      // ignore: discarded_futures
      c.dispose();
    }
    unawaited(VideoSystemUi.restore());
    _page.dispose();
    disposeVideoPresentation();
    super.dispose();
  }

  bool _isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  void _syncSystemUi(bool immersive) {
    if (_lastImmersive == immersive) return;
    _lastImmersive = immersive;
    unawaited(VideoSystemUi.apply(immersive));
  }

  Future<void> _toggleOrientation(BuildContext context) =>
      chooseVideoOrientation();

  Future<void> _chooseFit() async {
    final selected = await showVideoFitModeSheet(context, current: _fitMode);
    if (selected != null && mounted) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setPlayerFitMode(selected);
      if (mounted) setState(() => _fitMode = selected);
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final video = _video;
    if (video == null) throw StateError('There is no active video.');
    final settings = ref.read(settingsControllerProvider.notifier);
    await updateVideoPlaybackSpeed(
      controller: video,
      speed: speed,
      previousSpeed: _playbackSpeed,
      isCurrent: () => mounted && identical(_video, video),
      persist: () => settings.setPlayerPlaybackSpeed(speed),
    );
    if (mounted) setState(() => _playbackSpeed = speed);
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
    if (!mounted || !identical(_video, video)) return;
    final itemId = _current.id;
    await video.setPlaybackSpeed(_playbackSpeed);
    await playVideoWhenAllowed(
      video,
      itemId,
      isCurrent: () =>
          mounted && identical(_video, video) && _current.id == itemId,
    );
  }

  Future<void> _seekTo(Duration position) async {
    final video = _video;
    if (video == null) return;
    _markUserSeek();
    await video.seekTo(position);
  }

  Future<void> _openSettings() async {
    final settings = ref.read(settingsControllerProvider);
    await showVideoSettingsSheet(
      context,
      advanced: videoAdvanced,
      controller: _video,
      defaultOrientation: settings.playerDefaultOrientation,
      onDefaultOrientationChanged: (mode) => unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setPlayerDefaultOrientation(mode),
      ),
      seekSeconds: settings.playerSeekSeconds,
      onSeekSecondsChanged: (seconds) => unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setPlayerSeekSeconds(seconds),
      ),
      dragSeekSeconds: settings.playerDragSeekSeconds,
      onDragSeekSecondsChanged: (seconds) => unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setPlayerDragSeekSeconds(seconds),
      ),
      playbackSpeed: _playbackSpeed,
      onPlaybackSpeedChanged: _setPlaybackSpeed,
      muted: _muted,
      onMutedChanged: _setMuted,
      looping: _looping,
      onLoopingChanged: _setLooping,
    );
  }

  void _toggleChrome() {
    if (videoChromeAllowed) setState(() => _chrome = !_chrome);
  }

  void _hideChrome() {
    if (_chrome && videoChromeAllowed) setState(() => _chrome = false);
  }

  void _exit() {
    final video = _video;
    if (video != null) unawaited(video.pause());
    setState(() => _programmaticPopAllowed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pictureInPictureControllerProvider);
    final landscape = _isLandscape(context);
    final immersive = shouldHideSystemUiForBuiltInVideo(_current.isVideo);
    _syncSystemUi(immersive);
    if (_current.isVideo && _video != null && _video!.value.isInitialized) {
      bindVideoPresentation(_video!, _file!.path);
    }
    return KeepVaultUnlocked(
      child: PopScope(
        canPop: _current.isVideo || !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          await _stopVideo();
        },
        child: AutoHideVideoControls(
          enabled: _current.isVideo,
          visible: _chrome && videoChromeAllowed,
          onHide: _hideChrome,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  key: const Key('folder-media-page-view'),
                  controller: _page,
                  itemCount: widget.items.length,
                  physics: _current.isVideo || _imageZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (index) => unawaited(_onPageChanged(index)),
                  itemBuilder: (context, index) =>
                      _pageContent(index == _index),
                ),
                if (_chrome &&
                    videoChromeAllowed &&
                    _current.isVideo &&
                    _video != null &&
                    _video!.value.isInitialized)
                  _centerVideoControls(),
                if (videoTouchLocked && !videoPipGranted) videoUnlockControl(),
                if (_chrome && videoChromeAllowed) _topBar(),
                if (_chrome &&
                    videoChromeAllowed &&
                    _current.isVideo &&
                    _video != null &&
                    _video!.value.isInitialized)
                  _videoBottomBar(landscape)
                else if (_chrome && videoChromeAllowed && !_current.isVideo)
                  _imageBottomBar(landscape),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageContent(bool active) {
    if (!active) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    final video = _video;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    if (_error != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        child: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    if (_current.isVideo && video != null && video.value.isInitialized) {
      return videoViewportWithLifecycle(
        controller: video,
        mediaId: _current.id,
        fitMode: _fitMode,
        onTap: _toggleChrome,
        onUserSeek: _markUserSeek,
      );
    }
    if (_file != null && !_current.isVideo) {
      return ZoomableMediaImage(
        file: _file!,
        onTap: _toggleChrome,
        onZoomChanged: (zoomed) {
          if (_imageZoomed == zoomed) return;
          setState(() => _imageZoomed = zoomed);
        },
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleChrome,
      child: const SizedBox.expand(),
    );
  }

  Widget _topBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          child: SizedBox(
            height: kToolbarHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 320;
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _exit,
                    ),
                    Expanded(
                      child: Text(
                        compact
                            ? '${_current.title} · ${_index + 1}/${widget.items.length}'
                            : _current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    if (!compact)
                      Text(
                        '${_index + 1}/${widget.items.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    if (!compact) const SizedBox(width: 12),
                    if (_video != null)
                      videoSessionTopActions(compact: compact),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerVideoControls() => VideoTransportRegion(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _video!,
          builder: (context, value, _) => VideoTransportControls(
            value: value,
            hasPrevious: _hasPrevious,
            hasNext: _hasNext,
            onPrevious: () => unawaited(_showItem(_index - 1)),
            onPlayPause: _togglePlayPause,
            onNext: () => unawaited(_showItem(_index + 1)),
          ),
        ),
      );

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
          hasPrevious: _hasPrevious,
          hasNext: _hasNext,
          onPrevious: () => unawaited(_showItem(_index - 1)),
          onSeek: _seekTo,
          onPlayPause: _togglePlayPause,
          onNext: () => unawaited(_showItem(_index + 1)),
          onToggleOrientation: () => unawaited(_toggleOrientation(context)),
          onChooseFit: () => unawaited(_chooseFit()),
          onOpenSettings: () => unawaited(_openSettings()),
          showTransport: false,
          onOpenTracks: () => unawaited(openVideoAdvanced()),
          onPictureInPicture: videoPipSupported
              ? () => unawaited(enterVideoPictureInPicture())
              : null,
          onPreviewFrameRequested: videoPreviewFrame,
        ),
      ),
    );
  }

  Widget _imageBottomBar(bool landscape) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: context.l10n.previousMedia,
                  color: Colors.white,
                  onPressed: _hasPrevious
                      ? () => unawaited(_showItem(_index - 1))
                      : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: landscape
                      ? context.l10n.portrait
                      : context.l10n.landscape,
                  color: Colors.white,
                  onPressed: () => unawaited(_toggleOrientation(context)),
                  icon: Icon(
                    landscape
                        ? Icons.stay_current_portrait
                        : Icons.stay_current_landscape,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.nextMedia,
                  color: Colors.white,
                  onPressed:
                      _hasNext ? () => unawaited(_showItem(_index + 1)) : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
