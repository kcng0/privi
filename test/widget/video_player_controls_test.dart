import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:video_player/video_player.dart';

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
                  onPlaybackSpeedChanged: (_) {},
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
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
