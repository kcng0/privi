import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../data/services/picture_in_picture_service.dart';
import '../../domain/enums.dart';
import '../lock/lock_controller.dart';

final pictureInPictureGatewayProvider =
    Provider<PictureInPictureGateway>((ref) {
  final gateway = MethodChannelPictureInPictureGateway();
  ref.onDispose(() => unawaited(gateway.dispose()));
  return gateway;
});

class PictureInPictureState {
  const PictureInPictureState({
    this.supported = false,
    this.isActive = false,
    this.grantActive = false,
    this.currentMediaId,
    this.controller,
  });

  final bool supported;
  final bool isActive;

  /// Includes preparation before Android enters PiP. Never advance a playlist
  /// while this single-item authorization exists.
  final bool grantActive;
  final String? currentMediaId;
  final VideoPlayerController? controller;

  PictureInPictureState copyWith({
    bool? supported,
    bool? isActive,
    bool? grantActive,
    String? currentMediaId,
    VideoPlayerController? controller,
    bool clearBinding = false,
  }) =>
      PictureInPictureState(
        supported: supported ?? this.supported,
        isActive: isActive ?? this.isActive,
        grantActive: grantActive ?? this.grantActive,
        currentMediaId:
            clearBinding ? null : currentMediaId ?? this.currentMediaId,
        controller: clearBinding ? null : controller ?? this.controller,
      );
}

/// A PiP grant is tied to one controller AND media id. It never unlocks the
/// vault, creates a decoder, or uses the external-player handoff bypass.
class PictureInPictureController extends Notifier<PictureInPictureState> {
  late PictureInPictureGateway _gateway;
  Object? _binding;
  VideoPlayerController? _boundController;
  final _pendingPlayback = <VideoPlayerController, (String, VoidCallback)>{};
  Rect? Function()? _sourceRect;
  int _sessionId = 0;
  int _revocation = 0;
  bool? _lastPlaying;
  Timer? _entryDeadline;
  Completer<void>? _entryCancelled;
  bool _nativeEntryRequested = false;
  AppLifecycleState? _lifecycle;

  @override
  PictureInPictureState build() {
    _gateway = ref.watch(pictureInPictureGatewayProvider);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    final listener = AppLifecycleListener(onStateChange: onAppLifecycle);
    final events = _gateway.events.listen(_onNativeEvent);
    ref.listen(lockControllerProvider, (_, next) {
      if (next.status != LockStatus.unlocked && !state.grantActive) {
        _pause(state.controller);
      }
      _pauseDisallowedCandidates();
    });
    ref.onDispose(() {
      listener.dispose();
      unawaited(events.cancel());
      _entryDeadline?.cancel();
      _cancelEntryWait();
      _boundController?.removeListener(_onVideoChanged);
      for (final entry in _pendingPlayback.entries) {
        entry.key.removeListener(entry.value.$2);
      }
      _pendingPlayback.clear();
    });
    Future<void>.microtask(_loadSupport);
    return const PictureInPictureState();
  }

  bool get _foreground =>
      _lifecycle == null || _lifecycle == AppLifecycleState.resumed;

  /// Playback permission is checked before the first frame too. A PiP grant
  /// authorizes exactly the bound media/controller; every other candidate must
  /// remain paused while the vault is locked or the app is not foregrounded.
  bool canPlay({
    required VideoPlayerController controller,
    required String mediaId,
  }) {
    if (!ref.mounted || !controller.value.isInitialized) return false;
    if (state.grantActive) {
      return identical(state.controller, controller) &&
          state.currentMediaId == mediaId;
    }
    return !state.isActive &&
        _foreground &&
        ref.read(lockControllerProvider).status == LockStatus.unlocked;
  }

  /// Completion must not advance a playlist after pause/revocation. The caller
  /// also checks that this is still its current item and latest async request.
  bool get canAdvance =>
      ref.mounted &&
      !state.grantActive &&
      !state.isActive &&
      _foreground &&
      ref.read(lockControllerProvider).status == LockStatus.unlocked;

  Future<bool> playIfAllowed({
    required VideoPlayerController controller,
    required String mediaId,
  }) async {
    if (!canPlay(controller: controller, mediaId: mediaId)) {
      _pause(controller);
      return false;
    }
    if (!identical(controller, _boundController)) {
      _removeCandidate(controller);
      void guard() {
        if (!canPlay(controller: controller, mediaId: mediaId)) {
          _pause(controller);
        }
      }

      _pendingPlayback[controller] = (mediaId, guard);
      controller.addListener(guard);
    }
    try {
      await controller.play();
      final stillTracked = identical(controller, _boundController) ||
          _pendingPlayback[controller]?.$1 == mediaId;
      if (!stillTracked || !canPlay(controller: controller, mediaId: mediaId)) {
        // Reassert the native pause even if an earlier lifecycle callback has
        // already changed Dart's value while play() was still in flight.
        await controller.pause();
        return false;
      }
      return true;
    } catch (_) {
      releaseController(controller);
      rethrow;
    }
  }

  /// Call before disposing stale/failed candidates. The widget binding takes
  /// over this registration once the successfully selected video is rendered.
  void releaseController(VideoPlayerController controller) {
    _removeCandidate(controller);
    _pause(controller);
  }

  void _removeCandidate(VideoPlayerController controller) {
    final candidate = _pendingPlayback.remove(controller);
    if (candidate != null) controller.removeListener(candidate.$2);
  }

  void _pauseDisallowedCandidates() {
    for (final entry in _pendingPlayback.entries.toList()) {
      if (!canPlay(controller: entry.key, mediaId: entry.value.$1)) {
        _pause(entry.key);
      }
    }
  }

  void _cancelEntryWait() {
    final cancellation = _entryCancelled;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  Future<void> _loadSupport() async {
    try {
      final supported = await _gateway.isSupported();
      if (ref.mounted) state = state.copyWith(supported: supported);
    } catch (error, stack) {
      _report(error, stack, 'checking PiP availability');
    }
  }

  void bind({
    required Object owner,
    required String mediaId,
    required VideoPlayerController controller,
    Rect? Function()? sourceRect,
  }) {
    if (identical(_binding, owner) &&
        identical(state.controller, controller) &&
        state.currentMediaId == mediaId) {
      return;
    }
    if (state.grantActive) _revoke();
    final previous = state.controller;
    previous?.removeListener(_onVideoChanged);
    if (previous != null && !identical(previous, controller)) _pause(previous);
    _binding = owner;
    _boundController = controller;
    _removeCandidate(controller);
    _sourceRect = sourceRect;
    _lastPlaying = null;
    state = state.copyWith(controller: controller, currentMediaId: mediaId);
    controller.addListener(_onVideoChanged);
    _onVideoChanged();
  }

  void unbind(Object owner) {
    if (!ref.mounted) return;
    if (!identical(owner, _binding)) return;
    if (state.grantActive) _revoke();
    state.controller?.removeListener(_onVideoChanged);
    _pause(state.controller);
    _binding = null;
    _boundController = null;
    _sourceRect = null;
    state = state.copyWith(clearBinding: true);
  }

  Future<void> enter({Rect? sourceRect}) async {
    final controller = state.controller;
    if (!state.supported ||
        controller == null ||
        !controller.value.isInitialized ||
        state.grantActive ||
        state.isActive ||
        ref.read(lockControllerProvider).status != LockStatus.unlocked ||
        (_lifecycle != null && _lifecycle != AppLifecycleState.resumed)) {
      throw StateError(
        'PiP requires an unlocked, initialized foreground video',
      );
    }
    final session = ++_sessionId;
    final cancellation = _entryCancelled = Completer<void>();
    _nativeEntryRequested = false;
    final ratio =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final rect = sourceRect == null
        ? _sourceRect?.call()
        : Rect.fromLTRB(
            sourceRect.left * ratio,
            sourceRect.top * ratio,
            sourceRect.right * ratio,
            sourceRect.bottom * ratio,
          );
    state = state.copyWith(grantActive: true);
    ref.read(lockControllerProvider.notifier).lock();
    _entryDeadline = Timer(const Duration(seconds: 5), () {
      if (ref.mounted &&
          session == _sessionId &&
          state.grantActive &&
          !state.isActive) {
        _revoke();
        _report(
          StateError('PiP entry did not become active'),
          StackTrace.current,
          'entering PiP',
        );
      }
    });
    try {
      // Render the video-only root surface before Android captures the window.
      await Future.any(
        [WidgetsBinding.instance.endOfFrame, cancellation.future],
      );
      if (!ref.mounted || session != _sessionId || !state.grantActive) return;
      final value = controller.value;
      final rotated = value.rotationCorrection % 180 != 0;
      final size = value.size;
      final aspect =
          rotated ? size.height / size.width : size.width / size.height;
      _nativeEntryRequested = true;
      final entered = await _gateway
          .enter(
            sessionId: session,
            aspectRatio: aspect.isFinite && aspect > 0 ? aspect : 16 / 9,
            isPlaying: value.isPlaying,
            sourceRect: rect,
          )
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted || session != _sessionId || !state.grantActive) return;
      if (!entered) {
        throw PlatformException(
          code: 'pip_rejected',
          message: 'Android rejected PiP',
        );
      }
    } catch (_) {
      if (ref.mounted && session == _sessionId) _revoke();
      rethrow;
    }
  }

  /// Flutter hidden/paused can arrive during a successful PiP handoff. Native
  /// onStop/screen-off is the authority for revoking an authorized handoff.
  /// Before the native request, any foreground loss cancels preparation: a
  /// stopped engine may never render the frame that enter() is waiting for.
  void onAppLifecycle(AppLifecycleState lifecycle) {
    _lifecycle = lifecycle;
    if (state.grantActive && !_nativeEntryRequested && !_foreground) _revoke();
    if (!state.grantActive && !_foreground) {
      _pause(state.controller);
    }
    _pauseDisallowedCandidates();
    if (lifecycle == AppLifecycleState.detached && state.grantActive) _revoke();
  }

  void _onNativeEvent(PictureInPictureEvent event) {
    if (!ref.mounted || event.sessionId != _sessionId) return;
    switch (event.type) {
      case PictureInPictureEventType.active:
        if (!state.grantActive) {
          _revoke();
          return;
        }
        _entryDeadline?.cancel();
        state = state.copyWith(isActive: true);
        _onVideoChanged();
      case PictureInPictureEventType.exited:
        _revoke(active: false);
      case PictureInPictureEventType.stopped:
      case PictureInPictureEventType.screenOff:
        _revoke();
      case PictureInPictureEventType.play:
        if (state.grantActive && state.isActive) {
          _run(
            playIfAllowed(
              controller: state.controller!,
              mediaId: state.currentMediaId!,
            ).then<void>((_) {}),
            'playing PiP video',
          );
        }
      case PictureInPictureEventType.pause:
        if (state.grantActive && state.isActive) _pause(state.controller);
    }
  }

  void _revoke({bool? active}) {
    final session = _sessionId;
    final revocation = ++_revocation;
    _entryDeadline?.cancel();
    _cancelEntryWait();
    // Lock first; consumers must never see a revoked grant and an unlocked vault.
    ref.read(lockControllerProvider.notifier).lock();
    // Until native confirms its cover and pinned status, render black. A late
    // entry callback must never capture credential UI during a failed handoff.
    state = state.copyWith(grantActive: false, isActive: active ?? true);
    _pause(state.controller);
    _run(_finishRevocation(session, revocation), 'revoking PiP');
  }

  Future<void> _finishRevocation(int session, int revocation) async {
    final stillPinned = await _gateway.revoke(session);
    if (!ref.mounted ||
        session != _sessionId ||
        revocation != _revocation ||
        state.grantActive) {
      return;
    }
    state = state.copyWith(isActive: stillPinned);
    await WidgetsBinding.instance.endOfFrame;
    if (!ref.mounted ||
        session != _sessionId ||
        revocation != _revocation ||
        state.grantActive) {
      return;
    }
    await _gateway.acknowledgeExit(session);
  }

  void _onVideoChanged() {
    if (!ref.mounted) return;
    final controller = state.controller;
    if (controller == null) return;
    if (!canPlay(controller: controller, mediaId: state.currentMediaId!)) {
      _pause(controller);
      return;
    }
    final playing = controller.value.isPlaying;
    if (state.grantActive && playing != _lastPlaying) {
      _lastPlaying = playing;
      _run(_gateway.setPlaying(_sessionId, playing), 'updating PiP action');
    }
  }

  void _pause(VideoPlayerController? controller) {
    if (controller == null || !controller.value.isPlaying) return;
    _run(controller.pause(), 'pausing video');
  }

  void _run(Future<void> operation, String context) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        _report(error, stack, context);
      }),
    );
  }

  void _report(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Privi picture in picture',
        context: ErrorDescription(context),
      ),
    );
  }
}

final pictureInPictureControllerProvider =
    NotifierProvider<PictureInPictureController, PictureInPictureState>(
  PictureInPictureController.new,
);
