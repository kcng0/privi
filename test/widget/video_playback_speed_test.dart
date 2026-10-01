import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/application/settings/settings_controller.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/video_playback_speed.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

class _SpeedVideo extends VideoPlayerController {
  _SpeedVideo(this.application)
      : super.networkUrl(Uri.parse('https://example.com/video.mp4'));

  final Completer<void> application;
  final calls = <double>[];
  bool applied = false;

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    calls.add(speed);
    // Match video_player's optimistic update before its platform await.
    value = value.copyWith(playbackSpeed: speed);
    if (speed != 1) {
      await application.future;
      applied = true;
    }
  }
}

void main() {
  for (final reject in [false, true]) {
    testWidgets(
      reject
          ? 'rejected speed restores facade and selection without saving'
          : 'speed selection and preference wait for native acceptance',
      (tester) async {
        SharedPreferences.setMockInitialValues({'player_playback_speed': 1.0});
        final preferences = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        );
        addTearDown(container.dispose);
        final application = Completer<void>();
        final video = _SpeedVideo(application);
        addTearDown(video.dispose);
        final settings = container.read(settingsControllerProvider.notifier);
        bool? persistedAfterAcceptance;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showVideoSettingsSheet(
                    context,
                    seekSeconds: 3,
                    onSeekSecondsChanged: (_) {},
                    dragSeekSeconds: 600,
                    onDragSeekSecondsChanged: (_) {},
                    playbackSpeed: 1,
                    onPlaybackSpeedChanged: (speed) => updateVideoPlaybackSpeed(
                      controller: video,
                      speed: speed,
                      previousSpeed: 1,
                      isCurrent: () => true,
                      persist: () {
                        persistedAfterAcceptance = video.applied;
                        return settings.setPlayerPlaybackSpeed(speed);
                      },
                    ),
                    muted: false,
                    onMutedChanged: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
        await tester.pump();
        expect(find.text('1x'), findsOneWidget);
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
        expect(preferences.getDouble('player_playback_speed'), 1);
        expect(
          container.read(settingsControllerProvider).playerPlaybackSpeed,
          1,
        );

        if (reject) {
          application.completeError(StateError('Native speed rejected: 4x'));
        } else {
          application.complete();
        }
        await tester.pumpAndSettle();
        if (reject) {
          expect(persistedAfterAcceptance, isNull);
          expect(video.calls, [4, 1]);
          expect(video.value.playbackSpeed, 1);
          expect(find.text('1x'), findsOneWidget);
          expect(
            find.textContaining('Native speed rejected: 4x'),
            findsOneWidget,
          );
          expect(preferences.getDouble('player_playback_speed'), 1);
          expect(
            container.read(settingsControllerProvider).playerPlaybackSpeed,
            1,
          );
        } else {
          expect(find.textContaining('Error:'), findsNothing);
          expect(persistedAfterAcceptance, isTrue);
          expect(video.calls, [4]);
          expect(video.value.playbackSpeed, 4);
          expect(find.text('4x'), findsOneWidget);
          expect(preferences.getDouble('player_playback_speed'), 4);
          expect(
            container.read(settingsControllerProvider).playerPlaybackSpeed,
            4,
          );
        }
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
