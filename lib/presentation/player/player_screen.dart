import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/external_player_coordinator.dart';
import '../../application/player/player_controller.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../domain/models/media_item.dart';
import '../common/keep_vault_unlocked.dart';
import 'video_player_controls.dart';
import 'video_player_surface.dart';

/// Playlist player (built-in slideshow + video, external hand-off for VLC).
/// See docs/02-design/screens/05-player.md.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.items,
    this.shuffle,
    this.startItemId,
    this.title = 'Playing',
  });

  final List<MediaItem> items;
  final bool? shuffle;
  final String? startItemId;
  final String title;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _video;
  String? _videoItemId;
  VideoPlayerController? _nextVideo;
  String? _nextVideoId;
  String? _completedForId;
  bool _chrome = true;
  bool _programmaticPopAllowed = false;
  VideoFitMode _fitMode = VideoFitMode.fit;
  double _playbackSpeed = 1;
  bool _muted = false;
  bool? _lastImmersive;

  @override
  void initState() {
    super.initState();
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
    final c = _video;
    _video = null;
    _videoItemId = null;
    _completedForId = null;
    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
      // ignore: discarded_futures
      c.dispose();
    }
    final n = _nextVideo;
    _nextVideo = null;
    _nextVideoId = null;
    if (n != null) {
      try {
        n.pause();
      } catch (_) {}
      // ignore: discarded_futures
      n.dispose();
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
    final selected = await showVideoFitModeSheet(
      context,
      current: _fitMode,
    );
    if (selected != null && mounted) setState(() => _fitMode = selected);
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

  void _seekTo(Duration position) {
    final video = _video;
    if (video != null) unawaited(video.seekTo(position));
  }

  Future<void> _openSettings(PlayerUiState ui) async {
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
      shuffle: ui.playlist?.shuffle,
      onShuffleChanged: (value) {
        if (value != ref.read(playerControllerProvider).playlist?.shuffle) {
          ref.read(playerControllerProvider.notifier).toggleShuffle();
        }
      },
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

  Future<void> _syncVideo(MediaItem? item, bool playing) async {
    if (item == null || !item.isVideo) {
      await _disposeVideo();
      await _disposeNextVideo();
      return;
    }
    final external = ref.read(settingsControllerProvider).playerExternal &&
        ref.read(externalPlayerCoordinatorProvider).supported;
    if (external) {
      await _disposeVideo();
      await _disposeNextVideo();
      return;
    }
    if (_videoItemId == item.id && _video != null) {
      if (playing && !_video!.value.isPlaying) {
        if (_completedForId == item.id) {
          _completedForId = null;
          await _video!.seekTo(Duration.zero);
        }
        await _video!.play();
        await _video!.setPlaybackSpeed(_playbackSpeed);
      } else if (!playing && _video!.value.isPlaying) {
        await _video!.pause();
      }
      // Keep warm next item while current plays.
      unawaited(_preloadNext());
      return;
    }

    // Promote preloaded controller for seamless advance (shuffle / next).
    if (_nextVideoId == item.id && _nextVideo != null) {
      final prev = _video;
      final c = _nextVideo!;
      _nextVideo = null;
      _nextVideoId = null;
      _completedForId = null;
      final itemId = item.id;
      c.addListener(() {
        if (!mounted) return;
        _maybeAdvanceOnVideoEnd(c, itemId);
      });
      if (playing) {
        try {
          await c.seekTo(Duration.zero);
        } catch (_) {}
      }
      await _configureVideo(c, playing: playing);
      if (!mounted) {
        await c.dispose();
        await prev?.dispose();
        return;
      }
      setState(() {
        _video = c;
        _videoItemId = item.id;
      });
      if (prev != null) {
        try {
          await prev.pause();
        } catch (_) {}
        try {
          await prev.dispose();
        } catch (_) {}
      }
      unawaited(_preloadNext());
      return;
    }

    await _disposeVideo();
    final file = File(item.privatePath);
    if (!await file.exists()) return;
    final c = VideoPlayerController.file(file);
    await c.initialize();
    final itemId = item.id;
    c.addListener(() {
      if (!mounted) return;
      _maybeAdvanceOnVideoEnd(c, itemId);
    });
    await _configureVideo(c, playing: playing);
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _video = c;
      _videoItemId = item.id;
    });
    unawaited(_preloadNext());
  }

  Future<void> _disposeVideo() async {
    final c = _video;
    _video = null;
    _videoItemId = null;
    _completedForId = null;
    if (c != null) {
      try {
        await c.pause();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  Future<void> _disposeNextVideo() async {
    final c = _nextVideo;
    _nextVideo = null;
    _nextVideoId = null;
    if (c != null) {
      try {
        await c.pause();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  /// Warm the next playlist video so shuffle advances with less black-screen gap.
  Future<void> _preloadNext() async {
    final ui = ref.read(playerControllerProvider);
    final pl = ui.playlist;
    if (pl == null || !pl.hasNext) {
      await _disposeNextVideo();
      return;
    }
    final nextItem = pl.peekNext();
    if (nextItem == null || !nextItem.isVideo) {
      await _disposeNextVideo();
      return;
    }
    if (_nextVideoId == nextItem.id && _nextVideo != null) return;

    await _disposeNextVideo();
    final external = ref.read(settingsControllerProvider).playerExternal &&
        ref.read(externalPlayerCoordinatorProvider).supported;
    if (external) return;

    final file = File(nextItem.privatePath);
    if (!await file.exists()) return;
    try {
      final c = VideoPlayerController.file(file);
      await c.initialize();
      await c.pause();
      await c.setVolume(_muted ? 0 : 1);
      await c.setPlaybackSpeed(_playbackSpeed);
      if (!mounted) {
        await c.dispose();
        return;
      }
      // Don't call setState during dispose races — only if still mounted.
      _nextVideo = c;
      _nextVideoId = nextItem.id;
    } catch (e) {
      debugPrint('preload next: $e');
    }
  }

  void _maybeAdvanceOnVideoEnd(VideoPlayerController c, String itemId) {
    if (!mounted) return;
    if (!ref.read(playerControllerProvider).playing) return;
    if (_completedForId == itemId) return;
    if (!c.value.isInitialized) return;
    final dur = c.value.duration;
    final pos = c.value.position;
    if (dur <= Duration.zero) return;
    // isCompleted is flaky on some devices; also treat near-end as finished.
    final ended =
        c.value.isCompleted || pos >= dur - const Duration(milliseconds: 350);
    if (!ended) return;
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

    // Keep video engine in sync with playlist cursor.
    ref.listen(playerControllerProvider, (prev, next) {
      unawaited(_syncVideo(next.current, next.playing));
    });

    // Initial sync.
    if (item != null && item.isVideo && _videoItemId != item.id) {
      unawaited(_syncVideo(item, ui.playing));
    }

    return KeepVaultUnlocked(
      child: PopScope(
        canPop: !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          ref.read(playerControllerProvider.notifier).stop();
          await _disposeVideo();
          await _disposeNextVideo();
        },
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
              if (_chrome && !immersive)
                _topBar(ui, pl?.positionDisplay ?? 0, pl?.length ?? 0),
              if (_chrome && builtInVideo)
                _videoBottomBar(ui, landscape)
              else if (_chrome)
                _bottomBar(ui, landscape),
            ],
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
      onTap: () => setState(() => _chrome = !_chrome),
      child: InteractiveViewer(
        child: Center(
          child: Image.file(file, fit: BoxFit.contain),
        ),
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
    final c = _video;
    if (c == null || !c.value.isInitialized) {
      return GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    return VideoGestureSurface(
      controller: c,
      seekSeconds: ref.watch(settingsControllerProvider).playerSeekSeconds,
      onTap: () => setState(() => _chrome = !_chrome),
      child: VideoViewport(
        controller: c,
        fitMode: _fitMode,
      ),
    );
  }

  Widget _topBar(PlayerUiState ui, int pos, int total) {
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
                    '${widget.title} · $pos/$total',
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
            onPrevious: () => unawaited(
              ref.read(playerControllerProvider.notifier).prev(),
            ),
            onSeek: _seekTo,
            onPlayPause: () =>
                ref.read(playerControllerProvider.notifier).togglePlayPause(),
            onNext: () => unawaited(
              ref.read(playerControllerProvider.notifier).next(),
            ),
            onToggleOrientation: () => unawaited(_toggleOrientation(context)),
            onChooseFit: () => unawaited(_chooseFit()),
            onOpenSettings: () => unawaited(_openSettings(ui)),
          );
        },
      ),
    );
  }
}
