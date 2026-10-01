import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/import/import_controller.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/media/rating_controller.dart';
import '../../application/player/external_player_coordinator.dart';
import '../../application/player/picture_in_picture_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../domain/enums.dart';
import '../../domain/models/media_item.dart';
import '../common/heart_rating_bar.dart';
import '../common/keep_vault_unlocked.dart';
import '../common/zoomable_media_image.dart';
import '../player/video_playback_speed.dart';
import '../player/video_player_controls.dart';
import '../player/video_player_surface.dart';
import '../player/video_presentation_session.dart';

/// Fullscreen swipe viewer with zoom, video, rating, unhide.
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  }) : assert(items.length > 0);

  final List<MediaItem> items;
  final int initialIndex;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen>
    with VideoPresentationSession<ViewerScreen> {
  late final PageController _page;
  late int _index;
  bool _chrome = true;
  bool _imageZoomed = false;
  bool _programmaticPopAllowed = false;
  VideoPlayerController? _video;
  String? _videoId;
  String? _videoError;
  String? _completedForId;
  int _videoRequest = 0;
  final _videoOps = VideoControllerQueue();
  DateTime? _ignoreAutoAdvanceUntil;
  VideoFitMode _fitMode = VideoFitMode.fit;
  double _playbackSpeed = 1;
  bool _muted = false;
  bool _looping = false;
  bool? _lastImmersive;

  @override
  void initState() {
    super.initState();
    _playbackSpeed = ref.read(settingsControllerProvider).playerPlaybackSpeed;
    _fitMode = ref.read(settingsControllerProvider).playerFitMode;
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _page = PageController(initialPage: _index);
    unawaited(VideoSystemUi.apply(false));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_syncVideo()),
    );
  }

  @override
  void dispose() {
    _videoRequest++;
    final c = _video;
    _video = null;
    _videoId = null;
    _videoError = null;
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

  MediaItem get _current => widget.items[_index];
  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index < widget.items.length - 1;

  bool _isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  void _syncSystemUi(bool immersive) {
    if (_lastImmersive == immersive) return;
    _lastImmersive = immersive;
    unawaited(VideoSystemUi.apply(immersive));
  }

  Future<void> _toggleOrientation(BuildContext context) =>
      chooseVideoOrientation();

  Future<void> _syncVideo() {
    final item = _current;
    final request = ++_videoRequest;
    return _videoOps.enqueue(() => _syncVideoBody(request, item));
  }

  Future<void> _syncVideoBody(int request, MediaItem item) async {
    if (!mounted || request != _videoRequest) return;
    if (!item.isVideo) {
      await _detachVideo();
      return;
    }
    if (_videoId == item.id && _video != null) return;
    await _detachVideo();
    if (!mounted || request != _videoRequest) return;
    final file = File(item.privatePath);
    if (!file.existsSync()) {
      setState(
        () => _videoError = 'Video file does not exist: ${item.privatePath}',
      );
      return;
    }
    if (!mounted || request != _videoRequest) return;
    final c = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    bool current() =>
        mounted && request == _videoRequest && _current.id == item.id;
    try {
      await c.initialize();
      if (!current()) return;
      await c.setLooping(_looping);
      if (!current()) return;
      await c.setVolume(_muted ? 0 : 1);
      if (!current()) return;
      await c.setPlaybackSpeed(_playbackSpeed);
      await playVideoWhenAllowed(c, item.id, isCurrent: current);
      if (!current()) return;
      c.addListener(() {
        if (mounted) _maybeAdvanceOnVideoEnd(c, item.id);
      });
      setState(() {
        _video = c;
        _videoId = item.id;
        _videoError = null;
        _completedForId = null;
      });
    } catch (error) {
      if (current()) setState(() => _videoError = error.toString());
    } finally {
      if (!identical(_video, c)) {
        releaseVideoPlayback(c);
        await c.dispose();
      }
    }
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

  Future<void> _disposeVideo() {
    _videoRequest++;
    return _videoOps.enqueue(_detachVideo);
  }

  Future<void> _detachVideo() async {
    detachVideoPresentation();
    final c = _video;
    _video = null;
    _videoId = null;
    _videoError = null;
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
    if (mounted) setState(() {});
  }

  void _exitViewer() {
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

  Future<void> _showItem(int index) async {
    if (index < 0 || index >= widget.items.length || index == _index) return;
    if (!mounted) return;
    if (!_page.hasClients) {
      setState(() => _index = index);
      await _syncVideo();
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
    setState(() {
      _index = index;
      _imageZoomed = false;
    });
    await _syncVideo();
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

  Future<void> _chooseFit() async {
    final selected = await showVideoFitModeSheet(context, current: _fitMode);
    if (selected != null && mounted) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setPlayerFitMode(selected);
      if (mounted) setState(() => _fitMode = selected);
    }
  }

  Future<void> _openSettings() async {
    final settings = ref.read(settingsControllerProvider);
    final externalSupported =
        ref.read(externalPlayerCoordinatorProvider).supported;
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
      onOpenExternal:
          externalSupported ? () => unawaited(_openExternal()) : null,
      rating: _current.rating,
      onRatingChanged: (rating) => _setRating(_current, rating),
    );
  }

  Future<void> _openExternal() async {
    final item = _current;
    final external = ref.read(externalPlayerCoordinatorProvider);
    if (!item.isVideo || !external.supported) return;
    final video = _video;
    if (video != null) await video.pause();
    await external.open(filePath: item.privatePath, mimeType: item.mimeType);
  }

  void _setRating(MediaItem item, int rating) {
    unawaited(
      ref.read(ratingControllerProvider.notifier).setRating(item.id, rating),
    );
    setState(() {
      widget.items[_index] = item.copyWith(rating: rating);
    });
  }

  void _toggleChrome() {
    if (videoChromeAllowed) setState(() => _chrome = !_chrome);
  }

  void _hideChrome() {
    if (_chrome && videoChromeAllowed) setState(() => _chrome = false);
  }

  Future<void> _unhide() async {
    final item = _current;
    final ok = await ref.read(importServiceProvider).reveal(item);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.couldNotUnhideFile)));
      return;
    }
    // Same Visible refresh path as batch unhide (no manual pull needed).
    await ref
        .read(importControllerProvider.notifier)
        .refreshVisibleAfterReveal();
    if (!mounted) return;
    if (widget.items.length == 1) {
      _exitViewer();
      return;
    }
    await _disposeVideo();
    setState(() {
      widget.items.removeAt(_index);
      if (_index >= widget.items.length) _index = widget.items.length - 1;
    });
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _page.hasClients) _page.jumpToPage(_index);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.restoredToGallery)));
    await _syncVideo();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pictureInPictureControllerProvider);
    final item = _current;
    final landscape = _isLandscape(context);
    final immersive = shouldHideSystemUiForBuiltInVideo(item.isVideo);
    _syncSystemUi(immersive);
    if (item.isVideo &&
        _video != null &&
        _videoId == item.id &&
        _video!.value.isInitialized) {
      bindVideoPresentation(_video!, item.privatePath);
    }

    return KeepVaultUnlocked(
      child: PopScope(
        canPop: item.isVideo || !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          await _disposeVideo();
        },
        child: AutoHideVideoControls(
          enabled: item.isVideo,
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
                  physics: item.isVideo || _imageZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (index) => unawaited(_onPageChanged(index)),
                  itemBuilder: (context, index) =>
                      _mediaPage(widget.items[index], index == _index),
                ),
                if (_chrome &&
                    videoChromeAllowed &&
                    item.isVideo &&
                    _video != null &&
                    _videoId == item.id &&
                    _video!.value.isInitialized)
                  _centerVideoControls(),
                if (videoTouchLocked && !videoPipGranted) videoUnlockControl(),
                if (_chrome && videoChromeAllowed) _topBar(item),
                if (_chrome && videoChromeAllowed && item.isVideo)
                  _videoBottomBar(item, landscape)
                else if (_chrome && videoChromeAllowed)
                  _imageBottomBar(item, landscape),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaPage(MediaItem item, bool active) {
    final file = File(item.privatePath);
    if (!file.existsSync()) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 64,
          ),
        ),
      );
    }
    if (item.isVideo) return _videoPage(item, active);
    return ZoomableMediaImage(
      file: file,
      heroTag: 'media-hero-${item.id}',
      onTap: _toggleChrome,
      onZoomChanged: (zoomed) {
        if (_imageZoomed == zoomed) return;
        setState(() => _imageZoomed = zoomed);
      },
    );
  }

  Widget _videoPage(MediaItem item, bool active) {
    if (active && _videoError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.errorWithDetails(_videoError!),
                style: const TextStyle(color: Colors.white70),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _videoError = null);
                  unawaited(_syncVideo());
                },
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      );
    }
    final video = _video;
    if (!active ||
        video == null ||
        _videoId != item.id ||
        !video.value.isInitialized) {
      final thumb = item.thumbnailPath;
      if (thumb != null && File(thumb).existsSync()) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleChrome,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.file(File(thumb), fit: BoxFit.contain),
              Icon(
                active ? Icons.hourglass_top : Icons.play_circle_fill,
                size: 64,
                color: Colors.white70,
              ),
            ],
          ),
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        child: Center(
          child: Icon(
            active ? Icons.hourglass_top : Icons.videocam,
            size: 72,
            color: Colors.white54,
          ),
        ),
      );
    }
    return videoViewportWithLifecycle(
      controller: video,
      mediaId: item.id,
      fitMode: _fitMode,
      onTap: _toggleChrome,
      onUserSeek: _markUserSeek,
    );
  }

  Widget _topBar(MediaItem item) {
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
                      onPressed: _exitViewer,
                    ),
                    Expanded(
                      child: Text(
                        compact
                            ? '${item.originalName} · ${_index + 1}/${widget.items.length}'
                            : item.originalName,
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
                    if (!compact || _video == null)
                      PopupMenuButton<String>(
                        icon:
                            const Icon(Icons.more_vert, color: Colors.white70),
                        onSelected: (value) {
                          if (value == 'unhide') unawaited(_unhide());
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'unhide',
                            child: Text(context.l10n.unhideRestoreOriginal),
                          ),
                        ],
                      ),
                    if (_video != null)
                      videoSessionTopActions(
                        compact: compact,
                        additionalMenuItems: [
                          PopupMenuItem(
                            value: () => unawaited(_unhide()),
                            child: Text(context.l10n.unhideRestoreOriginal),
                          ),
                        ],
                      ),
                    if (!compact) const SizedBox(width: 4),
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

  Widget _videoBottomBar(MediaItem item, bool landscape) {
    final video = _video;
    if (video == null || _videoId != item.id || !video.value.isInitialized) {
      return _imageBottomBar(item, landscape);
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: video,
        builder: (context, value, _) {
          return VideoBottomControls(
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
          );
        },
      ),
    );
  }

  Widget _imageBottomBar(MediaItem item, bool landscape) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HeartRatingBar(
                  rating: item.rating,
                  size: 28,
                  interactive: true,
                  scrim: false,
                  onRate: (rating) => _setRating(item, rating),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
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
                      onPressed: _hasNext
                          ? () => unawaited(_showItem(_index + 1))
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
