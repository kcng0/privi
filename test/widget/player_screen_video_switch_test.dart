import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/player/player_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/player_screen.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:privi/presentation/viewer/viewer_screen.dart';
import 'package:privi/presentation/visible/gallery_preview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

final class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}

final class _SerialProbeVideoPlatform extends VideoPlayerPlatform {
  final StreamController<VideoEvent> _firstPlayerEvents =
      StreamController<VideoEvent>.broadcast();
  final Set<int> activePlayers = {};

  int createCalls = 0;
  int playCalls = 0;
  int maxActivePlayers = 0;
  int _nextPlayerId = 0;

  VideoEvent get _initializedEvent => VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 1),
        size: const Size(1920, 1080),
      );

  void initializeFirstPlayer() {
    _firstPlayerEvents.add(_initializedEvent);
  }

  void completeFirstPlayer() {
    _firstPlayerEvents.add(VideoEvent(eventType: VideoEventType.completed));
  }

  Future<void> close() => _firstPlayerEvents.close();

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCalls++;

    final playerId = _nextPlayerId++;
    activePlayers.add(playerId);
    maxActivePlayers = activePlayers.length > maxActivePlayers
        ? activePlayers.length
        : maxActivePlayers;
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (playerId == 0) return _firstPlayerEvents.stream;
    return Stream<VideoEvent>.value(_initializedEvent);
  }

  @override
  Future<void> dispose(int playerId) async {
    activePlayers.remove(playerId);
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => SizedBox(key: ValueKey(playerId));
}

MediaItem _video(String id, String path) => MediaItem(
      id: id,
      privatePath: path,
      originalName: '$id.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      rating: 0,
      dateAdded: DateTime(2026),
      sizeBytes: 1,
    );

Widget _app(
  ProviderContainer container,
  List<MediaItem> items, {
  required bool shuffle,
}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlayerScreen(
          items: items,
          shuffle: shuffle,
          videoFileProbe: (_) => SynchronousFuture<bool>(true),
        ),
      ),
    );

void restoreForeground(WidgetsBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform originalPlatform;
  late _SerialProbeVideoPlatform videoPlatform;
  late ProviderContainer container;
  late Directory videoDirectory;
  late File videoFile;

  setUp(() async {
    videoDirectory =
        await Directory.systemTemp.createTemp('privi-playback-ui-');
    videoFile =
        await File('${videoDirectory.path}/video.mp4').writeAsBytes([0]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.privi.app/orientation'),
      (_) async => null,
    );
    originalPlatform = VideoPlayerPlatform.instance;
    videoPlatform = _SerialProbeVideoPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
    SharedPreferences.setMockInitialValues({'player_external': false});
    final preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
      ],
    );
  });

  tearDown(() async {
    restoreForeground(TestWidgetsFlutterBinding.instance);
    container.dispose();
    VideoPlayerPlatform.instance = originalPlatform;
    await videoPlatform.close();
    await videoDirectory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.privi.app/orientation'),
      null,
    );
  });

  Widget videoApp(String entry) {
    final items = [
      _video('one', videoFile.path),
      _video('two', videoFile.path),
    ];
    final child = switch (entry) {
      'playlist' => PlayerScreen(
          items: items,
          videoFileProbe: (_) => SynchronousFuture<bool>(true),
        ),
      'viewer' => ViewerScreen(items: items, initialIndex: 0),
      _ => GalleryPreviewScreen(
          items: const [
            GalleryAsset(id: 'one', isVideo: true, title: 'one.mp4'),
            GalleryAsset(id: 'two', isVideo: true, title: 'two.mp4'),
          ],
          initialIndex: 0,
          resolveFile: (_) => SynchronousFuture<File?>(videoFile),
        ),
    };
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  Future<void> drain(WidgetTester tester) async {
    // File.exists in the gallery adapter uses real IO; release it without
    // waiting for the deliberately held video initialization future.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  for (final entry in ['playlist', 'viewer', 'gallery']) {
    for (final interruption in ['background', 'lock']) {
      testWidgets('$entry held initialization never starts after $interruption',
          (tester) async {
        await tester.pumpWidget(videoApp(entry));
        await drain(tester);
        expect(videoPlatform.createCalls, 1);
        if (interruption == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        } else {
          container.read(lockControllerProvider.notifier).lock();
        }
        videoPlatform.initializeFirstPlayer();
        await drain(tester);
        expect(videoPlatform.playCalls, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        restoreForeground(tester.binding);
      });

      testWidgets('$entry ignores late completion after $interruption',
          (tester) async {
        await tester.pumpWidget(videoApp(entry));
        await drain(tester);
        videoPlatform.initializeFirstPlayer();
        await drain(tester);
        expect(videoPlatform.playCalls, greaterThan(0));
        final before =
            tester.widget<VideoViewport>(find.byType(VideoViewport)).controller;
        if (interruption == 'background') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        } else {
          container.read(lockControllerProvider.notifier).lock();
        }
        videoPlatform.completeFirstPlayer();
        await drain(tester);
        expect(
          tester.widget<VideoViewport>(find.byType(VideoViewport)).controller,
          same(before),
        );
        if (entry == 'playlist') {
          expect(container.read(playerControllerProvider).current?.id, 'one');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        restoreForeground(tester.binding);
      });
    }
  }

  testWidgets(
      'playlist resumes on the first explicit Play after background pause',
      (tester) async {
    await tester.pumpWidget(videoApp('playlist'));
    await drain(tester);
    videoPlatform.initializeFirstPlayer();
    await drain(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await drain(tester);
    restoreForeground(tester.binding);
    await drain(tester);
    final before = videoPlatform.playCalls;
    expect(find.byTooltip('Play'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await drain(tester);
    expect(videoPlatform.playCalls, before + 1);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final shuffle in [false, true]) {
    testWidgets(
      'rapid Next serializes ${shuffle ? 'shuffle' : 'ordered'} playback',
      (tester) async {
        final stubPath = File('test/fixtures/video_stub.mp4').absolute.path;
        final items = List<MediaItem>.generate(
          7,
          (index) => _video('video-$index', stubPath),
        );

        await tester.pumpWidget(
          _app(container, items, shuffle: shuffle),
        );
        await tester.pump();
        await tester.pump();

        expect(videoPlatform.createCalls, 1);
        final player = container.read(playerControllerProvider.notifier);
        for (var index = 0; index < 5; index++) {
          unawaited(player.next());
        }
        await tester.pump();

        final state = container.read(playerControllerProvider);
        expect(state.playlist?.positionDisplay, 6);
        if (!shuffle) expect(state.current?.id, 'video-5');
        expect(videoPlatform.createCalls, 1);
        expect(videoPlatform.maxActivePlayers, 1);

        videoPlatform.initializeFirstPlayer();
        await tester.pumpWidget(const SizedBox.shrink());
        for (var index = 0; index < 10; index++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(videoPlatform.maxActivePlayers, lessThanOrEqualTo(2));
      },
    );
  }
}
