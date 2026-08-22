import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/media/rating_controller.dart';
import '../../application/player/external_player_coordinator.dart';
import '../../application/player/player_controller.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../data/services/video_frame_service.dart';
import '../../domain/models/media_item.dart';
import '../common/keep_vault_unlocked.dart';
import 'video_player_controls.dart';
import 'video_player_surface.dart';

typedef VideoFileProbe = Future<bool> Function(String path);

Future<bool> _probeVideoFile(String path) => File(path).exists();

/// Playlist player (built-in slideshow + video, external hand-off for VLC).
/// See docs/02-design/screens/05-player.md.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.items,
    this.shuffle,
    this.startItemId,
    this.title = 'Playing',
    this.videoFileProbe = _probeVideoFile,
  });

  final List<MediaItem> items;
  final bool? shuffle;
  final String? startItemId;
  final String title;
  final VideoFileProbe videoFileProbe;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _video;
  String? _videoItemId;
  VideoPlayerController? _nextVideo;
  String? _nextVideoId;
  Future<void> _videoOperations = Future<void>.value();
  int _videoRequest = 0;
  int _preloadRequest = 0;
  String? _requestedVideoItemId;
  bool? _requestedVideoPlaying;
  String? _videoError;
  String? _videoErrorItemId;
  String? _completedForId;
  bool _chrome = true;
  bool _programmaticPopAllowed = false;
  VideoFitMode _fitMode = VideoFitMode.fit;
  double _playbackSpeed = 1;
  bool _muted = false;
  bool? _lastImmersive;
  String? _orientationLockedItemId;
  bool _orientationOverridden = false;
  final Map<String, int> _ratingOverrides = {};

  @override
  void initState() {
    super.initState();
    _playbackSpeed = ref.read(settingsControllerProvider).playerPlaybackSpeed;
    unawaited(VideoSystemUi.apply(false));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerControllerProvider.notifier).start(
            items: widget.items,
            shuffle: widget.shuffle,
            startItemId: widget.startItemId,
          );
    });
  }

  @override
  void dispose() {
    _videoRequest++;
    _preloadRequest++;
    final c = _video;
    _video = null;
    _videoItemId = null;
    _completedForId = null;
    if (c != null) {
      unawaited(_disposeController(c));
    }
    final n = _nextVideo;
    _nextVideo = null;
    _nextVideoId = null;
    if (n != null) {
      unawaited(_disposeController(n));
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
    _orientationOverridden = true;
    await VideoSystemUi.toggle(_isLandscape(context));
  }

  void _maybeLockOrientationToVideo() {
    final video = _video;
    final itemId = _videoItemId;
    if (video == null || itemId == null || !video.value.isInitialized) return;
    if (_orientationLockedItemId == itemId) return;
    _orientationLockedItemId = itemId;
    _orientationOverridden = false;
    unawaited(VideoSystemUi.lockToVideoSize(video.value.size));
  }

  void _clearOrientationLock() {
    if (_orientationLockedItemId == null && !_orientationOverridden) return;
    _orientationLockedItemId = null;
    _orientationOverridden = false;
    unawaited(VideoSystemUi.unlockOrientations());
  }

  int _ratingFor(MediaItem item) => _ratingOverrides[item.id] ?? item.rating;

  void _setRating(MediaItem item, int rating) {
    unawaited(
      ref.read(ratingControllerProvider.notifier).setRating(item.id, rating),
    );
    setState(() => _ratingOverrides[item.id] = rating);
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

  Future<void> _seekTo(Duration position) async {
    final video = _video;
    if (video != null) await video.seekTo(position);
  }

  Future<void> _openSettings(PlayerUiState ui) async {
    final settings = ref.read(settingsControllerProvider);
    final item = ui.current;
    await showVideoSettingsSheet(
      context,
      seekSeconds: settings.playerSeekSeconds,
      onSeekSecondsChanged: (seconds) => unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setPlayerSeekSeconds(seconds),
      ),
      playbackSpeed: _playbackSpeed,
      onPlaybackSpeedChanged: _setPlaybackSpeed,
      muted: _muted,
      onMutedChanged: _setMuted,
      shuffle: ui.playlist?.shuffle,
      onShuffleChanged: (value) {
        if (value != ref.read(playerControllerProvider).playlist?.shuffle) {
          ref.read(playerControllerProvider.notifier).toggleShuffle();
        }
      },
      rating: item == null ? null : _ratingFor(item),
      onRatingChanged:
          item == null ? null : (rating) => _setRating(item, rating),
    );
  }

  Future<void> _configureVideo(
    VideoPlayerController controller, {
    required bool playing,
  }) async {
    await controller.setLooping(false);
    await controller.setVolume(_muted ? 0 : 1);
    if (playing) {
      await controller.play();
      await controller.setPlaybackSpeed(_playbackSpeed);
    } else {
      await controller.setPlaybackSpeed(_playbackSpeed);
    }
  }

  Future<void> _enqueueVideoOperation(Future<void> Function() operation) {
    final scheduled = _videoOperations.then((_) => operation());
    _videoOperations = scheduled.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'Privi video playback',
          ),
        );
      },
    );
    return _videoOperations;
  }

  void _requestVideoSync(MediaItem? item, bool playing) {
    _requestedVideoItemId = item?.id;
    _requestedVideoPlaying = playing;
    final request = ++_videoRequest;
    _preloadRequest++;
    unawaited(_enqueueVideoOperation(() => _syncVideo(request, item, playing)));
  }

  void _ensureVideoSync(MediaItem item, bool playing) {
    if (_requestedVideoItemId == item.id && _requestedVideoPlaying == playing) {
      return;
    }
    _requestVideoSync(item, playing);
  }

  bool _isCurrentVideoRequest(int request, String? itemId) {
    if (!mounted || request != _videoRequest) return false;
    return ref.read(playerControllerProvider).current?.id == itemId;
  }

  bool _isCurrentPreloadRequest(
    int request, {
    required String currentItemId,
    required String nextItemId,
  }) {
    if (!mounted || request != _preloadRequest) return false;
    final playlist = ref.read(playerControllerProvider).playlist;
    return playlist?.current?.id == currentItemId &&
        playlist?.peekNext()?.id == nextItemId;
  }

  void _clearVideoError() {
    if (_videoError == null && _videoErrorItemId == null) return;
    setState(() {
      _videoError = null;
      _videoErrorItemId = null;
    });
  }

  void _showVideoError(
    int request,
    String itemId,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('video playback failed for $itemId: $error\n$stackTrace');
    if (!_isCurrentVideoRequest(request, itemId)) return;
    setState(() {
      _videoError = error.toString();
      _videoErrorItemId = itemId;
    });
  }

  Future<void> _syncVideo(int request, MediaItem? item, bool playing) async {
    final itemId = item?.id;
    if (!_isCurrentVideoRequest(request, itemId)) return;
    _clearVideoError();

    if (item == null || !item.isVideo) {
      await _disposeVideo();
      if (!_isCurrentVideoRequest(request, itemId)) return;
      await _disposeNextVideo();
      _clearOrientationLock();
      return;
    }
    final external = ref.read(settingsControllerProvider).playerExternal &&
        ref.read(externalPlayerCoordinatorProvider).supported;
    if (external) {
      await _disposeVideo();
      if (!_isCurrentVideoRequest(request, itemId)) return;
      await _disposeNextVideo();
      return;
    }
    if (_videoItemId == item.id && _video != null) {
      final currentVideo = _video!;
      try {
        if (playing && !currentVideo.value.isPlaying) {
          if (_completedForId == item.id) {
            _completedForId = null;
            await currentVideo.seekTo(Duration.zero);
          }
          await currentVideo.play();
          await currentVideo.setPlaybackSpeed(_playbackSpeed);
        } else if (!playing && currentVideo.value.isPlaying) {
          await currentVideo.pause();
        }
      } catch (error, stackTrace) {
        _showVideoError(request, item.id, error, stackTrace);
        return;
      }
      if (_isCurrentVideoRequest(request, item.id)) _schedulePreload();
      return;
    }

    // Promote preloaded controller for seamless advance (shuffle / next).
    if (_nextVideoId == item.id && _nextVideo != null) {
      final previous = _video;
      final candidate = _nextVideo!;
      _nextVideo = null;
      _nextVideoId = null;
      _completedForId = null;
      try {
        if (playing) await candidate.seekTo(Duration.zero);
        if (!_isCurrentVideoRequest(request, item.id)) {
          await _disposeController(candidate);
          return;
        }
        await _configureVideo(candidate, playing: playing);
      } catch (error, stackTrace) {
        await _disposeController(candidate);
        _showVideoError(request, item.id, error, stackTrace);
        return;
      }
      if (!_isCurrentVideoRequest(request, item.id)) {
        await _disposeController(candidate);
        return;
      }
      candidate.addListener(() {
        if (!mounted) return;
        _maybeAdvanceOnVideoEnd(candidate, item.id);
      });
      setState(() {
        _video = candidate;
        _videoItemId = item.id;
      });
      if (previous != null) await _disposeController(previous);
      if (_isCurrentVideoRequest(request, item.id)) _schedulePreload();
      return;
    }

    await _disposeNextVideo();
    if (!_isCurrentVideoRequest(request, item.id)) return;
    await _disposeVideo();
    if (!_isCurrentVideoRequest(request, item.id)) return;
    final file = File(item.privatePath);
    if (!await widget.videoFileProbe(item.privatePath)) {
      _showVideoError(
        request,
        item.id,
        StateError('Video file does not exist: ${item.privatePath}'),
        StackTrace.current,
      );
      return;
    }
    if (!_isCurrentVideoRequest(request, item.id)) return;

    final candidate = VideoPlayerController.file(file);
    try {
      await candidate.initialize();
      if (!_isCurrentVideoRequest(request, item.id)) {
        await _disposeController(candidate);
        return;
      }
      await _configureVideo(candidate, playing: playing);
    } catch (error, stackTrace) {
      await _disposeController(candidate);
      _showVideoError(request, item.id, error, stackTrace);
      return;
    }
    if (!_isCurrentVideoRequest(request, item.id)) {
      await _disposeController(candidate);
      return;
    }
    candidate.addListener(() {
      if (!mounted) return;
      _maybeAdvanceOnVideoEnd(candidate, item.id);
    });
    setState(() {
      _video = candidate;
      _videoItemId = item.id;
    });
    _schedulePreload();
  }

  Future<void> _disposeController(VideoPlayerController controller) async {
    try {
      await controller.pause();
    } catch (error, stackTrace) {
      debugPrint('pause video during disposal failed: $error\n$stackTrace');
    }
    try {
      await controller.dispose();
    } catch (error, stackTrace) {
      debugPrint('dispose video failed: $error\n$stackTrace');
    }
  }

  Future<void> _disposeVideo() async {
    final c = _video;
    _video = null;
    _videoItemId = null;
    _completedForId = null;
    if (c != null) await _disposeController(c);
  }

  Future<void> _disposeNextVideo() async {
    final c = _nextVideo;
    _nextVideo = null;
    _nextVideoId = null;
    if (c != null) await _disposeController(c);
  }

  void _schedulePreload() {
    final request = ++_preloadRequest;
    unawaited(_enqueueVideoOperation(() => _preloadNext(request)));
  }

  /// Warm the next playlist video so shuffle advances with less black-screen gap.
  Future<void> _preloadNext(int request) async {
    if (!mounted || request != _preloadRequest) return;
    final ui = ref.read(playerControllerProvider);
    final pl = ui.playlist;
    final currentItemId = pl?.current?.id;
    if (pl == null || !pl.hasNext) {
      await _disposeNextVideo();
      return;
    }
    final nextItem = pl.peekNext();
    if (nextItem == null || !nextItem.isVideo) {
      await _disposeNextVideo();
      return;
    }
    if (currentItemId == null) return;
    if (_nextVideoId == nextItem.id && _nextVideo != null) return;

    await _disposeNextVideo();
    if (!_isCurrentPreloadRequest(
      request,
      currentItemId: currentItemId,
      nextItemId: nextItem.id,
    )) {
      return;
    }
    final external = ref.read(settingsControllerProvider).playerExternal &&
        ref.read(externalPlayerCoordinatorProvider).supported;
    if (external) return;

    final file = File(nextItem.privatePath);
    if (!await widget.videoFileProbe(nextItem.privatePath)) return;
    if (!_isCurrentPreloadRequest(
      request,
      currentItemId: currentItemId,
      nextItemId: nextItem.id,
    )) {
      return;
    }
    final candidate = VideoPlayerController.file(file);
    try {
      await candidate.initialize();
      if (!_isCurrentPreloadRequest(
        request,
        currentItemId: currentItemId,
        nextItemId: nextItem.id,
      )) {
        await _disposeController(candidate);
        return;
      }
      await candidate.pause();
      await candidate.setVolume(_muted ? 0 : 1);
      await candidate.setPlaybackSpeed(_playbackSpeed);
      if (!_isCurrentPreloadRequest(
        request,
        currentItemId: currentItemId,
        nextItemId: nextItem.id,
      )) {
        await _disposeController(candidate);
        return;
      }
      _nextVideo = candidate;
      _nextVideoId = nextItem.id;
    } catch (error, stackTrace) {
      await _disposeController(candidate);
      debugPrint(
        'preload next video failed for ${nextItem.id}: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _cancelVideoOperationsAndDispose() {
    _videoRequest++;
    _preloadRequest++;
    return _enqueueVideoOperation(() async {
      await _disposeVideo();
      await _disposeNextVideo();
    });
  }

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  void _hideChrome() {
    if (_chrome) setState(() => _chrome = false);
  }

  void _maybeAdvanceOnVideoEnd(VideoPlayerController c, String itemId) {
    if (!mounted) return;
    if (!ref.read(playerControllerProvider).playing) return;
    if (_completedForId == itemId) return;
    if (!videoPlaybackEnded(c.value)) return;
    _completedForId = itemId;
    // ignore: discarded_futures
    ref.read(playerControllerProvider.notifier).onItemCompleted();
  }

  void _exitPlayer() {
    ref.read(playerControllerProvider.notifier).stop();
    if (!mounted) return;
    setState(() {
      _chrome = false;
      _programmaticPopAllowed = true;
    });
    // PopScope's canPop value is updated by the rebuild above. Wait for that
    // frame before issuing the programmatic pop from the visible back button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerControllerProvider);
    final item = ui.current;
    final pl = ui.playlist;
    final landscape = _isLandscape(context);
    final builtInVideo = item?.isVideo == true &&
        _video != null &&
        _videoItemId == item?.id &&
        _video!.value.isInitialized;
    final immersive = landscape && builtInVideo;
    _syncSystemUi(immersive);
    if (builtInVideo) {
      _maybeLockOrientationToVideo();
    }

    // Keep video engine in sync with playlist cursor.
    ref.listen(playerControllerProvider, (prev, next) {
      _requestVideoSync(next.current, next.playing);
    });
    if (item?.isVideo == true &&
        _videoItemId != item?.id &&
        _videoErrorItemId != item?.id) {
      _ensureVideoSync(item!, ui.playing);
    }

    return KeepVaultUnlocked(
      child: PopScope(
        canPop: item?.isVideo == true || !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          ref.read(playerControllerProvider.notifier).stop();
          await _cancelVideoOperationsAndDispose();
        },
        child: AutoHideVideoControls(
          enabled: item?.isVideo == true,
          visible: _chrome,
          onHide: _hideChrome,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (item == null)
                  Center(
                    child: Text(
                      context.l10n.emptyPlaylist,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                else if (item.isVideo)
                  _buildVideo(item, ui)
                else
                  _buildImage(item),
                if (_chrome)
                  _topBar(ui, pl?.positionDisplay ?? 0, pl?.length ?? 0),
                if (_chrome && builtInVideo)
                  _videoBottomBar(ui, landscape)
                else if (_chrome)
                  _bottomBar(ui, landscape),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(MediaItem item) {
    final file = File(item.privatePath);
    if (!file.existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
      );
    }
    return GestureDetector(
      onTap: _toggleChrome,
      child: InteractiveViewer(
        child: Center(child: Image.file(file, fit: BoxFit.contain)),
      ),
    );
  }

  Widget _buildVideo(MediaItem item, PlayerUiState ui) {
    if (ui.externalHandedOff) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              context.l10n.openedExternalPlayer,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(playerControllerProvider.notifier).next(),
              child: Text(context.l10n.next),
            ),
          ],
        ),
      );
    }
    if (_videoErrorItemId == item.id && _videoError != null) {
      return GestureDetector(
        onTap: _toggleChrome,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white54,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.errorWithDetails(_videoError!),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    _clearVideoError();
                    _requestVideoSync(item, ui.playing);
                  },
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final c = _video;
    if (c == null || _videoItemId != item.id || !c.value.isInitialized) {
      return GestureDetector(
        onTap: _toggleChrome,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    return VideoGestureSurface(
      controller: c,
      seekSeconds: ref.watch(settingsControllerProvider).playerSeekSeconds,
      onTap: _toggleChrome,
      onPreviewFrameRequested: (position) => VideoFrameService().frameAtTime(
        path: item.privatePath,
        position: position,
      ),
      child: VideoViewport(controller: c, fitMode: _fitMode),
    );
  }

  Widget _topBar(PlayerUiState ui, int pos, int total) {
    final title = ui.current?.originalName ?? widget.title;
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
                  onPressed: _exitPlayer,
                ),
                Expanded(
                  child: Text(
                    '$title · $pos/$total',
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(PlayerUiState ui, bool landscape) {
    final pl = ui.playlist;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      tooltip: context.l10n.previousMedia,
                      onPressed: pl?.hasPrev == true
                          ? () =>
                              ref.read(playerControllerProvider.notifier).prev()
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      iconSize: 44,
                      color: Colors.white,
                      tooltip:
                          ui.playing ? context.l10n.pause : context.l10n.play,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .togglePlayPause(),
                      icon: Icon(
                        ui.playing ? Icons.pause_circle : Icons.play_circle,
                      ),
                    ),
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      tooltip: context.l10n.nextMedia,
                      onPressed: pl?.hasNext == true
                          ? () =>
                              ref.read(playerControllerProvider.notifier).next()
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                    IconButton(
                      iconSize: 28,
                      color: pl?.shuffle == true
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                      tooltip: context.l10n.shuffle,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleShuffle(),
                      icon: const Icon(Icons.shuffle),
                    ),
                    IconButton(
                      iconSize: 28,
                      color: Colors.white,
                      tooltip: landscape
                          ? context.l10n.portrait
                          : context.l10n.landscape,
                      onPressed: () => unawaited(_toggleOrientation(context)),
                      icon: Icon(
                        landscape
                            ? Icons.stay_current_portrait
                            : Icons.stay_current_landscape,
                      ),
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

  Widget _videoBottomBar(PlayerUiState ui, bool landscape) {
    final video = _video;
    final playlist = ui.playlist;
    final item = ui.current;
    if (video == null || !video.value.isInitialized) {
      return const SizedBox.shrink();
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
            hasPrevious: playlist?.hasPrev == true,
            hasNext: playlist?.hasNext == true,
            onPrevious: () =>
                unawaited(ref.read(playerControllerProvider.notifier).prev()),
            onSeek: _seekTo,
            onPlayPause: () =>
                ref.read(playerControllerProvider.notifier).togglePlayPause(),
            onNext: () =>
                unawaited(ref.read(playerControllerProvider.notifier).next()),
            onToggleOrientation: () => unawaited(_toggleOrientation(context)),
            onChooseFit: () => unawaited(_chooseFit()),
            onOpenSettings: () => unawaited(_openSettings(ui)),
            onPreviewFrameRequested: item == null
                ? null
                : (position) => VideoFrameService().frameAtTime(
                      path: item.privatePath,
                      position: position,
                    ),
          );
        },
      ),
    );
  }
}
