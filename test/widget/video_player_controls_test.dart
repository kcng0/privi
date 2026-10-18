import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/video_preview_coordinator.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/playback_display_service.dart';
import 'package:privi/domain/models/video_playback_settings.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/heart_rating_bar.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _longPressDuration = Duration(milliseconds: 500);

class _GestureVideoPlatform extends VideoPlayerPlatform {
  int _nextId = 0;
  final rates = <(int, double)>[];
  final appliedRates = <(int, double)>[];
  final seeks = <(int, Duration)>[];
  final plays = <int>[];
  final pauses = <int>[];
  final positions = <int, Duration>{};
  Completer<void>? nextRate;
  Completer<void>? nextSeek;

  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async =>
      _nextId++;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 2),
          size: const Size(1920, 1080),
        ),
      );
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    rates.add((playerId, speed));
    final pending = nextRate;
    nextRate = null;
    if (pending != null) await pending.future;
    appliedRates.add((playerId, speed));
  }

  @override
  Future<void> play(int playerId) async => plays.add(playerId);
  @override
  Future<void> pause(int playerId) async => pauses.add(playerId);
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add((playerId, position));
    final pending = nextSeek;
    nextSeek = null;
    if (pending != null) await pending.future;
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  void clearCalls() {
    rates.clear();
    appliedRates.clear();
    seeks.clear();
    plays.clear();
    pauses.clear();
  }
}

_GestureVideoPlatform _installGesturePlatform() {
  final original = VideoPlayerPlatform.instance;
  final platform = _GestureVideoPlatform();
  VideoPlayerPlatform.instance = platform;
  addTearDown(() => VideoPlayerPlatform.instance = original);
  return platform;
}

Future<VideoPlayerController> _playingVideo(
  _GestureVideoPlatform platform, {
  double speed = 1.25,
}) async {
  final video = VideoPlayerController.networkUrl(
    Uri.parse('https://example.com/video.mp4'),
  );
  addTearDown(() => unawaited(video.dispose()));
  await video.initialize();
  await video.seekTo(const Duration(seconds: 15));
  await video.setPlaybackSpeed(speed);
  await video.play();
  platform.clearCalls();
  return video;
}

Future<void> _disposeVideo(
  WidgetTester tester,
  VideoPlayerController video,
) async {
  await tester.runAsync(video.dispose);
  await tester.pump();
}

Widget _gestureApp(
  VideoPlayerController controller, {
  bool enabled = true,
  VoidCallback? onFastForwardStarted,
  VoidCallback? onUserSeek,
  VoidCallback Function()? onSeekStarted,
  Future<void> Function()? onResume,
  Widget child = const ColoredBox(color: Colors.black),
}) =>
    MaterialApp(
      home: VideoGestureSurface(
        controller: controller,
        seekSeconds: 3,
        onTap: () {},
        enabled: enabled,
        onFastForwardStarted: onFastForwardStarted,
        onUserSeek: onUserSeek,
        onSeekStarted: onSeekStarted,
        onResume: onResume,
        child: child,
      ),
    );

class _FakeDisplayControls implements VideoDisplayControls {
  _FakeDisplayControls({this.brightness = 0.4, this.volume = 0.6});

  double brightness;
  double volume;
  final brightnessWrites = <double>[];
  final volumeWrites = <double>[];
  var resetCount = 0;

  @override
  Future<double> getBrightness() async => brightness;

  @override
  Future<void> setBrightness(double value) async {
    brightness = value;
    brightnessWrites.add(value);
  }

  @override
  Future<void> resetBrightness() async {
    resetCount++;
  }

  @override
  Future<double> getVolume() async => volume;

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    volumeWrites.add(value);
  }
}

void main() {
  test('swipe seek follows VLC 8cm curve and the configured full swipe', () {
    const duration = Duration(minutes: 20);
    final eightCm = logicalPixelsForCentimeters(8);
    final fourCm = logicalPixelsForCentimeters(4);

    final precise = videoSwipeSeekDelta(
      horizontalDelta: 50,
      duration: duration,
      fullSwipeSeconds: 600,
      minimumSeconds: 3,
    );
    final medium = videoSwipeSeekDelta(
      horizontalDelta: fourCm,
      duration: duration,
      fullSwipeSeconds: 600,
      minimumSeconds: 3,
    );
    final reverse = videoSwipeSeekDelta(
      horizontalDelta: -fourCm,
      duration: duration,
      fullSwipeSeconds: 600,
      minimumSeconds: 3,
    );
    final maximum = videoSwipeSeekDelta(
      horizontalDelta: eightCm,
      duration: duration,
      fullSwipeSeconds: 600,
      minimumSeconds: 3,
    );
    final faster = videoSwipeSeekDelta(
      horizontalDelta: eightCm,
      duration: const Duration(minutes: 30),
      fullSwipeSeconds: 1200,
      minimumSeconds: 3,
    );
    final shortVideoMaximum = videoSwipeSeekDelta(
      horizontalDelta: eightCm,
      duration: const Duration(minutes: 2),
      fullSwipeSeconds: 600,
      minimumSeconds: 3,
    );

    expect(precise.inMilliseconds, closeTo(3058, 2));
    expect(medium.inMilliseconds, 40500);
    expect(reverse.inMilliseconds, -40500);
    expect(maximum.inMilliseconds, 603000);
    expect(faster.inMilliseconds, 1203000);
    expect(shortVideoMaximum, const Duration(minutes: 2));
  });

  test('video time helpers clamp and format playback positions', () {
    expect(
      clampVideoPosition(
        const Duration(seconds: -1),
        const Duration(minutes: 2),
      ),
      Duration.zero,
    );
    expect(
      clampVideoPosition(
        const Duration(minutes: 3),
        const Duration(minutes: 2),
      ),
      const Duration(minutes: 2),
    );
    expect(formatVideoTime(const Duration(seconds: 65)), '1:05');
    expect(formatVideoTime(const Duration(hours: 1, seconds: 2)), '1:00:02');
    expect(
      formatVideoProgress(
        const Duration(hours: 1, minutes: 2, seconds: 3),
        const Duration(hours: 2, minutes: 3, seconds: 4),
      ),
      '1:02:03/2:03:04',
    );
    expect(formatVideoDelta(const Duration(seconds: -3)), '-0:03');
    expect(formatPlaybackSpeed(1), '1x');
    expect(formatPlaybackSpeed(1.25), '1.25x');
  });

  test('vertical swipe maps full height to the 0–1 range', () {
    expect(
      videoVerticalAdjustDelta(verticalDelta: -200, viewportHeight: 400),
      0.5,
    );
    expect(
      videoVerticalAdjustDelta(verticalDelta: 200, viewportHeight: 400),
      -0.5,
    );
    expect(
      videoVerticalAdjustDelta(verticalDelta: -800, viewportHeight: 400),
      1,
    );
    expect(videoVerticalAdjustDelta(verticalDelta: 0, viewportHeight: 400), 0);
  });

  test('rotation metadata corrects display size exactly once', () {
    expect(
      displayAspectRatioForVideo(
        const Size(1920, 1080),
        rotationCorrection: 90,
      ),
      1080 / 1920,
    );
    expect(
      displaySizeForVideo(const Size(1920, 1080), rotationCorrection: 90),
      const Size(1080, 1920),
    );
    expect(
      displaySizeForVideo(const Size(1920, 1080), rotationCorrection: -90),
      const Size(1080, 1920),
    );
    expect(
      displaySizeForVideo(const Size(1920, 1080), rotationCorrection: 450),
      const Size(1080, 1920),
    );
    expect(
      displaySizeForVideo(const Size(1920, 1080), rotationCorrection: 0),
      const Size(1920, 1080),
    );
  });

  test('built-in video hides system UI in portrait and landscape', () {
    expect(shouldHideSystemUiForBuiltInVideo(true), isTrue);
    expect(shouldHideSystemUiForBuiltInVideo(false), isFalse);
  });

  testWidgets('immersive video UI uses sticky fullscreen mode', (tester) async {
    final modes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments! as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await VideoSystemUi.apply(true);
    await VideoSystemUi.apply(false);
    expect(modes, [
      'SystemUiMode.immersiveSticky',
      'SystemUiMode.edgeToEdge',
    ]);
  });

  testWidgets('viewport uses tight bounds and updates rotated display metadata',
      (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);
    controller.value = const VideoPlayerValue(
      duration: Duration(seconds: 10),
      size: Size(1920, 1080),
      rotationCorrection: 90,
      isInitialized: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 480,
            child: VideoViewport(
              controller: controller,
              fitMode: VideoFitMode.bestFit,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('video-display-rect'))),
      const Size(270, 480),
    );
    final mountedVideo = tester.element(find.byType(VideoPlayer));
    controller.value =
        controller.value.copyWith(position: const Duration(seconds: 3));
    await tester.pump();
    expect(tester.element(find.byType(VideoPlayer)), same(mountedVideo));
    controller.value = controller.value
        .copyWith(size: const Size(720, 1280), rotationCorrection: 0);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('video-display-rect'))),
      const Size(270, 480),
    );
    controller.value = controller.value.copyWith(size: const Size(1920, 1080));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('video-display-rect'))),
      const Size(320, 180),
    );
    expect(tester.element(find.byType(VideoPlayer)), same(mountedVideo));
  });

  testWidgets(
      'portrait video supports every mode without reversing fixed ratios',
      (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);
    final expected = <VideoFitMode, Size>{
      VideoFitMode.bestFit: const Size(270, 480),
      VideoFitMode.fitScreen: const Size(320, 320 * 16 / 9),
      VideoFitMode.fill: const Size(320, 480),
      VideoFitMode.original: const Size(540, 960),
      VideoFitMode.ratio16x9: const Size(320, 180),
      VideoFitMode.ratio4x3: const Size(320, 240),
      VideoFitMode.ratio16x10: const Size(320, 200),
      VideoFitMode.ratio2x1: const Size(320, 160),
      VideoFitMode.ratio221x1: const Size(320, 320 / 2.21),
      VideoFitMode.ratio235x1: const Size(320, 320 / 2.35),
      VideoFitMode.ratio239x1: const Size(320, 320 / 2.39),
      VideoFitMode.ratio5x4: const Size(320, 256),
    };
    for (final rotation in [0, 90, 270]) {
      controller.value = VideoPlayerValue(
        duration: const Duration(seconds: 10),
        size: rotation == 0 ? const Size(1080, 1920) : const Size(1920, 1080),
        rotationCorrection: rotation,
        isInitialized: true,
      );
      for (final entry in expected.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 2),
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 480,
                  child: VideoViewport(
                    controller: controller,
                    fitMode: entry.key,
                  ),
                ),
              ),
            ),
          ),
        );
        final actual =
            tester.getSize(find.byKey(const Key('video-display-rect')));
        expect(
          actual.width,
          closeTo(entry.value.width, .001),
          reason: '${entry.key} rotation=$rotation',
        );
        expect(
          actual.height,
          closeTo(entry.value.height, .001),
          reason: '${entry.key} rotation=$rotation',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  test(
      'original size does not shrink and viewport resizing changes contain only',
      () {
    const portrait = Size(1080, 1920);
    expect(
      videoViewportSize(
        viewport: const Size(640, 360),
        displaySize: portrait,
        mode: VideoFitMode.bestFit,
      ),
      const Size(202.5, 360),
    );
    expect(
      videoViewportSize(
        viewport: const Size(640, 360),
        displaySize: portrait,
        mode: VideoFitMode.original,
        devicePixelRatio: 3,
      ),
      const Size(360, 640),
    );
    expect(
      videoViewportSize(
        viewport: const Size(120, 120),
        displaySize: portrait,
        mode: VideoFitMode.original,
        devicePixelRatio: 1,
      ),
      portrait,
    );
    expect(VideoFitMode.values.length, 12);
    expect(VideoFitMode.fromStored('fit'), VideoFitMode.bestFit);
  });

  testWidgets('long press changes native rate once and restores once',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    var starts = 0;
    var childBuilds = 0;
    await tester.pumpWidget(
      _gestureApp(
        video,
        onFastForwardStarted: () {
          starts++;
          expect(platform.rates, isEmpty);
        },
        child: Builder(
          builder: (_) {
            childBuilds++;
            return const ColoredBox(color: Colors.black);
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    await tester.pump(const Duration(seconds: 2));
    expect(starts, 1);
    expect(platform.rates, [(video.playerId, 2.0)]);
    expect(platform.seeks, isEmpty);
    expect(platform.plays, isEmpty);
    expect(platform.pauses, isEmpty);
    expect(video.value.isPlaying, isTrue);
    expect(find.text('2x'), findsOneWidget);
    expect(childBuilds, 1);
    await gesture.up();
    await tester.pump();
    expect(platform.rates, [(video.playerId, 2.0), (video.playerId, 1.25)]);
    expect(video.value.playbackSpeed, 1.25);
    expect(find.text('2x'), findsNothing);
    expect(childBuilds, 1);
    await _disposeVideo(tester, video);
  });

  testWidgets('cancelled long press restores native playback speed',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    await tester.pumpWidget(_gestureApp(video));
    final gesture = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    await gesture.cancel();
    await tester.pump();
    expect(platform.rates, [(video.playerId, 2.0), (video.playerId, 1.25)]);
    expect(video.value.playbackSpeed, 1.25);
    expect(find.text('2x'), findsNothing);
    await _disposeVideo(tester, video);
  });

  testWidgets('rapid release and another hold serialize delayed native rates',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    final delayedRate = Completer<void>();
    platform.nextRate = delayedRate;
    await tester.pumpWidget(_gestureApp(video));
    final first = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    await first.up();
    await tester.pump();
    final second = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    expect(platform.rates, [(video.playerId, 2.0)]);
    expect(platform.appliedRates, isEmpty);
    delayedRate.complete();
    await tester.pump();
    expect(platform.rates, [(video.playerId, 2.0)]);
    expect(video.value.playbackSpeed, 2);
    expect(find.text('2x'), findsOneWidget);
    await second.up();
    await tester.pump();
    expect(platform.rates.last, (video.playerId, 1.25));
    expect(platform.appliedRates, platform.rates);
    expect(platform.rates.length, 2);
    expect(video.value.playbackSpeed, 1.25);
    expect(platform.seeks, isEmpty);
    await _disposeVideo(tester, video);
  });

  testWidgets('pending hold restoration stays with the previous controller',
      (tester) async {
    final platform = _installGesturePlatform();
    final first = await _playingVideo(platform);
    final second = await _playingVideo(platform, speed: 1.5);
    final delayedRate = Completer<void>();
    platform.nextRate = delayedRate;
    await tester.pumpWidget(_gestureApp(first));
    final firstHold = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    await tester.pumpWidget(_gestureApp(second));
    await _disposeVideo(tester, first);
    await firstHold.up();
    final secondHold = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    expect(platform.rates, [(first.playerId, 2.0), (second.playerId, 2.0)]);
    delayedRate.complete();
    await tester.pump();
    expect(first.value.playbackSpeed, 2);
    expect(second.value.playbackSpeed, 2);
    expect(find.text('2x'), findsOneWidget);
    await secondHold.up();
    await tester.pump();
    expect(platform.rates, [
      (first.playerId, 2.0),
      (second.playerId, 2.0),
      (second.playerId, 1.5),
    ]);
    expect(second.value.playbackSpeed, 1.5);
    expect(platform.seeks, isEmpty);
    await _disposeVideo(tester, first);
    await _disposeVideo(tester, second);
  });

  testWidgets(
      'three holds pending one native write converge to the normal rate',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    final delayedRate = Completer<void>();
    platform.nextRate = delayedRate;
    await tester.pumpWidget(_gestureApp(video));
    for (var i = 0; i < 3; i++) {
      final gesture = await tester.startGesture(const Offset(400, 250));
      await tester.pump(_longPressDuration);
      await gesture.up();
      await tester.pump();
    }
    expect(platform.rates, [(video.playerId, 2.0)]);
    delayedRate.complete();
    await tester.pump();
    expect(platform.rates, [(video.playerId, 2.0), (video.playerId, 1.25)]);
    expect(platform.appliedRates, platform.rates);
    expect(video.value.playbackSpeed, 1.25);
    expect(find.text('2x'), findsNothing);
    await _disposeVideo(tester, video);
  });

  testWidgets(
      'route disposal retires pending rate writes without setter errors',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    final delayedRate = Completer<void>();
    platform.nextRate = delayedRate;
    await tester.pumpWidget(_gestureApp(video));
    final gesture = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    await gesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await _disposeVideo(tester, video);
    delayedRate.complete();
    await tester.pump();
    expect(platform.rates, [(video.playerId, 2.0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disabling a pending hold restores speed without resuming playback',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    final delayedRate = Completer<void>();
    platform.nextRate = delayedRate;
    await tester.pumpWidget(_gestureApp(video));
    final gesture = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    await video.pause();
    await tester.pumpWidget(_gestureApp(video, enabled: false));
    await gesture.up();
    delayedRate.complete();
    await tester.pump();
    // video_player updates the normal facade speed while paused; it sends the
    // restored rate to native only when the lifecycle owner next allows play.
    expect(video.value.playbackSpeed, 1.25);
    expect(video.value.isPlaying, isFalse);
    expect(platform.plays, isEmpty);
    expect(platform.pauses.length, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
    await _disposeVideo(tester, video);
  });

  testWidgets(
      'rejected native hold rate is diagnosed and restores normal speed',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    final rejectedRate = Completer<void>();
    platform.nextRate = rejectedRate;
    await tester.pumpWidget(_gestureApp(video));
    final gesture = await tester.startGesture(const Offset(400, 250));
    await tester.pump(_longPressDuration);
    rejectedRate.completeError(StateError('Native hold rate rejected'));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    await tester.pump();
    expect(platform.rates, [(video.playerId, 2.0), (video.playerId, 1.25)]);
    expect(video.value.playbackSpeed, 1.25);
    expect(find.text('2x'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(platform.rates.length, 2);
    await _disposeVideo(tester, video);
  });

  testWidgets(
      'drag only updates feedback while playing and seeks once on release',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    var childBuilds = 0;
    var userSeeks = 0;
    var resumeRequests = 0;
    await tester.pumpWidget(
      _gestureApp(
        video,
        onUserSeek: () {
          userSeeks++;
          expect(platform.seeks, isEmpty);
        },
        onResume: () async => resumeRequests++,
        child: Builder(
          builder: (_) {
            childBuilds++;
            return const ColoredBox(color: Colors.black);
          },
        ),
      ),
    );
    final detector = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(VideoGestureSurface),
        matching: find.byType(GestureDetector),
      ),
    );
    detector.onHorizontalDragStart!(DragStartDetails());
    for (final delta in [80.0, 40.0, 50.0]) {
      detector.onHorizontalDragUpdate!(
        DragUpdateDetails(
          delta: Offset(delta, 0),
          primaryDelta: delta,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pump();
      expect(platform.seeks, isEmpty);
      expect(platform.pauses, isEmpty);
      expect(platform.plays, isEmpty);
      expect(video.value.isPlaying, isTrue);
    }
    expect(find.byKey(const Key('video-frame-preview')), findsNothing);
    expect(childBuilds, 1);
    final expected = const Duration(seconds: 15) +
        videoSwipeSeekDelta(
          horizontalDelta: 170,
          duration: video.value.duration,
          fullSwipeSeconds: defaultPlayerDragSeekSeconds,
        );
    expect(find.textContaining(formatVideoTime(expected)), findsOneWidget);
    detector.onHorizontalDragEnd!(DragEndDetails());
    await tester.pump();
    expect(platform.seeks, [(video.playerId, expected)]);
    expect(userSeeks, 1);
    expect(resumeRequests, 0);
    expect(platform.pauses, isEmpty);
    expect(platform.plays, isEmpty);
    expect(video.value.isPlaying, isTrue);
    expect(childBuilds, 1);
    await tester.pump(const Duration(seconds: 1));
    await _disposeVideo(tester, video);
  });

  testWidgets('cancelled swipe leaves playing video and position unchanged',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    var userSeeks = 0;
    await tester.pumpWidget(_gestureApp(video, onUserSeek: () => userSeeks++));
    final gesture = await tester.startGesture(const Offset(300, 250));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(platform.seeks, isEmpty);
    expect(platform.pauses, isEmpty);
    expect(platform.plays, isEmpty);
    expect(userSeeks, 0);
    expect(video.value.position, const Duration(seconds: 15));
    expect(video.value.isPlaying, isTrue);
    await _disposeVideo(tester, video);
  });

  testWidgets('cancelling a second pointer does not cancel the active swipe',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    await tester.pumpWidget(_gestureApp(video));
    final first =
        await tester.startGesture(const Offset(300, 250), pointer: 11);
    await first.moveBy(const Offset(30, 0));
    await first.moveBy(const Offset(100, 0));
    final second =
        await tester.startGesture(const Offset(500, 250), pointer: 12);
    await second.cancel();
    await tester.pump();
    expect(platform.seeks, isEmpty);
    await first.up();
    await tester.pump(const Duration(seconds: 1));
    expect(platform.seeks.length, 1);
    expect(video.value.isPlaying, isTrue);
    await _disposeVideo(tester, video);
  });

  for (final interruption in ['disabled', 'unmounted', 'replaced']) {
    testWidgets(
        'late seek after $interruption never resumes or affects new video',
        (tester) async {
      final platform = _installGesturePlatform();
      final first = await _playingVideo(platform);
      final second = await _playingVideo(platform, speed: 1.5);
      var oldUserSeeks = 0;
      var newUserSeeks = 0;
      var activeSeeks = 0;
      var releases = 0;
      await tester.pumpWidget(
        _gestureApp(
          first,
          onUserSeek: () => oldUserSeeks++,
          onSeekStarted: () {
            activeSeeks++;
            return () {
              activeSeeks--;
              releases++;
            };
          },
        ),
      );
      final delayedSeek = Completer<void>();
      platform.nextSeek = delayedSeek;
      await tester.dragFrom(const Offset(300, 250), const Offset(130, 0));
      await tester.pump();
      expect(platform.seeks.length, 1);
      expect(oldUserSeeks, 1);
      expect(activeSeeks, 1);
      await first.pause();
      if (interruption == 'unmounted') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        await tester.pumpWidget(
          _gestureApp(
            interruption == 'replaced' ? second : first,
            enabled: interruption != 'disabled',
            onUserSeek: () => newUserSeeks++,
          ),
        );
      }
      expect(activeSeeks, 0);
      delayedSeek.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(platform.seeks.length, 1);
      expect(platform.seeks.single.$1, first.playerId);
      expect(platform.plays, isEmpty);
      expect(first.value.isPlaying, isFalse);
      expect(second.value.position, const Duration(seconds: 15));
      expect(newUserSeeks, 0);
      expect(activeSeeks, 0);
      expect(releases, 1);
      expect(tester.takeException(), isNull);
      await _disposeVideo(tester, first);
      await _disposeVideo(tester, second);
    });
  }

  testWidgets('disabling an active swipe cancels it without seeking',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    await tester.pumpWidget(_gestureApp(video));
    final gesture = await tester.startGesture(const Offset(300, 250));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await tester.pumpWidget(_gestureApp(video, enabled: false));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.seeks, isEmpty);
    expect(platform.plays, isEmpty);
    expect(platform.pauses, isEmpty);
    await _disposeVideo(tester, video);
  });

  testWidgets(
      'seek scope spans drag and native seek without releasing newer drag',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    var activeSeeks = 0;
    var releases = 0;
    await tester.pumpWidget(
      _gestureApp(
        video,
        onSeekStarted: () {
          activeSeeks++;
          return () {
            activeSeeks--;
            releases++;
          };
        },
      ),
    );
    final detector = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(VideoGestureSurface),
        matching: find.byType(GestureDetector),
      ),
    );
    detector.onHorizontalDragStart!(DragStartDetails());
    await tester.pump(const Duration(seconds: 2));
    expect(activeSeeks, 1);
    final pending = Completer<void>();
    platform.nextSeek = pending;
    detector.onHorizontalDragEnd!(DragEndDetails());
    await tester.pump();
    expect(activeSeeks, 1);
    detector.onHorizontalDragStart!(DragStartDetails());
    expect(activeSeeks, 2);
    pending.complete();
    await tester.pump();
    expect(activeSeeks, 1);
    detector.onHorizontalDragCancel!();
    expect(activeSeeks, 0);
    expect(releases, 2);
    await _disposeVideo(tester, video);
  });

  testWidgets('double-tap seek owns a scope until native completion',
      (tester) async {
    final platform = _installGesturePlatform();
    final video = await _playingVideo(platform);
    var activeSeeks = 0;
    await tester.pumpWidget(
      _gestureApp(
        video,
        onSeekStarted: () {
          activeSeeks++;
          return () => activeSeeks--;
        },
      ),
    );
    final pending = Completer<void>();
    platform.nextSeek = pending;
    await tester.tapAt(const Offset(500, 250));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(500, 250));
    await tester.pump();
    expect(platform.seeks, [(video.playerId, const Duration(seconds: 18))]);
    expect(activeSeeks, 1);
    pending.complete();
    await tester.pump();
    expect(activeSeeks, 0);
    expect(platform.plays, isEmpty);
    await tester.pump(const Duration(milliseconds: 50));
    await _disposeVideo(tester, video);
  });

  for (final disabled in [false, true]) {
    testWidgets('natural end during drag resumes only while allowed: $disabled',
        (tester) async {
      final platform = _installGesturePlatform();
      final video = await _playingVideo(platform);
      var resumeRequests = 0;
      Future<void> resume() async {
        resumeRequests++;
        await video.play();
      }

      await tester.pumpWidget(_gestureApp(video, onResume: resume));
      final detector = tester.widget<GestureDetector>(
        find.descendant(
          of: find.byType(VideoGestureSurface),
          matching: find.byType(GestureDetector),
        ),
      );
      detector.onHorizontalDragStart!(DragStartDetails());
      await video.pause();
      video.value = video.value.copyWith(
        isCompleted: true,
        position: video.value.duration,
      );
      final pending = Completer<void>();
      platform.nextSeek = pending;
      detector.onHorizontalDragEnd!(DragEndDetails());
      await tester.pump();
      if (disabled) {
        await tester
            .pumpWidget(_gestureApp(video, enabled: false, onResume: resume));
      }
      expect(resumeRequests, 0);
      pending.complete();
      await tester.pump();
      expect(resumeRequests, disabled ? 0 : 1);
      expect(platform.plays.length, disabled ? 0 : 1);
      expect(video.value.isPlaying, !disabled);
      expect(platform.seeks, [(video.playerId, const Duration(seconds: 15))]);
      await _disposeVideo(tester, video);
    });
  }

  testWidgets('progress scrub seeks once when released', (tester) async {
    final seeks = <Duration>[];
    const value = VideoPlayerValue(
      duration: Duration(minutes: 2),
      position: Duration(seconds: 15),
      isInitialized: true,
      isPlaying: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VideoBottomControls(
            value: value,
            landscape: false,
            fitMode: VideoFitMode.fit,
            hasPrevious: false,
            hasNext: false,
            onPrevious: () {},
            onSeek: (position) async => seeks.add(position),
            onPlayPause: () {},
            onNext: () {},
            onToggleOrientation: () {},
            onChooseFit: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(15000);
    slider.onChanged!(30000);
    await tester.pump();

    expect(seeks, isEmpty);
    expect(find.text('0:30/2:00'), findsOneWidget);

    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(30000);
    await tester.pump();

    expect(seeks, [const Duration(seconds: 30)]);
  });

  testWidgets('progress scrub throttles and shows the latest frame preview', (
    tester,
  ) async {
    final requests = <Duration>[];
    final responses = <Completer<Uint8List>>[];
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
    );
    final previews = VideoPreviewCoordinator(
      load: (position) {
        requests.add(position);
        final response = Completer<Uint8List>();
        responses.add(response);
        return response.future;
      },
    );
    addTearDown(previews.dispose);
    const value = VideoPlayerValue(
      duration: Duration(minutes: 2),
      position: Duration(seconds: 15),
      isInitialized: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VideoBottomControls(
            value: value,
            landscape: false,
            fitMode: VideoFitMode.fit,
            hasPrevious: false,
            hasNext: false,
            onPrevious: () {},
            onSeek: (_) async {},
            onPlayPause: () {},
            onNext: () {},
            onToggleOrientation: () {},
            onChooseFit: () {},
            onOpenSettings: () {},
            onPreviewFrameRequested: previews.requestFrame,
          ),
        ),
      ),
    );

    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(15000);
    slider.onChanged!(30000);
    slider.onChanged!(45000);
    slider.onChanged!(60000);
    await tester.pump(const Duration(milliseconds: 109));
    expect(requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, [const Duration(seconds: 60)]);
    responses.single.complete(png);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('video-frame-preview')), findsOneWidget);
    expect(find.text('1:00/2:00'), findsWidgets);

    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(60000);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('video-frame-preview')), findsNothing);
  });

  testWidgets('video controls hide three seconds after interaction ends', (
    tester,
  ) async {
    var visible = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => AutoHideVideoControls(
            enabled: true,
            visible: visible,
            onHide: () => setState(() => visible = false),
            child: const ColoredBox(
              color: Colors.black,
              child: Center(child: Text('Controls')),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Controls')),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(visible, isTrue);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 2999));
    expect(visible, isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    expect(visible, isFalse);
  });

  testWidgets('landscape controls retain progress without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const value = VideoPlayerValue(
      duration: Duration(minutes: 2),
      position: Duration(seconds: 15),
      isInitialized: true,
      isPlaying: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: VideoBottomControls(
              value: value,
              landscape: true,
              fitMode: VideoFitMode.fit,
              hasPrevious: true,
              hasNext: true,
              onPrevious: () {},
              onSeek: (_) async {},
              onPlayPause: () {},
              onNext: () {},
              onToggleOrientation: () {},
              onChooseFit: () {},
              onOpenSettings: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('0:15/2:00'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.screen_rotation), findsOneWidget);
    expect(find.byIcon(Icons.fit_screen), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps transport above the complete bottom toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const value = VideoPlayerValue(
      duration: Duration(hours: 12),
      position: Duration(hours: 10),
      isInitialized: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              VideoTransportRegion(
                child: VideoTransportControls(
                  value: value,
                  hasPrevious: true,
                  hasNext: true,
                  onPrevious: () {},
                  onPlayPause: () {},
                  onNext: () {},
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: VideoBottomControls(
                  value: value,
                  landscape: true,
                  fitMode: VideoFitMode.bestFit,
                  hasPrevious: true,
                  hasNext: true,
                  onPrevious: () {},
                  onSeek: (_) async {},
                  onPlayPause: () {},
                  onNext: () {},
                  onToggleOrientation: () {},
                  onChooseFit: () {},
                  onOpenSettings: () {},
                  onOpenTracks: () {},
                  onPictureInPicture: () {},
                  showTransport: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('10:00:00/12:00:00'), findsOneWidget);
    expect(find.byTooltip('Audio and subtitles'), findsOneWidget);
    expect(find.byTooltip('Picture in picture'), findsOneWidget);
    final transport = tester.getRect(find.byType(VideoTransportControls));
    final timeline = tester.getRect(find.byType(Slider));
    expect(transport.bottom, lessThanOrEqualTo(timeline.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('player settings remain usable on a short landscape screen', (
    tester,
  ) async {
    double? selectedSpeed;
    tester.view.physicalSize = const Size(480, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showVideoSettingsSheet(
                  context,
                  seekSeconds: 3,
                  onSeekSecondsChanged: (_) {},
                  dragSeekSeconds: 600,
                  onDragSeekSecondsChanged: (_) {},
                  playbackSpeed: 1,
                  onPlaybackSpeedChanged: (speed) async {
                    selectedSpeed = speed;
                  },
                  muted: false,
                  onMutedChanged: (_) {},
                  looping: false,
                  onLoopingChanged: (_) {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Player settings'), findsOneWidget);
    expect(find.text('Double-tap seek'), findsOneWidget);
    expect(find.text('Drag seek'), findsOneWidget);
    expect(find.text('10m'), findsOneWidget);
    expect(find.text('Playback speed'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1.5);
    await tester.pump();

    expect(selectedSpeed, 1.5);
    expect(find.text('1.5x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player settings expose heart rating instead of the playbar', (
    tester,
  ) async {
    var rating = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showVideoSettingsSheet(
                  context,
                  seekSeconds: 3,
                  onSeekSecondsChanged: (_) {},
                  dragSeekSeconds: 600,
                  onDragSeekSecondsChanged: (_) {},
                  playbackSpeed: 1,
                  onPlaybackSpeedChanged: (_) async {},
                  muted: false,
                  onMutedChanged: (_) {},
                  rating: rating,
                  onRatingChanged: (next) => rating = next,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Rate'), findsOneWidget);
    expect(find.byType(HeartRatingBar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite).last);
    await tester.pump();

    expect(rating, 0);
  });

  testWidgets('touch lock blocks seek, volume, brightness and long press',
      (tester) async {
    final video = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    video.value = video.value.copyWith(
      duration: const Duration(minutes: 2),
      position: const Duration(seconds: 30),
      playbackSpeed: 1.25,
    );
    addTearDown(video.dispose);
    final display = _FakeDisplayControls();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoGestureSurface(
          controller: video,
          seekSeconds: 3,
          enabled: false,
          displayControls: display,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 200));
    await tester.tapAt(const Offset(100, 200));
    await tester.dragFrom(const Offset(100, 250), const Offset(200, 0));
    await tester.dragFrom(const Offset(100, 250), const Offset(0, -100));
    await tester.dragFrom(const Offset(700, 250), const Offset(0, -100));
    await tester.longPressAt(const Offset(400, 200));
    expect(video.value.position, const Duration(seconds: 30));
    expect(video.value.playbackSpeed, 1.25);
    expect(display.brightnessWrites, isEmpty);
    expect(display.volumeWrites, isEmpty);
    expect(taps, 0);
  });

  testWidgets('left vertical swipe changes brightness', (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);
    final display = _FakeDisplayControls(brightness: 0.4, volume: 0.6);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 800,
          child: VideoGestureSurface(
            controller: controller,
            seekSeconds: 3,
            onTap: () {},
            displayControls: display,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(80, 500), const Offset(0, -200));
    await tester.pump();

    expect(display.brightnessWrites, isNotEmpty);
    expect(display.brightnessWrites.last, closeTo(0.65, 0.05));
    expect(display.volumeWrites, isEmpty);
    expect(find.byKey(const Key('video-level-feedback')), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('right vertical swipe changes volume', (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);
    final display = _FakeDisplayControls(brightness: 0.4, volume: 0.6);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 800,
          child: VideoGestureSurface(
            controller: controller,
            seekSeconds: 3,
            onTap: () {},
            displayControls: display,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(320, 400), const Offset(0, 200));
    await tester.pump();

    expect(display.volumeWrites, isNotEmpty);
    expect(display.volumeWrites.last, closeTo(0.35, 0.05));
    expect(display.brightnessWrites, isEmpty);
    expect(find.byKey(const Key('video-level-feedback')), findsOneWidget);

    await tester.pumpAndSettle();
  });

  test('videoPlaybackEnded treats completed and near-end positions as finished',
      () {
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(duration: Duration.zero),
      ),
      isFalse,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(milliseconds: 200),
          isInitialized: true,
        ),
      ),
      isFalse,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(milliseconds: 200),
          isInitialized: true,
          isCompleted: true,
        ),
      ),
      isTrue,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          isInitialized: true,
          isCompleted: true,
        ),
      ),
      isTrue,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(milliseconds: 9700),
          isInitialized: true,
          isPlaying: true,
        ),
      ),
      isTrue,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(milliseconds: 9700),
          isInitialized: true,
        ),
      ),
      isFalse,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 10),
          isInitialized: true,
        ),
      ),
      isTrue,
    );
    expect(
      videoPlaybackEnded(
        const VideoPlayerValue(
          duration: Duration(seconds: 10),
          position: Duration(seconds: 5),
          isInitialized: true,
          isPlaying: true,
        ),
      ),
      isFalse,
    );
  });

  test('shouldAdvanceFolderVideoOnEnd respects lock, loop, and recent seeks',
      () {
    const ended = VideoPlayerValue(
      duration: Duration(seconds: 10),
      isInitialized: true,
      isCompleted: true,
    );
    expect(
      shouldAdvanceFolderVideoOnEnd(
        value: ended,
        looping: false,
        vaultUnlocked: true,
        isCurrentItem: true,
        alreadyAdvanced: false,
      ),
      isTrue,
    );
    expect(
      shouldAdvanceFolderVideoOnEnd(
        value: ended,
        looping: false,
        vaultUnlocked: false,
        isCurrentItem: true,
        alreadyAdvanced: false,
      ),
      isFalse,
    );
    expect(
      shouldAdvanceFolderVideoOnEnd(
        value: ended,
        looping: true,
        vaultUnlocked: true,
        isCurrentItem: true,
        alreadyAdvanced: false,
      ),
      isFalse,
    );
    expect(
      shouldAdvanceFolderVideoOnEnd(
        value: ended,
        looping: false,
        vaultUnlocked: true,
        isCurrentItem: true,
        alreadyAdvanced: false,
        ignoreUntil: DateTime(2026, 1, 1, 0, 0, 1),
        now: DateTime(2026, 1, 1),
      ),
      isFalse,
    );
    expect(
      shouldAdvanceFolderVideoOnEnd(
        value: ended,
        looping: false,
        vaultUnlocked: true,
        isCurrentItem: true,
        alreadyAdvanced: false,
        ignoreUntil: DateTime(2026, 1, 1),
        now: DateTime(2026, 1, 1, 0, 0, 1),
      ),
      isTrue,
    );
  });

  test('nextIndexAfterVideoEnd follows sort order and stops at the end', () {
    expect(
      nextIndexAfterVideoEnd(
        index: 0,
        length: 3,
        looping: false,
        ended: true,
      ),
      1,
    );
    expect(
      nextIndexAfterVideoEnd(
        index: 2,
        length: 3,
        looping: false,
        ended: true,
      ),
      isNull,
    );
    expect(
      nextIndexAfterVideoEnd(
        index: 0,
        length: 3,
        looping: true,
        ended: true,
      ),
      isNull,
    );
    expect(
      nextIndexAfterVideoEnd(
        index: 0,
        length: 3,
        looping: false,
        ended: false,
      ),
      isNull,
    );
  });
}
