import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/import/import_controller.dart';
import '../../application/media/rating_controller.dart';
import '../../application/player/external_player_coordinator.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../domain/models/media_item.dart';
import '../common/heart_rating_bar.dart';
import '../common/keep_vault_unlocked.dart';
import '../player/video_player_controls.dart';
import '../player/video_player_surface.dart';

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

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final PageController _page;
  late int _index;
  bool _chrome = true;
  bool _programmaticPopAllowed = false;
  VideoPlayerController? _video;
  String? _videoId;
  int _videoRequest = 0;
  VideoFitMode _fitMode = VideoFitMode.fit;
  double _playbackSpeed = 1;
  bool _muted = false;
  bool _looping = false;
  bool? _lastImmersive;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _page = PageController(initialPage: _index);
    unawaited(VideoSystemUi.apply(false));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_syncVideo()));
  }

  @override
  void dispose() {
    _videoRequest++;
    final c = _video;
    _video = null;
    _videoId = null;
    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
      // ignore: discarded_futures
      c.dispose();
    }
    unawaited(VideoSystemUi.restore());
    _page.dispose();
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

  Future<void> _toggleOrientation(BuildContext context) async {
    await VideoSystemUi.toggle(_isLandscape(context));
  }

  Future<void> _syncVideo() async {
    final item = _current;
    final request = ++_videoRequest;
    if (!item.isVideo) {
      await _detachVideo();
      return;
    }
    if (_videoId == item.id && _video != null) return;
    await _detachVideo();
    final file = File(item.privatePath);
    if (!await file.exists()) return;
    final c = VideoPlayerController.file(file);
    await c.initialize();
    await c.setLooping(_looping);
    await c.setVolume(_muted ? 0 : 1);
    await c.setPlaybackSpeed(_playbackSpeed);
    await c.play();
    if (!mounted || request != _videoRequest || _current.id != item.id) {
      await c.dispose();
      return;
    }
    setState(() {
      _video = c;
      _videoId = item.id;
    });
  }

  Future<void> _disposeVideo() async {
    _videoRequest++;
    await _detachVideo();
  }

  Future<void> _detachVideo() async {
    final c = _video;
    _video = null;
    _videoId = null;
    if (c != null) {
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
    if (!_page.hasClients) {
      setState(() => _index = index);
      await _syncVideo();
      return;
    }
    await _page.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onPageChanged(int index) async {
    setState(() => _index = index);
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
    await video.play();
    await video.setPlaybackSpeed(_playbackSpeed);
  }

  void _seekTo(Duration position) {
    final video = _video;
    if (video != null) unawaited(video.seekTo(position));
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
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

  Future<void> _chooseFit() async {
    final selected = await showVideoFitModeSheet(
      context,
      current: _fitMode,
    );
    if (selected != null && mounted) setState(() => _fitMode = selected);
  }

  Future<void> _openSettings() async {
    final settings = ref.read(settingsControllerProvider);
    final externalSupported =
        ref.read(externalPlayerCoordinatorProvider).supported;
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
      onOpenExternal:
          externalSupported ? () => unawaited(_openExternal()) : null,
    );
  }

  Future<void> _openExternal() async {
    final item = _current;
    final external = ref.read(externalPlayerCoordinatorProvider);
    if (!item.isVideo || !external.supported) return;
    final video = _video;
    if (video != null) await video.pause();
    await external.open(
      filePath: item.privatePath,
      mimeType: item.mimeType,
    );
  }

  void _setRating(MediaItem item, int rating) {
    unawaited(
      ref.read(ratingControllerProvider.notifier).setRating(item.id, rating),
    );
    setState(() {
      widget.items[_index] = item.copyWith(rating: rating);
    });
  }

  void _toggleFavorite(MediaItem item) {
    _setRating(item, item.rating >= 1 ? 0 : 1);
  }

  Future<void> _unhide() async {
    final item = _current;
    final ok = await ref.read(importServiceProvider).reveal(item);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotUnhideFile)),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.restoredToGallery)),
    );
    await _syncVideo();
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    final landscape = _isLandscape(context);
    final immersive = landscape && item.isVideo;
    _syncSystemUi(immersive);

    return KeepVaultUnlocked(
      child: PopScope(
        canPop: !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          await _disposeVideo();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _page,
                itemCount: widget.items.length,
                physics: item.isVideo
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (index) => unawaited(_onPageChanged(index)),
                itemBuilder: (context, index) =>
                    _mediaPage(widget.items[index], index == _index),
              ),
              if (_chrome && !immersive) _topBar(item),
              if (_chrome && item.isVideo)
                _videoBottomBar(item, landscape)
              else if (_chrome)
                _imageBottomBar(item, landscape),
            ],
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
        onTap: () => setState(() => _chrome = !_chrome),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _chrome = !_chrome),
      child: Center(
        child: InteractiveViewer(
          child: Hero(
            tag: 'media-hero-${item.id}',
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _videoPage(MediaItem item, bool active) {
    final video = _video;
    if (!active ||
        video == null ||
        _videoId != item.id ||
        !video.value.isInitialized) {
      final thumb = item.thumbnailPath;
      if (thumb != null && File(thumb).existsSync()) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _chrome = !_chrome),
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
        onTap: () => setState(() => _chrome = !_chrome),
        child: Center(
          child: Icon(
            active ? Icons.hourglass_top : Icons.videocam,
            size: 72,
            color: Colors.white54,
          ),
        ),
      );
    }
    return VideoGestureSurface(
      controller: video,
      seekSeconds: ref.watch(settingsControllerProvider).playerSeekSeconds,
      onTap: () => setState(() => _chrome = !_chrome),
      child: VideoViewport(controller: video, fitMode: _fitMode),
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
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _exitViewer,
                ),
                Expanded(
                  child: Text(
                    item.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                Text(
                  '${_index + 1}/${widget.items.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
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
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoBottomBar(MediaItem item, bool landscape) {
    final video = _video;
    if (video == null || _videoId != item.id || !video.value.isInitialized) {
      return _imageBottomBar(item, landscape);
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!landscape) _ratingStrip(item),
          ValueListenableBuilder<VideoPlayerValue>(
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
                onToggleOrientation: () =>
                    unawaited(_toggleOrientation(context)),
                onChooseFit: () => unawaited(_chooseFit()),
                onOpenSettings: () => unawaited(_openSettings()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _ratingStrip(MediaItem item) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HeartRatingBar(
              rating: item.rating,
              size: 26,
              interactive: true,
              scrim: false,
              onRate: (rating) => _setRating(item, rating),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: context.l10n.favoriteToggle,
              icon: Icon(Icons.favorite, color: context.vaultColors.heart),
              onPressed: () => _toggleFavorite(item),
            ),
          ],
        ),
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
                      tooltip: context.l10n.favoriteToggle,
                      onPressed: () => _toggleFavorite(item),
                      icon: Icon(
                        Icons.favorite,
                        color: context.vaultColors.heart,
                      ),
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
