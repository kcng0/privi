import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../data/services/playback_display_service.dart';
import '../../domain/models/video_playback_settings.dart';
import '../../domain/models/video_player_capabilities.dart';

export '../../domain/models/video_playback_settings.dart' show VideoFitMode;

Duration clampVideoPosition(Duration position, Duration duration) {
  if (position < Duration.zero) return Duration.zero;
  if (position > duration) return duration;
  return position;
}

/// Natural end of built-in playback. `isCompleted` is flaky on some devices,
/// so a near-end position also counts — but never for clips shorter than
/// [slop], and never for a paused/seeked position inside the slop window.
bool videoPlaybackEnded(
  VideoPlayerValue value, {
  Duration slop = const Duration(milliseconds: 350),
}) {
  if (!value.isInitialized) return false;
  final duration = value.duration;
  if (duration <= Duration.zero) return false;
  if (value.isCompleted) return true;
  if (duration <= slop) return false;
  if (value.position >= duration) return true;
  if (!value.isPlaying) return false;
  return value.position >= duration - slop;
}

/// Whether a folder viewer should start the next sorted video.
bool shouldAdvanceFolderVideoOnEnd({
  required VideoPlayerValue value,
  required bool looping,
  required bool vaultUnlocked,
  required bool isCurrentItem,
  required bool alreadyAdvanced,
  DateTime? ignoreUntil,
  DateTime? now,
}) {
  if (!vaultUnlocked || looping || !isCurrentItem || alreadyAdvanced) {
    return false;
  }
  final clock = now ?? DateTime.now();
  if (ignoreUntil != null && !clock.isAfter(ignoreUntil)) {
    return false;
  }
  return videoPlaybackEnded(value);
}

/// Serializes video controller create/dispose work for one screen.
class VideoControllerQueue {
  Future<void> _ops = Future<void>.value();

  Future<void> enqueue(Future<void> Function() operation) {
    final scheduled = _ops.then((_) => operation());
    _ops = scheduled.then<void>(
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
    return scheduled;
  }
}

/// Next folder item after a built-in video ends, using the current sort order.
int? nextIndexAfterVideoEnd({
  required int index,
  required int length,
  required bool looping,
  required bool ended,
}) {
  if (!ended || looping || index < 0) return null;
  final next = index + 1;
  if (next >= length) return null;
  return next;
}

/// VLC maps centimeters (not screen fraction) through a 4th-power curve:
/// an 8cm swipe seeks [fullSwipeSeconds] plus [minimumSeconds].
const videoDragSeekFullSwipeCentimeters = 8.0;

double logicalPixelsForCentimeters(double centimeters) =>
    centimeters / 2.54 * 160;

Duration videoSwipeSeekDelta({
  required double horizontalDelta,
  required Duration duration,
  required int fullSwipeSeconds,
  int minimumSeconds = 3,
}) {
  if (horizontalDelta == 0 ||
      duration <= Duration.zero ||
      fullSwipeSeconds <= 0) {
    return Duration.zero;
  }
  final direction = horizontalDelta.sign.toInt();
  final gestureCm = (horizontalDelta.abs() / 160) * 2.54;
  final jumpMs = (Duration(seconds: fullSwipeSeconds).inMilliseconds *
              math.pow(
                gestureCm / videoDragSeekFullSwipeCentimeters,
                4,
              ) +
          Duration(seconds: minimumSeconds).inMilliseconds)
      .round();
  final clampedMs = jumpMs.clamp(0, duration.inMilliseconds);
  return Duration(milliseconds: direction * clampedMs);
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

/// Full-height swipe covers the full 0–1 range. Up increases the value.
double videoVerticalAdjustDelta({
  required double verticalDelta,
  required double viewportHeight,
}) {
  if (verticalDelta == 0 || viewportHeight <= 0) return 0;
  return (-verticalDelta / viewportHeight).clamp(-1.0, 1.0);
}

/// Display size after applying `rotationCorrection` (90/270 swap axes).
/// Phone portrait clips are often stored as 1920x1080 with a 90° tag.
Size displaySizeForVideo(
  Size size, {
  int rotationCorrection = 0,
}) {
  if (size.isEmpty) return size;
  final turns = ((rotationCorrection % 360) + 360) % 360;
  if (turns == 90 || turns == 270) {
    return Size(size.height, size.width);
  }
  return size;
}

double displayAspectRatioForVideo(
  Size size, {
  int rotationCorrection = 0,
  double fallback = 16 / 9,
}) {
  final display = displaySizeForVideo(
    size,
    rotationCorrection: rotationCorrection,
  );
  if (display.width <= 0 || display.height <= 0) return fallback;
  return display.width / display.height;
}

/// Built-in video hides status and navigation bars in every orientation.
/// Landscape already used immersive sticky; portrait used to keep the bars.
bool shouldHideSystemUiForBuiltInVideo(bool builtInVideo) => builtInVideo;

abstract final class VideoSystemUi {
  static Future<void> apply(bool immersive) {
    return SystemChrome.setEnabledSystemUIMode(
      immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  static Future<void> restore() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await PlaybackDisplayService.instance.resetBrightness();
  }
}

/// The only sizing owner. All sizes are in final display coordinates, so a
/// fixed aspect ratio never reverses when the device rotates.
Size videoViewportSize({
  required Size viewport,
  required Size displaySize,
  required VideoFitMode mode,
  double devicePixelRatio = 1,
}) {
  if (viewport.isEmpty) return Size.zero;
  final source = displaySize.isEmpty ? const Size(16, 9) : displaySize;
  if (mode == VideoFitMode.fill) return viewport;
  if (mode == VideoFitMode.original && !displaySize.isEmpty) {
    return source / devicePixelRatio;
  }
  final ratio = mode.aspectRatio ?? source.aspectRatio;
  final contain = Size(viewport.width, viewport.width / ratio);
  if (mode == VideoFitMode.fitScreen) {
    return contain.height >= viewport.height
        ? contain
        : Size(viewport.height * ratio, viewport.height);
  }
  return contain.height <= viewport.height
      ? contain
      : Size(viewport.height * ratio, viewport.height);
}

class VideoViewport extends StatefulWidget {
  const VideoViewport({
    super.key,
    required this.controller,
    required this.fitMode,
    this.displaySize,
  });
  final VideoPlayerController controller;
  final VideoFitMode fitMode;

  /// Advanced backend dimensions have already applied rotation exactly once.
  final Size? displaySize;
  @override
  State<VideoViewport> createState() => _VideoViewportState();
}

class _VideoViewportState extends State<VideoViewport> {
  late Size _size;
  late int _rotation;
  late Widget _video;
  NativeVideoPresentationPlatform? get _nativePresentation {
    final Object platform = VideoPlayerPlatform.instance;
    return platform is NativeVideoPresentationPlatform ? platform : null;
  }

  void _attach() {
    _size = widget.controller.value.size;
    _rotation = widget.controller.value.rotationCorrection;
    _video = VideoPlayer(widget.controller);
    widget.controller.addListener(_metadataChanged);
  }

  void _metadataChanged() {
    final value = widget.controller.value;
    if (value.size == _size && value.rotationCorrection == _rotation) return;
    setState(() {
      _size = value.size;
      _rotation = value.rotationCorrection;
    });
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(VideoViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_metadataChanged);
      _attach();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_metadataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final native = _nativePresentation;
          if (native != null) {
            // LibVLC owns placement inside this bounded native viewport,
            // including SAR/rotation and physical pixels in Original mode.
            // Applying Flutter's OverflowBox as well would scale twice.
            return ClipRect(
              child: SizedBox.expand(
                child: native.buildNativeViewport(
                  // ignore: invalid_use_of_visible_for_testing_member
                  widget.controller.playerId,
                  widget.fitMode,
                ),
              ),
            );
          }
          final size = videoViewportSize(
            viewport: constraints.biggest,
            displaySize: widget.displaySize ??
                displaySizeForVideo(_size, rotationCorrection: _rotation),
            mode: widget.fitMode,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
          return ClipRect(
            child: SizedBox.expand(
              child: OverflowBox(
                alignment: Alignment.center,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: SizedBox(
                  key: const Key('video-display-rect'),
                  width: size.width,
                  height: size.height,
                  child: _video,
                ),
              ),
            ),
          );
        },
      );
}

class VideoGestureSurface extends StatefulWidget {
  const VideoGestureSurface({
    super.key,
    required this.controller,
    required this.seekSeconds,
    required this.onTap,
    required this.child,
    this.dragSeekSeconds = defaultPlayerDragSeekSeconds,
    this.onUserSeek,
    this.onSeekStarted,
    this.onResume,
    this.onFastForwardStarted,
    this.displayControls,
    this.enabled = true,
  });

  final VideoPlayerController controller;
  final bool enabled;
  final int seekSeconds;
  final int dragSeekSeconds;
  final VoidCallback onTap;
  final Widget child;
  final VoidCallback? onUserSeek;
  final VoidCallback Function()? onSeekStarted;
  final Future<void> Function()? onResume;
  final VoidCallback? onFastForwardStarted;
  final VideoDisplayControls? displayControls;

  @override
  State<VideoGestureSurface> createState() => _VideoGestureSurfaceState();
}

class _FastForwardRate {
  _FastForwardRate(this.normalSpeed) : appliedSpeed = normalSpeed;

  final double normalSpeed;
  double? appliedSpeed;
  Future<void> pending = Future<void>.value();
  int revision = 0;
  bool retired = false;
}

class _VideoGestureSurfaceState extends State<VideoGestureSurface> {
  static const _fastForwardSpeed = 2.0;

  Offset? _doubleTapPosition;
  Duration? _dragStartPosition;
  Duration? _dragTarget;
  double _dragPixels = 0;
  VideoPlayerController? _dragController;
  final _pointers = <int>{};
  int? _dragPointer;
  bool _dragWasPlaying = false;
  VoidCallback? _dragSeekRelease;
  final _seekReleases = <VoidCallback>{};
  int _interaction = 0;
  VideoPlayerController? _fastForwardController;
  final _rates = <VideoPlayerController, _FastForwardRate>{};
  final _fastForwardNotifier = ValueNotifier<bool>(false);
  _VerticalAdjustKind? _verticalKind;
  double? _verticalStartValue;
  double _verticalPixels = 0;
  late final ValueNotifier<_SeekFeedback?> _feedbackNotifier =
      ValueNotifier<_SeekFeedback?>(null);
  late final ValueNotifier<_LevelFeedback?> _levelNotifier =
      ValueNotifier<_LevelFeedback?>(null);
  Timer? _feedbackTimer;

  VideoDisplayControls get _displayControls =>
      widget.displayControls ?? PlaybackDisplayService.instance;

  @override
  void didUpdateWidget(VideoGestureSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        (oldWidget.enabled && !widget.enabled)) {
      if (oldWidget.controller != widget.controller) {
        _retirePlaybackSpeed(oldWidget.controller);
      } else {
        _stopFastForward();
      }
      _interaction++;
      _feedbackTimer?.cancel();
      _feedbackNotifier.value = null;
      _levelNotifier.value = null;
      _doubleTapPosition = null;
      _pointers.clear();
      _releaseSeekScopes();
      _resetDrag();
      _resetVerticalAdjust();
    }
  }

  @override
  void dispose() {
    _releaseSeekScopes();
    _retirePlaybackSpeed(widget.controller);
    _feedbackTimer?.cancel();
    _fastForwardNotifier.dispose();
    _feedbackNotifier.dispose();
    _levelNotifier.dispose();
    super.dispose();
  }

  void _startFastForward(LongPressStartDetails details) {
    final controller = widget.controller;
    if (!widget.enabled ||
        !controller.value.isInitialized ||
        _fastForwardController != null) {
      return;
    }
    widget.onFastForwardStarted?.call();
    if (!mounted || !widget.enabled || controller != widget.controller) return;
    _fastForwardController = controller;
    _fastForwardNotifier.value = true;
    _queuePlaybackSpeed(controller, fastForward: true);
  }

  void _stopFastForward() {
    final controller = _fastForwardController;
    if (controller == null) return;
    _fastForwardController = null;
    _fastForwardNotifier.value = false;
    _queuePlaybackSpeed(controller, fastForward: false);
  }

  void _retirePlaybackSpeed(VideoPlayerController controller) {
    // The route owns releasing replaced/disposed engines. Do not issue a late
    // facade setter after that owner may already have disposed this controller.
    _rates.remove(controller)?.retired = true;
    if (identical(_fastForwardController, controller)) {
      _fastForwardController = null;
      _fastForwardNotifier.value = false;
    }
  }

  void _queuePlaybackSpeed(
    VideoPlayerController controller, {
    required bool fastForward,
  }) {
    // Keep the baseline until the final restore completes. A second hold can
    // begin while the facade still optimistically reports the previous 2x.
    final rate = _rates.putIfAbsent(
      controller,
      () => _FastForwardRate(controller.value.playbackSpeed),
    );
    final revision = ++rate.revision;
    rate.pending = rate.pending.then((_) async {
      if (rate.retired || rate.revision != revision) return;
      final target = fastForward ? _fastForwardSpeed : rate.normalSpeed;
      var failed = false;
      try {
        if (rate.appliedSpeed != target) {
          await controller.setPlaybackSpeed(target);
          rate.appliedSpeed = target;
          if (!rate.retired && !controller.value.isPlaying) {
            // Native rate application may finish after the lifecycle owner
            // paused playback; never let that delayed operation resume it.
            await controller.pause();
          }
        }
      } catch (error, stack) {
        failed = true;
        rate.appliedSpeed = null;
        _reportGestureError(error, stack, 'changing long-press playback speed');
        if (mounted &&
            rate.revision == revision &&
            identical(_fastForwardController, controller)) {
          _fastForwardController = null;
          _fastForwardNotifier.value = false;
        }
        if (fastForward && !rate.retired && rate.revision == revision) {
          try {
            await controller.setPlaybackSpeed(rate.normalSpeed);
          } catch (error, stack) {
            _reportGestureError(error, stack, 'restoring playback speed');
          }
        }
      }
      if (identical(_rates[controller], rate) &&
          rate.revision == revision &&
          (!fastForward || failed)) {
        _rates.remove(controller);
      }
    });
  }

  void _reportGestureError(Object error, StackTrace stack, String action) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Privi video gestures',
        context: ErrorDescription(action),
      ),
    );
  }

  bool _isCurrentInteraction(
    VideoPlayerController controller,
    int interaction,
  ) =>
      mounted &&
      widget.enabled &&
      identical(widget.controller, controller) &&
      _interaction == interaction;

  VoidCallback _beginSeekScope() {
    final onRelease = widget.onSeekStarted?.call();
    var released = false;
    late final VoidCallback release;
    release = () {
      if (released) return;
      released = true;
      _seekReleases.remove(release);
      onRelease?.call();
    };
    _seekReleases.add(release);
    return release;
  }

  void _releaseSeekScopes() {
    for (final release in _seekReleases.toList()) {
      release();
    }
  }

  Future<bool> _seek(
    VideoPlayerController controller,
    Duration target,
    int interaction, {
    bool wasPlaying = false,
  }) async {
    if (!_isCurrentInteraction(controller, interaction)) return false;
    // Suppress natural-end advancement before seek updates the video value.
    widget.onUserSeek?.call();
    if (!_isCurrentInteraction(controller, interaction)) return false;
    final resumeAfterCompletion = wasPlaying &&
        !controller.value.isPlaying &&
        controller.value.isCompleted &&
        target < controller.value.duration;
    try {
      await controller.seekTo(target);
      if (resumeAfterCompletion &&
          _isCurrentInteraction(controller, interaction)) {
        // Playback continued during the drag and reached its natural end.
        // Only the lifecycle owner can permit restarting at the chosen target.
        await widget.onResume?.call();
      }
      return _isCurrentInteraction(controller, interaction);
    } catch (error, stack) {
      _reportGestureError(error, stack, 'seeking video');
      return false;
    }
  }

  Future<void> _handleDoubleTap() async {
    final width = context.size?.width ?? 0;
    final tap = _doubleTapPosition;
    if (width <= 0 || tap == null) return;
    final controller = widget.controller;
    if (!widget.enabled || !controller.value.isInitialized) return;
    final interaction = ++_interaction;
    final direction = tap.dx < width / 2 ? -1 : 1;
    final delta = Duration(seconds: direction * widget.seekSeconds);
    final target = clampVideoPosition(
      controller.value.position + delta,
      controller.value.duration,
    );
    final release = _beginSeekScope();
    bool sought;
    try {
      sought = await _seek(controller, target, interaction);
    } finally {
      release();
    }
    if (!sought) return;
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
    final controller = widget.controller;
    if (!widget.enabled || !controller.value.isInitialized) return;
    _interaction++;
    _feedbackTimer?.cancel();
    _dragSeekRelease?.call();
    _dragSeekRelease = _beginSeekScope();
    _dragController = controller;
    _dragPointer = _pointers.firstOrNull;
    _dragWasPlaying = controller.value.isPlaying;
    _dragStartPosition = controller.value.position;
    _dragTarget = _dragStartPosition;
    _dragPixels = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final controller = _dragController;
    final start = _dragStartPosition;
    if (controller == null ||
        start == null ||
        !_isCurrentInteraction(controller, _interaction)) {
      return;
    }
    _dragPixels += details.primaryDelta ?? 0;
    final delta = videoSwipeSeekDelta(
      horizontalDelta: _dragPixels,
      duration: controller.value.duration,
      fullSwipeSeconds: widget.dragSeekSeconds,
      minimumSeconds: widget.seekSeconds,
    );
    final target = clampVideoPosition(start + delta, controller.value.duration);
    _dragTarget = target;
    _showFeedback(
      _SeekFeedback(
        delta: target - start,
        target: target,
        alignment: Alignment.center,
      ),
      autoHide: false,
    );
  }

  void _resetDrag({bool release = true}) {
    if (release) _dragSeekRelease?.call();
    _dragSeekRelease = null;
    _dragController = null;
    _dragPointer = null;
    _dragWasPlaying = false;
    _dragStartPosition = null;
    _dragTarget = null;
    _dragPixels = 0;
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    final controller = _dragController;
    final target = _dragTarget;
    final interaction = _interaction;
    final release = _dragSeekRelease;
    final wasPlaying = _dragWasPlaying;
    _resetDrag(release: false);
    try {
      if (controller == null || target == null) return;
      if (await _seek(
        controller,
        target,
        interaction,
        wasPlaying: wasPlaying,
      )) {
        _scheduleFeedbackHide();
      }
    } finally {
      release?.call();
    }
  }

  void _handleDragCancel() {
    _interaction++;
    _resetDrag();
    _scheduleFeedbackHide();
  }

  Future<void> _handleVerticalDragStart(DragStartDetails details) async {
    _feedbackTimer?.cancel();
    _feedbackNotifier.value = null;
    _verticalKind = details.localPosition.dx <
            (context.size?.width ?? MediaQuery.sizeOf(context).width) / 2
        ? _VerticalAdjustKind.brightness
        : _VerticalAdjustKind.volume;
    _verticalPixels = 0;
    final start = _verticalKind == _VerticalAdjustKind.brightness
        ? await _displayControls.getBrightness()
        : await _displayControls.getVolume();
    if (!mounted || _verticalKind == null) return;
    _verticalStartValue = start;
    _showLevelFeedback(start);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final kind = _verticalKind;
    final start = _verticalStartValue;
    final height = context.size?.height ?? 0;
    if (kind == null || start == null || height <= 0) return;
    _verticalPixels += details.primaryDelta ?? 0;
    final next = (start +
            videoVerticalAdjustDelta(
              verticalDelta: _verticalPixels,
              viewportHeight: height,
            ))
        .clamp(0.0, 1.0);
    unawaited(
      kind == _VerticalAdjustKind.brightness
          ? _displayControls.setBrightness(next)
          : _displayControls.setVolume(next),
    );
    _showLevelFeedback(next);
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _resetVerticalAdjust();
    _scheduleFeedbackHide();
  }

  void _handleVerticalDragCancel() {
    _resetVerticalAdjust();
    _scheduleFeedbackHide();
  }

  void _resetVerticalAdjust() {
    _verticalKind = null;
    _verticalStartValue = null;
    _verticalPixels = 0;
  }

  void _showLevelFeedback(double value) {
    final kind = _verticalKind;
    if (!mounted || kind == null) return;
    _levelNotifier.value = _LevelFeedback(kind: kind, value: value);
  }

  void _showFeedback(_SeekFeedback feedback, {required bool autoHide}) {
    if (!mounted) return;
    _feedbackNotifier.value = feedback;
    if (autoHide) _scheduleFeedbackHide();
  }

  void _scheduleFeedbackHide() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      _feedbackNotifier.value = null;
      _levelNotifier.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return AbsorbPointer(child: widget.child);
    return Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        if (_dragPointer == event.pointer) {
          _dragPointer = _pointers.firstOrNull;
        }
      },
      onPointerCancel: (event) {
        // An accepted Flutter drag can report PointerCancel as a drag end.
        // Clear the target before that end callback can submit a seek.
        _pointers.remove(event.pointer);
        if (_dragPointer == event.pointer) _handleDragCancel();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTapDown: (details) =>
            _doubleTapPosition = details.localPosition,
        onDoubleTap: () => unawaited(_handleDoubleTap()),
        onLongPressStart: _startFastForward,
        onLongPressEnd: (_) => _stopFastForward(),
        onLongPressCancel: _stopFastForward,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: (details) => unawaited(_handleDragEnd(details)),
        onHorizontalDragCancel: _handleDragCancel,
        onVerticalDragStart: (details) =>
            unawaited(_handleVerticalDragStart(details)),
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        onVerticalDragCancel: _handleVerticalDragCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            ValueListenableBuilder<bool>(
              valueListenable: _fastForwardNotifier,
              builder: (context, active, child) =>
                  active ? child! : const SizedBox.shrink(),
              child: const IgnorePointer(
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
                            '${formatVideoProgress(feedback.target, widget.controller.value.duration)}',
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
            ValueListenableBuilder<_LevelFeedback?>(
              valueListenable: _levelNotifier,
              builder: (context, feedback, _) {
                if (feedback == null) return const SizedBox.shrink();
                return IgnorePointer(
                  child: Align(
                    alignment: Alignment.center,
                    child: _LevelFeedbackBadge(feedback: feedback),
                  ),
                );
              },
            ),
          ],
        ),
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
          Text('2x', style: TextStyle(color: Colors.white, fontSize: 14)),
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

enum _VerticalAdjustKind { brightness, volume }

class _LevelFeedback {
  const _LevelFeedback({required this.kind, required this.value});

  final _VerticalAdjustKind kind;
  final double value;
}

class _LevelFeedbackBadge extends StatelessWidget {
  const _LevelFeedbackBadge({required this.feedback});

  final _LevelFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final brightness = feedback.kind == _VerticalAdjustKind.brightness;
    return Container(
      key: const Key('video-level-feedback'),
      width: 168,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xE61C1C1E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            brightness
                ? (feedback.value <= 0.01
                    ? Icons.brightness_low
                    : Icons.brightness_high)
                : (feedback.value <= 0.01 ? Icons.volume_off : Icons.volume_up),
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: feedback.value,
                minHeight: 4,
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
