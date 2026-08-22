import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  test('swipe seek follows direction, magnitude, and duration limits', () {
    const duration = Duration(minutes: 20);

    final precise = videoSwipeSeekDelta(
      horizontalDelta: 50,
      viewportWidth: 1000,
      duration: duration,
      minimumSeconds: 3,
    );
    final medium = videoSwipeSeekDelta(
      horizontalDelta: 500,
      viewportWidth: 1000,
      duration: duration,
      minimumSeconds: 3,
    );
    final reverse = videoSwipeSeekDelta(
      horizontalDelta: -500,
      viewportWidth: 1000,
      duration: duration,
      minimumSeconds: 3,
    );
    final maximum = videoSwipeSeekDelta(
      horizontalDelta: 1000,
      viewportWidth: 1000,
      duration: duration,
      minimumSeconds: 3,
    );
    final shortVideoMaximum = videoSwipeSeekDelta(
      horizontalDelta: 1000,
      viewportWidth: 1000,
      duration: const Duration(minutes: 2),
      minimumSeconds: 3,
    );

    expect(precise.inMilliseconds, closeTo(3004, 1));
    expect(medium.inMilliseconds, 40313);
    expect(reverse.inMilliseconds, -40313);
    expect(maximum, const Duration(minutes: 10));
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

  test('video size picks landscape or portrait lock', () {
    expect(preferredOrientationsForVideo(const Size(1920, 1080)), [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    expect(preferredOrientationsForVideo(const Size(1080, 1920)), [
      DeviceOrientation.portraitUp,
    ]);
    expect(preferredOrientationsForVideo(const Size(1080, 1080)), [
      DeviceOrientation.portraitUp,
    ]);
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
            onPreviewFrameRequested: (position) {
              requests.add(position);
              final response = Completer<Uint8List>();
              responses.add(response);
              return response.future;
            },
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

  testWidgets('landscape controls hide time labels without overflowing', (
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

    expect(find.text('0:15'), findsNothing);
    expect(find.text('2:00'), findsNothing);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.stay_current_portrait), findsOneWidget);
    expect(find.byIcon(Icons.fit_screen), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
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
                  playbackSpeed: 1,
                  onPlaybackSpeedChanged: (speed) => selectedSpeed = speed,
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
                  playbackSpeed: 1,
                  onPlaybackSpeedChanged: (_) {},
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
