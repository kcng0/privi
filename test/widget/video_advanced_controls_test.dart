import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _DiagnosticsPort extends _Port implements VideoPlaybackDiagnosticsPort {
  _DiagnosticsPort() : super(const AdvancedVideoState());

  final diagnostics = const {'decoder': 'h264', 'speed': '1.5'};
  int diagnosticsReads = 0;
  Object? diagnosticsError;
  Completer<Map<String, String>>? diagnosticsGate;

  @override
  Future<Map<String, String>> readPlaybackDiagnostics() async {
    diagnosticsReads++;
    final error = diagnosticsError;
    if (error != null) throw error;
    return diagnosticsGate == null
        ? diagnostics
        : await diagnosticsGate!.future;
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
  group('playback diagnostics', () {
    const copyKey = ValueKey('video-copy-playback-diagnostics');
    late _DiagnosticsPort port;
    late VideoPlayerController video;
    late AdvancedVideoController advanced;
    late List<String> clipboardWrites;
    var controllerDisposed = false;

    setUp(() {
      port = _DiagnosticsPort();
      video = VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/video.mp4'),
      );
      advanced = AdvancedVideoController(video, port: port);
      controllerDisposed = false;
      clipboardWrites = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    tearDown(() async {
      if (!controllerDisposed) advanced.dispose();
      port.dispose();
      await video.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(_app(advanced, video));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('opening the sheet does not read or copy diagnostics',
        (tester) async {
      await openSheet(tester);
      expect(find.byKey(copyKey), findsOneWidget);
      expect(port.diagnosticsReads, 0);
      expect(clipboardWrites, isEmpty);
      expect(find.text('Playback diagnostics copied'), findsNothing);
      expect(
        find.text('Advanced playback is unavailable on this player.'),
        findsNothing,
      );
    });

    testWidgets('one tap copies the snapshot as JSON and confirms success',
        (tester) async {
      await openSheet(tester);
      await tester.tap(find.byKey(copyKey));
      await tester.pumpAndSettle();
      expect(port.diagnosticsReads, 1);
      expect(clipboardWrites, hasLength(1));
      expect(jsonDecode(clipboardWrites.single), port.diagnostics);
      expect(find.text('Playback diagnostics copied'), findsOneWidget);
    });

    testWidgets('rapid repeated taps read once while busy', (tester) async {
      port.diagnosticsGate = Completer<Map<String, String>>();
      await openSheet(tester);
      await tester.tap(find.byKey(copyKey));
      await tester.tap(find.byKey(copyKey));
      await tester.pump();
      expect(port.diagnosticsReads, 1);
      expect(tester.widget<ListTile>(find.byKey(copyKey)).onTap, isNull);
      expect(clipboardWrites, isEmpty);
      port.diagnosticsGate!.complete(port.diagnostics);
      await tester.pumpAndSettle();
      expect(clipboardWrites, hasLength(1));
    });

    testWidgets('read failures show an error without copying or success',
        (tester) async {
      port.diagnosticsError = StateError('Native diagnostics read failed');
      await openSheet(tester);
      await tester.tap(find.byKey(copyKey));
      await tester.pumpAndSettle();
      expect(port.diagnosticsReads, 1);
      expect(clipboardWrites, isEmpty);
      expect(find.text('Playback diagnostics copied'), findsNothing);
      expect(
        find.textContaining('Native diagnostics read failed'),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(find.byKey(copyKey)).onTap, isNotNull);
    });

    for (final finishDismissal in [false, true]) {
      testWidgets(
          'a ${finishDismissal ? 'dismissed' : 'dismissing'} sheet cannot copy a late result',
          (tester) async {
        port.diagnosticsGate = Completer<Map<String, String>>();
        await openSheet(tester);
        await tester.tap(find.byKey(copyKey));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        if (finishDismissal) await tester.pumpAndSettle();
        port.diagnosticsGate!.complete(port.diagnostics);
        await tester.pumpAndSettle();
        expect(clipboardWrites, isEmpty);
        expect(find.text('Playback diagnostics copied'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('controller disposal during a read prevents late copying',
        (tester) async {
      port.diagnosticsGate = Completer<Map<String, String>>();
      await openSheet(tester);
      await tester.tap(find.byKey(copyKey));
      await tester.pump();
      // The sheet normally leaves the tree before its controller is disposed.
      await tester.pumpWidget(const SizedBox.shrink());
      advanced.dispose();
      controllerDisposed = true;
      port.diagnosticsGate!.complete(port.diagnostics);
      await tester.pump();
      expect(clipboardWrites, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

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
      find.byKey(const ValueKey('video-copy-playback-diagnostics')),
      findsNothing,
    );
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
