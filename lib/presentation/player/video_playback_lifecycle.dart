import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/picture_in_picture_controller.dart';

/// Registers only the visible video, never a playlist preload. Controllers must
/// use allowBackgroundPlayback:true; this binding owns pause/grant decisions.
class VideoPlaybackLifecycle extends ConsumerStatefulWidget {
  const VideoPlaybackLifecycle({
    super.key,
    required this.controller,
    required this.mediaId,
    required this.child,
  });

  final VideoPlayerController controller;
  final String mediaId;
  final Widget child;

  @override
  ConsumerState<VideoPlaybackLifecycle> createState() =>
      _VideoPlaybackLifecycleState();
}

class _VideoPlaybackLifecycleState
    extends ConsumerState<VideoPlaybackLifecycle> {
  late PictureInPictureController _pip;

  @override
  void initState() {
    super.initState();
    _pip = ref.read(pictureInPictureControllerProvider.notifier);
    _scheduleBinding();
  }

  @override
  void didUpdateWidget(VideoPlaybackLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) ||
        widget.mediaId != oldWidget.mediaId) {
      _scheduleBinding();
    }
  }

  void _scheduleBinding() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pip.bind(
        owner: this,
        mediaId: widget.mediaId,
        controller: widget.controller,
        sourceRect: () {
          final box = context.findRenderObject();
          if (box is! RenderBox || !box.hasSize) return null;
          final ratio = View.of(context).devicePixelRatio;
          final origin = box.localToGlobal(Offset.zero);
          return Rect.fromLTWH(
            origin.dx * ratio,
            origin.dy * ratio,
            box.size.width * ratio,
            box.size.height * ratio,
          );
        },
      );
    });
  }

  @override
  void dispose() {
    // A provider may not be mutated during the element tree's dispose phase.
    scheduleMicrotask(() => _pip.unbind(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
