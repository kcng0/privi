import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/gallery/gallery_controller.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/media/rating_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';
import '../../data/services/intent_service.dart';
import '../../domain/models/media_item.dart';
import '../common/heart_rating_bar.dart';
import '../common/keep_vault_unlocked.dart';

/// Fullscreen swipe viewer with zoom, video, rating, unhide.
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<MediaItem> items;
  final int initialIndex;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final PageController _page;
  late int _index;
  bool _chrome = true;
  VideoPlayerController? _video;
  String? _videoId;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _page = PageController(initialPage: _index);
    // Keep status + navigation bars visible (no immersive fullscreen).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVideo());
  }

  @override
  void dispose() {
    // Pause first so audio cannot keep playing after the route is gone.
    final c = _video;
    _video = null;
    _videoId = null;
    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
      // Fire-and-forget dispose; controller is detached from UI.
      // ignore: discarded_futures
      c.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _page.dispose();
    super.dispose();
  }

  MediaItem get _current => widget.items[_index];

  Future<void> _syncVideo() async {
    final item = _current;
    if (!item.isVideo) {
      await _disposeVideo();
      return;
    }
    if (_videoId == item.id && _video != null) return;
    await _disposeVideo();
    final file = File(item.privatePath);
    if (!await file.exists()) return;
    final c = VideoPlayerController.file(file);
    await c.initialize();
    await c.setLooping(true);
    await c.play();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _video = c;
      _videoId = item.id;
    });
  }

  Future<void> _disposeVideo() async {
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

  Future<void> _close() async {
    await _disposeVideo();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openExternal() async {
    final item = _current;
    // Stay unlocked while VLC/system player is open; release on resume.
    ref.read(lockControllerProvider.notifier).suppressAutoLockUntilResumed();
    await IntentService().openExternal(
      filePath: item.privatePath,
      mimeType: item.mimeType,
    );
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
    final gallery = ref.read(galleryServiceProvider);
    gallery.invalidateVaultPathCache();
    gallery.refreshAfterMutation();
    ref.read(galleryUiEpochProvider.notifier).bump();
    ref.invalidate(galleryFoldersProvider);
    setState(() {
      widget.items.removeAt(_index);
      if (widget.items.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_index >= widget.items.length) _index = widget.items.length - 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.restoredToGallery)),
    );
    await _syncVideo();
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    final vc = context.vaultColors;
    final externalPref = ref.watch(settingsControllerProvider).playerExternal;

    return KeepVaultUnlocked(
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) async {
          // Always stop playback when leaving (system back or Navigator.pop).
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
                onPageChanged: (i) async {
                  setState(() => _index = i);
                  await _syncVideo();
                },
                itemBuilder: (context, i) {
                  final m = widget.items[i];
                  final file = File(m.privatePath);
                  return GestureDetector(
                    onTap: () => setState(() => _chrome = !_chrome),
                    child: Center(
                      child: !file.existsSync()
                          ? const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 64,
                            )
                          : m.isVideo
                              ? _videoPage(m, i == _index)
                              : InteractiveViewer(
                                  child: Hero(
                                    tag: 'media-hero-${m.id}',
                                    child:
                                        Image.file(file, fit: BoxFit.contain),
                                  ),
                                ),
                    ),
                  );
                },
              ),
              AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    child: Material(
                      color: Colors.black54,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: () => unawaited(_close()),
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
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            if (item.isVideo)
                              IconButton(
                                tooltip: context.l10n.openExternal,
                                icon: const Icon(
                                  Icons.open_in_new,
                                  color: Colors.white70,
                                ),
                                onPressed: _openExternal,
                              ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white70,
                              ),
                              onSelected: (v) {
                                if (v == 'unhide') unawaited(_unhide());
                                if (v == 'external') unawaited(_openExternal());
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'unhide',
                                  child:
                                      Text(context.l10n.unhideRestoreOriginal),
                                ),
                                if (item.isVideo)
                                  PopupMenuItem(
                                    value: 'external',
                                    child: Text(context.l10n.openExternal),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Container(
                      width: double.infinity,
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.isVideo &&
                              _video != null &&
                              _video!.value.isInitialized &&
                              !externalPref)
                            VideoProgressIndicator(
                              _video!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFF5ECFBA),
                              ),
                            ),
                          HeartRatingBar(
                            rating: item.rating,
                            size: 28,
                            interactive: true,
                            scrim: false,
                            onRate: (n) {
                              ref
                                  .read(ratingControllerProvider.notifier)
                                  .setRating(item.id, n);
                              setState(() {
                                widget.items[_index] = item.copyWith(rating: n);
                              });
                            },
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                tooltip: context.l10n.favoriteToggle,
                                icon: Icon(Icons.favorite, color: vc.heart),
                                onPressed: () {
                                  final n = item.rating >= 1 ? 0 : 1;
                                  ref
                                      .read(ratingControllerProvider.notifier)
                                      .setRating(item.id, n);
                                  setState(() {
                                    widget.items[_index] =
                                        item.copyWith(rating: n);
                                  });
                                },
                              ),
                              if (item.isVideo &&
                                  _video != null &&
                                  _video!.value.isInitialized)
                                IconButton(
                                  icon: Icon(
                                    _video!.value.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (_video!.value.isPlaying) {
                                        _video!.pause();
                                      } else {
                                        _video!.play();
                                      }
                                    });
                                  },
                                ),
                              IconButton(
                                tooltip: context.l10n.delete,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white70,
                                ),
                                onPressed: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final nav = Navigator.of(context);
                                  final recycleMsg =
                                      context.l10n.moveToRecycleBin;
                                  await ref
                                      .read(mediaRepositoryProvider)
                                      .softDelete(item.id);
                                  if (!mounted) return;
                                  if (widget.items.length <= 1) {
                                    nav.pop();
                                    return;
                                  }
                                  setState(() {
                                    widget.items.removeAt(_index);
                                    if (_index >= widget.items.length) {
                                      _index = widget.items.length - 1;
                                    }
                                  });
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(recycleMsg)),
                                  );
                                  await _syncVideo();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoPage(MediaItem m, bool active) {
    if (!active || _video == null || !_video!.value.isInitialized) {
      final thumb = m.thumbnailPath;
      if (thumb != null && File(thumb).existsSync()) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Image.file(File(thumb), fit: BoxFit.contain),
            const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
          ],
        );
      }
      return const Icon(Icons.videocam, size: 72, color: Colors.white54);
    }
    return AspectRatio(
      aspectRatio:
          _video!.value.aspectRatio == 0 ? 16 / 9 : _video!.value.aspectRatio,
      child: VideoPlayer(_video!),
    );
  }
}
