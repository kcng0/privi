import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/player/picture_in_picture_controller.dart';
import 'package:privi/data/services/picture_in_picture_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:video_player/video_player.dart';

class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}

class _Video extends VideoPlayerController {
  _Video() : super.networkUrl(Uri.parse('https://example.invalid/video')) {
    value = const VideoPlayerValue(
      duration: Duration(minutes: 1),
      size: Size(1920, 1080),
      isInitialized: true,
      isPlaying: true,
    );
  }

  int pauses = 0;
  int plays = 0;
  Completer<void>? playCompletion;

  @override
  Future<void> pause() async {
    pauses++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(isPlaying: true);
    await playCompletion?.future;
  }
}

class _Gateway implements PictureInPictureGateway {
  final _events = StreamController<PictureInPictureEvent>.broadcast(sync: true);
  int session = 0;
  int revoked = 0;
  int acknowledged = 0;
  bool autoActivate = true;
  Object? failure;
  Completer<bool>? entering;
  Completer<bool>? revoking;
  final playing = <bool>[];
  bool pinned = false;

  void emit(PictureInPictureEventType type, {int? id}) {
    if (type == PictureInPictureEventType.active) pinned = true;
    if (type == PictureInPictureEventType.exited) pinned = false;
    _events.add(PictureInPictureEvent(type, id ?? session));
  }

  @override
  Stream<PictureInPictureEvent> get events => _events.stream;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<bool> enter({
    required int sessionId,
    required double aspectRatio,
    required bool isPlaying,
    Rect? sourceRect,
  }) async {
    session = sessionId;
    if (failure != null) throw failure!;
    if (entering != null) return entering!.future;
    if (autoActivate) emit(PictureInPictureEventType.active);
    return true;
  }

  @override
  Future<void> setPlaying(int sessionId, bool playing) async =>
      this.playing.add(playing);
  @override
  Future<bool> revoke(int sessionId) async {
    revoked++;
    if (revoking != null) return revoking!.future;
    return pinned;
  }

  @override
  Future<void> acknowledgeExit(int sessionId) async {
    acknowledged++;
  }

  @override
  Future<void> dispose() => _events.close();
}

Future<
    ({
      ProviderContainer container,
      PictureInPictureController pip,
      _Video video,
      _Gateway gateway,
      Object owner
    })> _setup(WidgetTester tester) async {
  final gateway = _Gateway();
  final container = ProviderContainer(
    overrides: [
      pictureInPictureGatewayProvider.overrideWithValue(gateway),
      lockControllerProvider.overrideWith(_UnlockedLock.new),
    ],
  );
  final pip = container.read(pictureInPictureControllerProvider.notifier);
  final video = _Video();
  final owner = Object();
  pip.onAppLifecycle(AppLifecycleState.resumed);
  pip.bind(owner: owner, mediaId: 'private-video', controller: video);
  await tester.pump();
  addTearDown(() async {
    container.dispose();
    await gateway.dispose();
    await video.dispose();
  });
  return (
    container: container,
    pip: pip,
    video: video,
    gateway: gateway,
    owner: owner
  );
}

void main() {
  testWidgets(
      'button grant locks root immediately and survives handoff lifecycle order',
      (tester) async {
    final h = await _setup(tester);
    h.gateway.entering = Completer<bool>();
    final entering = h.pip.enter();
    expect(h.container.read(lockControllerProvider).status, LockStatus.locked);
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isTrue,
    );
    expect(
      h.gateway.session,
      0,
      reason: 'video-only frame precedes native entry',
    );
    await tester.pump();
    expect(h.gateway.session, isNot(0));
    h.pip.onAppLifecycle(AppLifecycleState.inactive);
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    h.pip.onAppLifecycle(AppLifecycleState.paused);
    h.gateway.emit(PictureInPictureEventType.active);
    h.gateway.entering!.complete(true);
    await entering;
    expect(
      h.container.read(pictureInPictureControllerProvider).isActive,
      isTrue,
    );
    expect(h.video.value.isPlaying, isTrue);
    expect(
      h.container.read(pictureInPictureControllerProvider).currentMediaId,
      'private-video',
    );
  });

  testWidgets(
      'leaving foreground before native handoff cancels without a frame',
      (tester) async {
    final h = await _setup(tester);
    final entering = h.pip.enter();
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    h.pip.onAppLifecycle(AppLifecycleState.paused);
    // No pump: a stopped Flutter engine cannot be required to draw a new frame
    // just to cancel an entry that was never handed off to Android.
    await entering;
    expect(h.gateway.session, 0);
    expect(h.video.value.isPlaying, isFalse);
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isFalse,
    );
    expect(h.container.read(lockControllerProvider).status, LockStatus.locked);
    expect(h.pip.canAdvance, isFalse);
    await tester.pump();
  });

  testWidgets('entry deadline includes waiting for the first video-only frame',
      (tester) async {
    final h = await _setup(tester);
    final entering = h.pip.enter();
    await tester.pump(const Duration(seconds: 5));
    await entering;
    expect(tester.takeException(), isA<StateError>());
    expect(h.gateway.session, 0);
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isFalse,
    );
    expect(h.video.value.isPlaying, isFalse);
    await tester.pump();
  });

  testWidgets(
      'new candidates cannot start after initialization finishes in background',
      (tester) async {
    final h = await _setup(tester);
    final candidate = _Video();
    addTearDown(candidate.dispose);
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    expect(
      await h.pip.playIfAllowed(controller: candidate, mediaId: 'next'),
      isFalse,
    );
    expect(candidate.plays, 0);
    expect(candidate.value.isPlaying, isFalse);
    expect(h.pip.canAdvance, isFalse);
  });

  testWidgets(
      'candidate remains guarded between play completion and first widget binding',
      (tester) async {
    final h = await _setup(tester);
    final candidate = _Video();
    addTearDown(candidate.dispose);
    expect(
      await h.pip.playIfAllowed(controller: candidate, mediaId: 'next'),
      isTrue,
    );
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    expect(candidate.value.isPlaying, isFalse);
    expect(
      h.container.read(pictureInPictureControllerProvider).controller,
      same(h.video),
    );
    h.pip.onAppLifecycle(AppLifecycleState.resumed);
    await h.pip.playIfAllowed(controller: candidate, mediaId: 'next');
    h.container.read(lockControllerProvider.notifier).lock();
    expect(candidate.value.isPlaying, isFalse);
    expect(h.pip.canAdvance, isFalse);
  });

  testWidgets(
      'play finishing after background reasserts pause before reporting success',
      (tester) async {
    final h = await _setup(tester);
    final candidate = _Video()..playCompletion = Completer<void>();
    addTearDown(candidate.dispose);
    final playing = h.pip.playIfAllowed(controller: candidate, mediaId: 'next');
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    expect(candidate.value.isPlaying, isFalse);
    final pauses = candidate.pauses;
    candidate.playCompletion!.complete();
    expect(await playing, isFalse);
    expect(candidate.pauses, greaterThan(pauses));
  });

  testWidgets(
      'release removes stale candidate registration and binding takes over guard',
      (tester) async {
    final h = await _setup(tester);
    final candidate = _Video();
    addTearDown(candidate.dispose);
    await h.pip.playIfAllowed(controller: candidate, mediaId: 'next');
    h.pip.releaseController(candidate);
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    // A released candidate belongs to its disposer, not the playback guard.
    await candidate.play();
    expect(candidate.value.isPlaying, isTrue);
    h.pip.onAppLifecycle(AppLifecycleState.resumed);
    await h.pip.playIfAllowed(controller: candidate, mediaId: 'next');
    h.pip.bind(owner: Object(), mediaId: 'next', controller: candidate);
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    expect(candidate.value.isPlaying, isFalse);
  });

  testWidgets(
      'grant never allows a different candidate or playlist advancement',
      (tester) async {
    final h = await _setup(tester);
    final candidate = _Video();
    addTearDown(candidate.dispose);
    final entering = h.pip.enter();
    expect(
      h.pip.canPlay(controller: h.video, mediaId: 'private-video'),
      isTrue,
    );
    expect(h.pip.canPlay(controller: h.video, mediaId: 'other-id'), isFalse);
    expect(
      await h.pip.playIfAllowed(controller: candidate, mediaId: 'next'),
      isFalse,
    );
    expect(candidate.plays, 0);
    expect(h.pip.canAdvance, isFalse);
    await tester.pump();
    await entering;
    h.gateway.emit(PictureInPictureEventType.exited);
    expect(h.pip.canAdvance, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('normal background and root lock pause without a PiP grant',
      (tester) async {
    final h = await _setup(tester);
    h.pip.onAppLifecycle(AppLifecycleState.hidden);
    expect(h.video.value.isPlaying, isFalse);
    h.pip.onAppLifecycle(AppLifecycleState.resumed);
    expect(h.video.value.isPlaying, isFalse, reason: 'resume never autoplays');
    await h.video.play();
    h.container.read(lockControllerProvider.notifier).lock();
    expect(h.video.value.isPlaying, isFalse);
    await h.video.play();
    expect(
      h.video.value.isPlaying,
      isFalse,
      reason: 'locked route cannot restart playback',
    );
  });

  for (final ending in [
    PictureInPictureEventType.screenOff,
    PictureInPictureEventType.stopped,
    PictureInPictureEventType.exited,
  ]) {
    testWidgets(
        '$ending revokes, pauses and acknowledges only after lock frame',
        (tester) async {
      final h = await _setup(tester);
      final entering = h.pip.enter();
      await tester.pump();
      await entering;
      h.gateway.emit(ending);
      expect(
        h.container.read(lockControllerProvider).status,
        LockStatus.locked,
      );
      expect(
        h.container.read(pictureInPictureControllerProvider).grantActive,
        isFalse,
      );
      expect(h.video.value.isPlaying, isFalse);
      expect(h.gateway.acknowledged, 0);
      h.gateway.emit(PictureInPictureEventType.play);
      expect(h.video.value.isPlaying, isFalse);
      await tester.pump();
      await tester.pump();
      expect(h.gateway.acknowledged, 1);
      if (ending != PictureInPictureEventType.exited) {
        expect(
          h.container.read(pictureInPictureControllerProvider).isActive,
          isTrue,
          reason: 'revoked PiP stays black until native exit',
        );
        h.gateway.emit(PictureInPictureEventType.exited);
        await tester.pump();
      }
      expect(
        h.container.read(pictureInPictureControllerProvider).isActive,
        isFalse,
      );
      h.pip.onAppLifecycle(AppLifecycleState.resumed);
      expect(h.video.value.isPlaying, isFalse);
    });
  }

  testWidgets('native entry failure propagates and revokes the grant',
      (tester) async {
    final h = await _setup(tester);
    h.gateway.failure = PlatformException(code: 'denied');
    final result =
        expectLater(h.pip.enter(), throwsA(isA<PlatformException>()));
    await tester.pump();
    await result;
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isFalse,
    );
    expect(h.container.read(lockControllerProvider).status, LockStatus.locked);
    expect(h.video.value.isPlaying, isFalse);
    await tester.pump();
    expect(h.gateway.acknowledged, 1);
  });

  testWidgets('stop before entry result and late active cannot resurrect grant',
      (tester) async {
    final h = await _setup(tester);
    h.gateway.entering = Completer<bool>();
    final entering = h.pip.enter();
    await tester.pump();
    h.gateway.emit(PictureInPictureEventType.stopped);
    h.gateway.entering!.complete(true);
    await entering;
    h.gateway.emit(PictureInPictureEventType.active);
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isFalse,
    );
    expect(h.video.value.isPlaying, isFalse);
    await tester.pump();
  });

  testWidgets('revocation keeps the root black until native confirms its cover',
      (tester) async {
    final h = await _setup(tester);
    h.gateway.entering = Completer<bool>();
    h.gateway.revoking = Completer<bool>();
    final entering = h.pip.enter();
    await tester.pump();
    h.gateway.emit(PictureInPictureEventType.stopped);
    h.gateway.entering!.complete(true);
    await entering;
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isFalse,
    );
    expect(
      h.container.read(pictureInPictureControllerProvider).isActive,
      isTrue,
    );
    expect(h.video.value.isPlaying, isFalse);
    await tester.pump();
    expect(h.gateway.acknowledged, 0);
    h.gateway.revoking!.complete(false);
    await tester.pump();
    await tester.pump();
    expect(
      h.container.read(pictureInPictureControllerProvider).isActive,
      isFalse,
    );
    expect(h.gateway.acknowledged, 1);
    expect(h.container.read(lockControllerProvider).status, LockStatus.locked);
  });

  testWidgets('system play and pause target only the authorized controller',
      (tester) async {
    final h = await _setup(tester);
    final entering = h.pip.enter();
    await tester.pump();
    await entering;
    h.gateway.emit(PictureInPictureEventType.pause);
    expect(h.video.value.isPlaying, isFalse);
    h.gateway.emit(PictureInPictureEventType.play);
    expect(h.video.value.isPlaying, isTrue);
    expect(h.video.plays, 1);
    expect(h.gateway.playing, containsAllInOrder([true, false, true]));
    h.gateway.emit(PictureInPictureEventType.pause, id: h.gateway.session + 1);
    expect(h.video.value.isPlaying, isTrue);
  });

  testWidgets(
      'changing media/controller revokes instead of extending single-item authorization',
      (tester) async {
    final h = await _setup(tester);
    final entering = h.pip.enter();
    await tester.pump();
    await entering;
    final next = _Video();
    addTearDown(next.dispose);
    h.pip.bind(owner: Object(), mediaId: 'another-video', controller: next);
    expect(
      h.container.read(pictureInPictureControllerProvider).grantActive,
      isFalse,
    );
    expect(h.video.value.isPlaying, isFalse);
    expect(next.value.isPlaying, isFalse);
    h.gateway.emit(PictureInPictureEventType.play);
    expect(next.value.isPlaying, isFalse);
    await tester.pump();
  });
}
