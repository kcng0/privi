import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

enum VideoFitMode { fit, fill, original, ratio4x3, ratio16x9 }

Duration clampVideoPosition(Duration position, Duration duration) {
  if (position < Duration.zero) return Duration.zero;
  if (position > duration) return duration;
  return position;
}

/// VLC-style non-linear seek: small drags stay precise while a full-width
/// swipe can move up to ten minutes.
Duration videoSwipeSeekDelta({
  required double horizontalDelta,
  required double viewportWidth,
  required Duration duration,
  required int minimumSeconds,
}) {
  if (horizontalDelta == 0 || viewportWidth <= 0 || duration <= Duration.zero) {
    return Duration.zero;
  }
  final direction = horizontalDelta.sign.toInt();
  final fraction = (horizontalDelta.abs() / viewportWidth).clamp(0.0, 1.0);
  final maximumMs = math.min(
    duration.inMilliseconds,
    const Duration(minutes: 10).inMilliseconds,
  );
  final minimumMs = math.min(
    Duration(seconds: minimumSeconds).inMilliseconds,
    maximumMs,
  );
  final curvedMs =
      minimumMs + ((maximumMs - minimumMs) * math.pow(fraction, 4)).round();
  return Duration(milliseconds: direction * curvedMs);
}

String formatVideoTime(Duration duration) {
  final totalSeconds = duration.inSeconds.abs();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatVideoDelta(Duration duration) {
  final sign = duration.isNegative ? '-' : '+';
  return '$sign${formatVideoTime(duration)}';
}

String formatVideoProgress(Duration position, Duration duration) {
  return '${formatVideoTime(position)}/${formatVideoTime(duration)}';
}

abstract final class VideoSystemUi {
  static Future<void> apply(bool immersive) {
    return SystemChrome.setEnabledSystemUIMode(
      immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  static Future<void> toggle(bool currentlyLandscape) async {
    await SystemChrome.setPreferredOrientations(
      currentlyLandscape
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  static Future<void> restore() async {
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class VideoViewport extends StatelessWidget {
  const VideoViewport({
    super.key,
    required this.controller,
    required this.fitMode,
  });

  final VideoPlayerController controller;
  final VideoFitMode fitMode;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final sourceAspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
    return ClipRect(
      child: switch (fitMode) {
        VideoFitMode.fit => _ratioViewport(sourceAspect),
        VideoFitMode.fill => _fillViewport(sourceAspect),
        VideoFitMode.original => _originalViewport(value.size, sourceAspect),
        VideoFitMode.ratio4x3 => _ratioViewport(4 / 3),
        VideoFitMode.ratio16x9 => _ratioViewport(16 / 9),
      },
    );
  }

  Widget _ratioViewport(double aspectRatio) {
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _fillViewport(double aspectRatio) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: aspectRatio * 1000,
          height: 1000,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _originalViewport(Size sourceSize, double fallbackAspect) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (sourceSize.isEmpty) return _ratioViewport(fallbackAspect);
        final scale = math.min(
          1.0,
          math.min(
            constraints.maxWidth / sourceSize.width,
            constraints.maxHeight / sourceSize.height,
          ),
        );
        return Center(
          child: SizedBox(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }
}

class VideoGestureSurface extends StatefulWidget {
  const VideoGestureSurface({
    super.key,
    required this.controller,
    required this.seekSeconds,
    required this.onTap,
    required this.child,
    this.onPreviewFrameRequested,
  });

  final VideoPlayerController controller;
  final int seekSeconds;
  final VoidCallback onTap;
  final Widget child;
  final Future<Uint8List?> Function(Duration position)? onPreviewFrameRequested;

  @override
  State<VideoGestureSurface> createState() => _VideoGestureSurfaceState();
}

class _VideoGestureSurfaceState extends State<VideoGestureSurface> {
  static const _fastForwardSpeed = 2.0;

  Offset? _doubleTapPosition;
  Duration? _dragStartPosition;
  Duration? _dragTarget;
  double _dragPixels = 0;
  bool _resumeAfterDrag = false;
  double? _speedBeforeFastForward;
  late final ValueNotifier<_SeekFeedback?> _feedbackNotifier =
      ValueNotifier<_SeekFeedback?>(null);
  Timer? _feedbackTimer;
  Timer? _previewTimer;
  Uint8List? _previewFrame;
  Duration? _previewPosition;
  Duration? _pendingPreviewPosition;
  bool _previewInFlight = false;
  int _previewGeneration = 0;

  @override
  void didUpdateWidget(VideoGestureSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _restorePlaybackSpeed(oldWidget.controller);
      _feedbackTimer?.cancel();
      _feedbackNotifier.value = null;
      _dragStartPosition = null;
      _dragTarget = null;
      _dragPixels = 0;
      _resumeAfterDrag = false;
      _clearPreview();
    }
  }

  @override
  void dispose() {
    _restorePlaybackSpeed(widget.controller);
    _feedbackTimer?.cancel();
    _previewTimer?.cancel();
    _feedbackNotifier.dispose();
    super.dispose();
  }

  void _startFastForward(LongPressStartDetails details) {
    if (_speedBeforeFastForward != null) return;
    _speedBeforeFastForward = widget.controller.value.playbackSpeed;
    unawaited(widget.controller.setPlaybackSpeed(_fastForwardSpeed));
    setState(() {});
  }

  void _stopFastForward() {
    _restorePlaybackSpeed(widget.controller);
    if (mounted) setState(() {});
  }

  void _restorePlaybackSpeed(VideoPlayerController controller) {
    final speed = _speedBeforeFastForward;
    if (speed == null) return;
    _speedBeforeFastForward = null;
    unawaited(controller.setPlaybackSpeed(speed));
  }

  Future<void> _handleDoubleTap() async {
    final width = context.size?.width ?? 0;
    final tap = _doubleTapPosition;
    if (width <= 0 || tap == null) return;
    final direction = tap.dx < width / 2 ? -1 : 1;
    final delta = Duration(seconds: direction * widget.seekSeconds);
    final target = clampVideoPosition(
      widget.controller.value.position + delta,
      widget.controller.value.duration,
    );
    await widget.controller.seekTo(target);
    _showFeedback(
      _SeekFeedback(
        delta: delta,
        target: target,
        alignment: direction < 0
            ? const Alignment(-0.68, 0)
            : const Alignment(0.68, 0),
      ),
      autoHide: true,
    );
  }

  void _handleDragStart(DragStartDetails details) {
    _feedbackTimer?.cancel();
    _dragStartPosition = widget.controller.value.position;
    _dragTarget = _dragStartPosition;
    _dragPixels = 0;
    _resumeAfterDrag = widget.controller.value.isPlaying;
    _clearPreviewAndRebuild();
    if (_resumeAfterDrag) unawaited(widget.controller.pause());
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final start = _dragStartPosition;
    final width = context.size?.width ?? 0;
    if (start == null || width <= 0) return;
    _dragPixels += details.primaryDelta ?? 0;
    final delta = videoSwipeSeekDelta(
      horizontalDelta: _dragPixels,
      viewportWidth: width,
      duration: widget.controller.value.duration,
      minimumSeconds: widget.seekSeconds,
    );
    final target = clampVideoPosition(
      start + delta,
      widget.controller.value.duration,
    );
    _dragTarget = target;
    _schedulePreview(target);
    _showFeedback(
      _SeekFeedback(
        delta: target - start,
        target: target,
        alignment: Alignment.center,
      ),
      autoHide: false,
    );
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    final target = _dragTarget;
    _dragStartPosition = null;
    _dragTarget = null;
    _dragPixels = 0;
    final resume = _resumeAfterDrag;
    _resumeAfterDrag = false;
    _clearPreviewAndRebuild();
    if (target != null) await widget.controller.seekTo(target);
    if (resume) await widget.controller.play();
    _scheduleFeedbackHide();
  }

  void _handleDragCancel() {
    _dragStartPosition = null;
    _dragTarget = null;
    _dragPixels = 0;
    final resume = _resumeAfterDrag;
    _resumeAfterDrag = false;
    _clearPreviewAndRebuild();
    if (resume) unawaited(widget.controller.play());
    _scheduleFeedbackHide();
  }

  void _showFeedback(_SeekFeedback feedback, {required bool autoHide}) {
    if (!mounted) return;
    _feedbackNotifier.value = feedback;
    if (autoHide) _scheduleFeedbackHide();
  }

  void _scheduleFeedbackHide() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) _feedbackNotifier.value = null;
    });
  }

  void _schedulePreview(Duration position) {
    if (widget.onPreviewFrameRequested == null) return;
    _pendingPreviewPosition = position;
    if (_previewInFlight || (_previewTimer?.isActive ?? false)) return;
    _previewTimer = Timer(const Duration(milliseconds: 110), _requestPreview);
  }

  void _requestPreview() {
    final request = widget.onPreviewFrameRequested;
    final position = _pendingPreviewPosition;
    if (request == null || position == null || !mounted) return;
    _pendingPreviewPosition = null;
    _previewInFlight = true;
    final generation = ++_previewGeneration;
    unawaited(() async {
      try {
        final frame = await request(position);
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewFrame = frame;
          _previewPosition = position;
        });
      } finally {
        _previewInFlight = false;
        if (_pendingPreviewPosition != null && mounted) {
          _previewTimer =
              Timer(const Duration(milliseconds: 40), _requestPreview);
        }
      }
    }());
  }

  void _clearPreview() {
    _previewGeneration++;
    _previewTimer?.cancel();
    _previewTimer = null;
    _pendingPreviewPosition = null;
    _previewFrame = null;
    _previewPosition = null;
  }

  void _clearPreviewAndRebuild() {
    final hadPreview = _previewFrame != null;
    _clearPreview();
    if (hadPreview && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: () => unawaited(_handleDoubleTap()),
      onLongPressStart: _startFastForward,
      onLongPressEnd: (_) => _stopFastForward(),
      onLongPressCancel: _stopFastForward,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: (details) => unawaited(_handleDragEnd(details)),
      onHorizontalDragCancel: _handleDragCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_previewFrame != null && _previewPosition != null)
            IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 92),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xE61C1C1E),
                      border: Border.all(color: Colors.white54),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.memory(
                            _previewFrame!,
                            key: const Key('video-frame-preview'),
                            width: 220,
                            height: 124,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              formatVideoProgress(
                                _previewPosition!,
                                widget.controller.value.duration,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_speedBeforeFastForward != null)
            const IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: _FastForwardFeedback(),
                  ),
                ),
              ),
            ),
          ValueListenableBuilder<_SeekFeedback?>(
            valueListenable: _feedbackNotifier,
            builder: (context, feedback, _) {
              if (feedback == null) return const SizedBox.shrink();
              return IgnorePointer(
                child: Align(
                  alignment: feedback.alignment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE61C1C1E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          feedback.delta.isNegative
                              ? Icons.fast_rewind
                              : Icons.fast_forward,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${formatVideoDelta(feedback.delta)}  '
                          '${formatVideoProgress(
                            feedback.target,
                            widget.controller.value.duration,
                          )}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FastForwardFeedback extends StatelessWidget {
  const _FastForwardFeedback();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE61C1C1E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fast_forward, color: Colors.white, size: 22),
          SizedBox(width: 6),
          Text(
            '2x',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _SeekFeedback {
  const _SeekFeedback({
    required this.delta,
    required this.target,
    required this.alignment,
  });

  final Duration delta;
  final Duration target;
  final Alignment alignment;
}
