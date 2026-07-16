import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../common/keep_vault_unlocked.dart';

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

  @override
  void initState() {
    super.initState();
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
        await c.setLooping(true);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeepVaultUnlocked(
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) async {
          await _stopVideo();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black87,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final nav = Navigator.of(context);
                await _stopVideo();
                if (!mounted) return;
                nav.pop();
              },
            ),
            title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          ),
          body: Center(
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white54)
                : _error != null
                    ? Text(_error!,
                        style: const TextStyle(color: Colors.white70))
                    : widget.isVideo &&
                            _video != null &&
                            _video!.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: _video!.value.aspectRatio == 0
                                ? 16 / 9
                                : _video!.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_video!),
                                Positioned(
                                  bottom: 24,
                                  child: IconButton(
                                    iconSize: 48,
                                    color: Colors.white,
                                    icon: Icon(
                                      _video!.value.isPlaying
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
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
                                ),
                              ],
                            ),
                          )
                        : _file != null
                            ? InteractiveViewer(
                                child: Image.file(_file!, fit: BoxFit.contain),
                              )
                            : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
