import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/advanced_video_controller.dart';
import 'package:video_player/video_player.dart';

void main() {
  test('fallback exposes real facade audio support and corrected display size',
      () async {
    final video = _Facade(supported: true, rotation: 90);
    final advanced = AdvancedVideoController(video);
    addTearDown(video.dispose);
    addTearDown(advanced.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(advanced.value.displaySize, const Size(1080, 1920));
    expect(advanced.value.supportsAudioTracks, isTrue);
    expect(advanced.value.audioTracks.length, 2);
    await advanced.selectAudioTrack('fr');
    expect(video.selected, 'fr');
    expect(
      advanced.value.audioTracks.singleWhere((t) => t.isSelected).id,
      'fr',
    );
    expect(advanced.value.supportsSubtitles, isFalse);
    expect(advanced.value.supportsAudioDelay, isFalse);
    expect(advanced.value.supportsAbLoop, isFalse);
    await expectLater(
      advanced.setSubtitleDelay(const Duration(seconds: 1)),
      throwsUnsupportedError,
    );
    expect(advanced.value.error, contains('Subtitle delay is unavailable'));
  });

  test('unsupported fallback does not call unavailable facade APIs', () async {
    final video = _Facade(supported: false);
    final advanced = AdvancedVideoController(video);
    addTearDown(video.dispose);
    addTearDown(advanced.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(video.trackRequests, 0);
    expect(advanced.value.supportsAudioTracks, isFalse);
    await expectLater(advanced.selectAudioTrack('fr'), throwsUnsupportedError);
    expect(video.selected, 'en');
  });

  test('position ticks do not emit unchanged display metadata', () async {
    final video = _Facade(supported: false);
    final advanced = AdvancedVideoController(video);
    addTearDown(video.dispose);
    addTearDown(advanced.dispose);
    await Future<void>.delayed(Duration.zero);
    var updates = 0;
    advanced.addListener(() => updates++);
    video.value = video.value.copyWith(position: const Duration(seconds: 1));
    video.value = video.value.copyWith(position: const Duration(seconds: 2));
    expect(updates, 0);
    video.value = video.value.copyWith(size: const Size(720, 480));
    expect(updates, 1);
    expect(advanced.value.displaySize, const Size(720, 480));
  });

  test('late facade results cannot publish after advanced controller disposal',
      () async {
    final video = _Facade(supported: true);
    video.loadGate = Completer<void>();
    final advanced = AdvancedVideoController(video);
    advanced.dispose();
    video.loadGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(video.disposed, isFalse);
    expect(video.hasSubscribers, isFalse);
    await video.dispose();
  });

  test(
      'native metadata remains authoritative and detaches without disposing it',
      () async {
    final video = _Facade(supported: true, rotation: 90);
    final native = _AdvancedPort();
    final advanced = AdvancedVideoController(video, port: native);
    expect(advanced.value.displaySize, const Size(1080, 1920));
    native.value = const AdvancedVideoState(displaySize: Size(720, 576));
    expect(advanced.value.displaySize, const Size(720, 576));
    advanced.dispose();
    expect(native.hasSubscribers, isFalse);
    expect(video.disposed, isFalse);
    native.value = const AdvancedVideoState(displaySize: Size(640, 480));
    native.dispose();
    await video.dispose();
  });
}

class _Facade extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  _Facade({required this.supported, int rotation = 0})
      : super(
          VideoPlayerValue(
            duration: const Duration(seconds: 30),
            isInitialized: true,
            size: const Size(1920, 1080),
            rotationCorrection: rotation,
          ),
        );

  final bool supported;
  String selected = 'en';
  int trackRequests = 0;
  bool disposed = false;
  Completer<void>? loadGate;

  bool get hasSubscribers => hasListeners;

  @override
  int get playerId => -1;

  @override
  bool isAudioTrackSupportAvailable() => supported;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() async {
    trackRequests++;
    await loadGate?.future;
    return [
      for (final id in ['en', 'fr'])
        VideoAudioTrack(id: id, language: id, isSelected: selected == id),
    ];
  }

  @override
  Future<void> selectAudioTrack(String id) async => selected = id;

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AdvancedPort extends ValueNotifier<AdvancedVideoState>
    implements AdvancedVideoPort {
  _AdvancedPort()
      : super(const AdvancedVideoState(displaySize: Size(1080, 1920)));

  bool get hasSubscribers => hasListeners;

  @override
  Future<void> refresh() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
