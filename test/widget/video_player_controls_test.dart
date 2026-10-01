import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/video_preview_coordinator.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/playback_display_service.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/heart_rating_bar.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:video_player/video_player.dart';

const _longPressDuration = Duration(milliseconds: 500);

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

  testWidgets('long press fast-forwards at 2x until release', (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);
    await controller.setPlaybackSpeed(1.25);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoGestureSurface(
          controller: controller,
          seekSeconds: 3,
          onTap: () {},
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VideoGestureSurface)),
    );
    await tester.pump(_longPressDuration);

    expect(controller.value.playbackSpeed, 2);
    expect(find.text('2x'), findsOneWidget);

    await gesture.up();
    await tester.pump();

    expect(controller.value.playbackSpeed, 1.25);
    expect(find.text('2x'), findsNothing);
  });

  testWidgets('cancelled long press restores playback speed', (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoGestureSurface(
          controller: controller,
          seekSeconds: 3,
          onTap: () {},
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VideoGestureSurface)),
    );
    await tester.pump(_longPressDuration);
    expect(controller.value.playbackSpeed, 2);

    await gesture.cancel();
    await tester.pump();

    expect(controller.value.playbackSpeed, 1);
    expect(find.text('2x'), findsNothing);
  });

  testWidgets('drag feedback does not rebuild the video child', (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);
    controller.value = const VideoPlayerValue(
      duration: Duration(minutes: 2),
      position: Duration(seconds: 15),
    );
    var childBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoGestureSurface(
          controller: controller,
          seekSeconds: 3,
          onTap: () {},
          child: Builder(
            builder: (_) {
              childBuilds++;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VideoGestureSurface)),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(childBuilds, 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

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

  testWidgets('seek release delegates resume to the lifecycle owner',
      (tester) async {
    final video = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    video.value = video.value.copyWith(
      duration: const Duration(minutes: 2),
      position: const Duration(seconds: 30),
      isPlaying: true,
    );
    addTearDown(video.dispose);
    var resumeRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoGestureSurface(
          controller: video,
          seekSeconds: 3,
          onTap: () {},
          onResume: () async {
            resumeRequests++;
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.dragFrom(const Offset(200, 250), const Offset(100, 0));
    await tester.pump();
    expect(resumeRequests, 1);
    expect(video.value.isPlaying, isFalse);
    await tester.pump(const Duration(seconds: 1));
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
