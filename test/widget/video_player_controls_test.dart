import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:video_player/video_player.dart';

const _longPressDuration = Duration(milliseconds: 500);

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
    expect(formatVideoDelta(const Duration(seconds: -3)), '-0:03');
    expect(formatPlaybackSpeed(1), '1x');
    expect(formatPlaybackSpeed(1.25), '1.25x');
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

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(VideoGestureSurface)));
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

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(VideoGestureSurface)));
    await tester.pump(_longPressDuration);
    expect(controller.value.playbackSpeed, 2);

    await gesture.cancel();
    await tester.pump();

    expect(controller.value.playbackSpeed, 1);
    expect(find.text('2x'), findsNothing);
  });

  testWidgets('landscape controls hide time labels without overflowing',
      (tester) async {
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
              title: 'clip-03.mp4',
              playlistPosition: 3,
              playlistLength: 25,
              hasPrevious: true,
              hasNext: true,
              onPrevious: () {},
              onSeek: (_) {},
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
    expect(find.text('clip-03.mp4'), findsOneWidget);
    expect(find.text('3/25'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.stay_current_portrait), findsOneWidget);
    expect(find.byIcon(Icons.fit_screen), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player settings remain usable on a short landscape screen',
      (tester) async {
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
}
