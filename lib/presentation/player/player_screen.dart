import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/external_player_coordinator.dart';
import '../../application/player/player_controller.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../domain/models/media_item.dart';
import '../common/keep_vault_unlocked.dart';

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

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  String? _videoItemId;
  VideoPlayerController? _nextVideo;
  String? _nextVideoId;
  String? _completedForId;
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep status + navigation bars visible (no immersive fullscreen).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerControllerProvider.notifier).start(
            items: widget.items,
            shuffle: widget.shuffle,
            startItemId: widget.startItemId,
          );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After external player (VLC etc.), auto-advance when user returns.
    if (state == AppLifecycleState.resumed) {
      final ui = ref.read(playerControllerProvider);
      if (ui.externalHandedOff) {
        // ignore: discarded_futures
        ref.read(playerControllerProvider.notifier).onItemCompleted();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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
        await _video!.play();
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
        setState(() {});
        _maybeAdvanceOnVideoEnd(c, itemId);
      });
      if (playing) {
        try {
          await c.seekTo(Duration.zero);
        } catch (_) {}
        await c.play();
      }
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
    await c.setLooping(false);
    final itemId = item.id;
    c.addListener(() {
      if (!mounted) return;
      setState(() {});
      _maybeAdvanceOnVideoEnd(c, itemId);
    });
    if (playing) await c.play();
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
      await c.setLooping(false);
      await c.pause();
      if (!mounted) {
        await c.dispose();
        return;
      }
      // Don't call setState during dispose races — only if still mounted.
      _nextVideo = c;
      _nextVideoId = nextItem.id;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('preload next: $e');
    }
  }

  void _maybeAdvanceOnVideoEnd(VideoPlayerController c, String itemId) {
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerControllerProvider);
    final item = ui.current;
    final pl = ui.playlist;

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
        canPop: true,
        onPopInvokedWithResult: (didPop, _) async {
          await _disposeVideo();
          await _disposeNextVideo();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => setState(() => _chrome = !_chrome),
            child: Stack(
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
                if (_chrome) _bottomBar(ui),
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
    return InteractiveViewer(
      child: Center(
        child: Image.file(file, fit: BoxFit.contain),
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
            const Text(
              'Opened in external player',
              style: TextStyle(color: Colors.white70),
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
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: VideoPlayer(c),
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
                  onPressed: () async {
                    ref.read(playerControllerProvider.notifier).stop();
                    await _disposeVideo();
                    if (mounted) Navigator.pop(context);
                  },
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

  Widget _bottomBar(PlayerUiState ui) {
    final pl = ui.playlist;
    final video = _video;
    final showSeek = video != null && video.value.isInitialized;

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
                if (showSeek)
                  Row(
                    children: [
                      Expanded(
                        child: VideoProgressIndicator(
                          video,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: Theme.of(context).colorScheme.primary,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      onPressed: pl?.hasPrev == true
                          ? () =>
                              ref.read(playerControllerProvider.notifier).prev()
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      iconSize: 44,
                      color: Colors.white,
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
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleShuffle(),
                      icon: const Icon(Icons.shuffle),
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
