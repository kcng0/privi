import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/player/advanced_video_controller.dart';
import '../../application/player/picture_in_picture_controller.dart';
import '../../application/player/video_preview_coordinator.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../data/services/playback_orientation_service.dart';
import '../../data/services/video_frame_service.dart';
import 'video_advanced_controls.dart';
import 'video_playback_lifecycle.dart';
import 'video_player_surface.dart';

/// Route-scoped presentation choices survive changes of the active media.
/// Per-video adapters only subscribe to the existing engine; they never create it.
mixin VideoPresentationSession<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  late final PictureInPictureController _playbackOwner;

  @override
  void initState() {
    super.initState();
    _playbackOwner = ref.read(pictureInPictureControllerProvider.notifier);
  }

  bool get videoMayAdvance => mounted && _playbackOwner.canAdvance;

  Future<bool> playVideoWhenAllowed(
    VideoPlayerController controller,
    String mediaId, {
    required bool Function() isCurrent,
  }) async {
    if (!mounted || !isCurrent()) return false;
    final played = await _playbackOwner.playIfAllowed(
      controller: controller,
      mediaId: mediaId,
    );
    if (!mounted || !isCurrent()) {
      releaseVideoPlayback(controller);
      await controller.pause();
      return false;
    }
    return played;
  }

  void releaseVideoPlayback(VideoPlayerController controller) =>
      _playbackOwner.releaseController(controller);

  AdvancedVideoController? videoAdvanced;
  VideoPreviewCoordinator? _preview;
  VideoPlayerController? _presentationVideo;
  bool videoTouchLocked = false;
  bool videoOrientationLocked = false;
  String videoOrientation = 'auto';
  bool _orientationStarted = false;
  Future<void> _orientationOperations = Future<void>.value();

  bool get videoPipGranted =>
      ref.read(pictureInPictureControllerProvider).grantActive;
  bool get _videoPipVisible {
    final pip = ref.read(pictureInPictureControllerProvider);
    // Revocation can finish before Android expands the retained route.
    return pip.grantActive || pip.isActive;
  }

  bool get videoChromeAllowed => !videoTouchLocked && !_videoPipVisible;
  bool get videoPipSupported =>
      ref.watch(pictureInPictureControllerProvider).supported;

  void bindVideoPresentation(VideoPlayerController controller, String path) {
    if (identical(_presentationVideo, controller)) return;
    detachVideoPresentation();
    _presentationVideo = controller;
    videoAdvanced = AdvancedVideoController(controller);
    _preview = VideoPreviewCoordinator(
      load: (position) =>
          VideoFrameService().frameAtTime(path: path, position: position),
    );
    _startVideoOrientation();
  }

  void _startVideoOrientation() {
    if (!_orientationStarted) {
      _orientationStarted = true;
      final settings = ref.read(settingsControllerProvider);
      videoOrientation = settings.playerDefaultOrientation == 'lastLocked'
          ? settings.playerLastLockedOrientation
          : settings.playerDefaultOrientation;
      videoOrientationLocked =
          settings.playerDefaultOrientation == 'lastLocked';
      _orientationOperations = _orientationOperations.then<void>((_) async {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await PlaybackOrientationService.instance.begin();
        }
        await _applyVideoOrientation(videoOrientation);
      }).catchError((Object error) => _videoError(error));
    }
  }

  void detachVideoPresentation() {
    videoAdvanced?.dispose();
    videoAdvanced = null;
    _preview?.dispose();
    _preview = null;
    _presentationVideo = null;
  }

  void disposeVideoPresentation() {
    detachVideoPresentation();
    if (!_orientationStarted) return;
    unawaited(
      _orientationOperations.then<void>((_) async {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await PlaybackOrientationService.instance.restore();
        } else {
          await SystemChrome.setPreferredOrientations(const []);
        }
      }).catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Privi playback orientation',
          ),
        );
      }),
    );
  }

  Future<Uint8List?> videoPreviewFrame(Duration position) async =>
      _preview?.requestFrame(position);

  Future<void> _applyVideoOrientation(String mode) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlaybackOrientationService.instance.setMode(mode);
    }
    return SystemChrome.setPreferredOrientations(
      switch (mode) {
        'portrait' => const [DeviceOrientation.portraitUp],
        'reversePortrait' => const [DeviceOrientation.portraitDown],
        'landscape' => const [DeviceOrientation.landscapeLeft],
        'reverseLandscape' => const [DeviceOrientation.landscapeRight],
        'sensorLandscape' => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        'sensorPortrait' => const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
        _ => const [],
      },
    );
  }

  Future<void> _setVideoOrientation(String mode, {bool locked = false}) async {
    _startVideoOrientation();
    final request =
        _orientationOperations.then((_) => _applyVideoOrientation(mode));
    _orientationOperations =
        request.catchError((Object error) => _videoError(error));
    try {
      await request;
      if (!mounted) return;
      setState(() {
        videoOrientation = mode;
        videoOrientationLocked = locked;
      });
      if (locked) {
        await ref
            .read(settingsControllerProvider.notifier)
            .setPlayerLastLockedOrientation(mode);
      }
    } catch (_) {
      // The serialized operation reports the actual platform error once.
    }
  }

  Future<void> chooseVideoOrientation() async {
    final selected =
        await showVideoOrientationSheet(context, current: videoOrientation);
    if (selected != null && mounted) await _setVideoOrientation(selected);
  }

  Future<void> toggleVideoOrientationLock() async {
    if (videoOrientationLocked) return _setVideoOrientation('auto');
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    await _setVideoOrientation(
      landscape ? 'sensorLandscape' : 'sensorPortrait',
      locked: true,
    );
  }

  Future<void> openVideoAdvanced() async {
    final advanced = videoAdvanced;
    final controller = _presentationVideo;
    if (advanced == null || controller == null) return;
    await showVideoAdvancedSheet(
      context,
      advanced: advanced,
      controller: controller,
    );
  }

  Future<void> enterVideoPictureInPicture() async {
    try {
      await ref.read(pictureInPictureControllerProvider.notifier).enter();
    } catch (error) {
      _videoError(error);
    }
  }

  void _videoError(Object error) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.errorWithDetails(error.toString())),
        ),
      );
    });
  }

  Widget videoViewportWithLifecycle({
    required VideoPlayerController controller,
    required String mediaId,
    required VideoFitMode fitMode,
    required VoidCallback onTap,
    VoidCallback? onUserSeek,
  }) =>
      VideoPlaybackLifecycle(
        controller: controller,
        mediaId: mediaId,
        child: VideoGestureSurface(
          controller: controller,
          enabled: videoChromeAllowed,
          seekSeconds: ref.watch(settingsControllerProvider).playerSeekSeconds,
          dragSeekSeconds:
              ref.watch(settingsControllerProvider).playerDragSeekSeconds,
          onTap: onTap,
          onUserSeek: onUserSeek,
          onResume: () async {
            await playVideoWhenAllowed(
              controller,
              mediaId,
              isCurrent: () => identical(_presentationVideo, controller),
            );
          },
          onPreviewFrameRequested: videoPreviewFrame,
          child: ValueListenableBuilder<AdvancedVideoState>(
            valueListenable: videoAdvanced!,
            builder: (context, state, _) => VideoViewport(
              controller: controller,
              fitMode: fitMode,
              displaySize: state.displaySize.isEmpty ? null : state.displaySize,
            ),
          ),
        ),
      );

  Widget videoSessionTopActions({
    bool compact = false,
    List<PopupMenuEntry<VoidCallback>> additionalMenuItems = const [],
  }) {
    if (compact) {
      return PopupMenuButton<VoidCallback>(
        key: const Key('video-session-menu'),
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => unawaited(toggleVideoOrientationLock()),
            child: Text(
              videoOrientationLocked
                  ? context.l10n.videoUnlockOrientation
                  : context.l10n.videoLockOrientation,
            ),
          ),
          PopupMenuItem(
            value: () => setState(() => videoTouchLocked = true),
            child: Text(context.l10n.videoLockTouch),
          ),
          ...additionalMenuItems,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: videoOrientationLocked
              ? context.l10n.videoUnlockOrientation
              : context.l10n.videoLockOrientation,
          icon: Icon(
            videoOrientationLocked
                ? Icons.screen_lock_rotation
                : Icons.screen_rotation,
          ),
          color: Colors.white,
          onPressed: () => unawaited(toggleVideoOrientationLock()),
        ),
        IconButton(
          tooltip: context.l10n.videoLockTouch,
          icon: const Icon(Icons.lock_outline),
          color: Colors.white,
          onPressed: () => setState(() => videoTouchLocked = true),
        ),
      ],
    );
  }

  Widget videoUnlockControl() => _videoPipVisible
      ? const SizedBox.shrink()
      : Align(
          alignment: Alignment.topRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filledTonal(
                key: const Key('video-unlock-touch'),
                tooltip: context.l10n.videoUnlockTouch,
                icon: const Icon(Icons.lock_open),
                onPressed: () => setState(() => videoTouchLocked = false),
              ),
            ),
          ),
        );
}
