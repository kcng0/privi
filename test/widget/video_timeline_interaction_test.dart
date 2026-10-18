import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/video_preview_coordinator.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:video_player/video_player.dart';

Widget _timeline({
  required Future<void> Function(Duration) seek,
  VideoPreviewCoordinator? previews,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: VideoBottomControls(
          value: const VideoPlayerValue(
            duration: Duration(minutes: 2),
            position: Duration(seconds: 15),
            isInitialized: true,
            isPlaying: true,
          ),
          landscape: false,
          fitMode: VideoFitMode.fit,
          hasPrevious: false,
          hasNext: false,
          onPrevious: () {},
          onSeek: seek,
          onPlayPause: () {},
          onNext: () {},
          onToggleOrientation: () {},
          onChooseFit: () {},
          onOpenSettings: () {},
          onPreviewFrameRequested: previews?.requestFrame,
          onPreviewCancelled: previews?.clear,
        ),
      ),
    );

void main() {
  testWidgets(
      'release clears visible and queued previews before seek completes',
      (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    final targets = <Duration>[];
    final frames = <Completer<Uint8List?>>[];
    final previews = VideoPreviewCoordinator(
      delay: const Duration(milliseconds: 1),
      load: (position) {
        targets.add(position);
        final frame = Completer<Uint8List?>();
        frames.add(frame);
        return frame.future;
      },
    );
    addTearDown(previews.dispose);
    final seek = Completer<void>();
    final seeks = <Duration>[];
    await tester.pumpWidget(
      _timeline(
        previews: previews,
        seek: (position) {
          seeks.add(position);
          return seek.future;
        },
      ),
    );
    Slider slider() => tester.widget<Slider>(find.byType(Slider));
    slider().onChangeStart!(15000);
    slider().onChanged!(30000);
    await tester.pump(const Duration(milliseconds: 1));
    frames.first.complete(png);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('video-frame-preview')), findsOneWidget);

    slider().onChanged!(45000);
    await tester.pump(const Duration(milliseconds: 1));
    slider().onChanged!(60000);
    slider().onChangeEnd!(60000);
    await tester.pump();
    expect(seeks, [const Duration(seconds: 60)]);
    expect(find.byKey(const Key('video-frame-preview')), findsNothing);
    expect(slider().value, 60000);
    expect(find.text('1:00/2:00'), findsOneWidget);

    frames.last.complete(png);
    await tester.pump(const Duration(seconds: 1));
    expect(targets, [const Duration(seconds: 30), const Duration(seconds: 45)]);
    expect(find.byKey(const Key('video-frame-preview')), findsNothing);
    seek.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an earlier seek completion preserves a newer active scrub',
      (tester) async {
    final seeks = <Completer<void>>[];
    await tester.pumpWidget(
      _timeline(
        seek: (_) {
          final seek = Completer<void>();
          seeks.add(seek);
          return seek.future;
        },
      ),
    );
    Slider slider() => tester.widget<Slider>(find.byType(Slider));
    slider().onChangeStart!(15000);
    slider().onChanged!(45000);
    slider().onChangeEnd!(45000);
    await tester.pump();
    slider().onChangeStart!(45000);
    slider().onChanged!(80000);
    seeks.first.complete();
    await tester.pump();
    expect(slider().value, 80000);
    expect(find.text('1:20/2:00'), findsOneWidget);
    slider().onChangeEnd!(80000);
    seeks.last.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
