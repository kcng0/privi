import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/advanced_video_controller.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/video_advanced_controls.dart';
import 'package:video_player/video_player.dart';

class _Port extends ValueNotifier<AdvancedVideoState>
    implements AdvancedVideoPort {
  _Port(super.value);
  String? audio;
  String? subtitle;
  Duration? start;
  Duration? end;
  bool fail = false;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> selectAudioTrack(String id) async {
    audio = id;
  }

  @override
  Future<void> selectSubtitleTrack(String id) async {
    subtitle = id;
  }

  @override
  Future<void> importSubtitle(String path) async {}
  @override
  Future<void> setAudioDelay(Duration delay) async {
    if (fail) throw StateError('Audio delay rejected by player');
    value = value.copyWith(audioDelay: delay);
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    value = value.copyWith(subtitleDelay: delay);
  }

  @override
  Future<void> setAbLoop(Duration? a, Duration? b) async {
    start = a;
    end = b;
    value = value.copyWith(abLoopStart: a, abLoopEnd: b, clearAbLoop: true);
  }
}

Widget _app(AdvancedVideoController advanced, VideoPlayerController video) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showVideoAdvancedSheet(
              context,
              advanced: advanced,
              controller: video,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'track selection, subtitles off, signed delay and AB use the active engine',
      (tester) async {
    tester.view.physicalSize = const Size(700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _Port(
      const AdvancedVideoState(
        supportsAudioTracks: true,
        supportsSubtitles: true,
        supportsAudioDelay: true,
        supportsSubtitleDelay: true,
        supportsAbLoop: true,
        audioTracks: [
          AdvancedVideoTrack(id: '1', title: 'English', language: 'en'),
        ],
        subtitleTracks: [
          AdvancedVideoTrack(
            id: '2',
            title: 'Chinese',
            language: 'zh',
            isSelected: true,
          ),
        ],
      ),
    );
    final video = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    video.value = video.value.copyWith(position: const Duration(seconds: 10));
    final advanced = AdvancedVideoController(video, port: port);
    addTearDown(() async {
      advanced.dispose();
      port.dispose();
      await video.dispose();
    });
    await tester.pumpWidget(_app(advanced, video));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(port.audio, '1');
    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subtitles off'));
    await tester.pumpAndSettle();
    expect(port.subtitle, 'no');
    await tester.tap(find.text('Audio delay'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-250');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(port.value.audioDelay, const Duration(milliseconds: -250));
    await tester.ensureVisible(find.text('Set A here'));
    await tester.tap(find.text('Set A here'));
    await tester.pumpAndSettle();
    expect(port.start, const Duration(seconds: 10));
    video.value = video.value.copyWith(position: const Duration(seconds: 25));
    await tester.tap(find.text('Set B here'));
    await tester.pumpAndSettle();
    expect(port.end, const Duration(seconds: 25));
    await tester.tap(find.text('Clear A–B'));
    await tester.pumpAndSettle();
    expect(port.start, isNull);
    expect(port.end, isNull);
  });

  testWidgets(
      'unsupported controls are absent and player errors remain visible',
      (tester) async {
    final video = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    final port = _Port(const AdvancedVideoState());
    final advanced = AdvancedVideoController(video, port: port);
    addTearDown(() async {
      advanced.dispose();
      port.dispose();
      await video.dispose();
    });
    await tester.pumpWidget(_app(advanced, video));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Open subtitle file'), findsNothing);
    expect(find.text('Audio delay'), findsNothing);
    expect(
      find.text('Advanced playback is unavailable on this player.'),
      findsOneWidget,
    );
    port.value = const AdvancedVideoState(supportsAudioDelay: true);
    port.fail = true;
    await tester.pump();
    await tester.tap(find.text('Audio delay'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '150');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Audio delay rejected by player'),
      findsOneWidget,
    );
  });
}
