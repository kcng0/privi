import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:privi/app.dart';
import 'package:privi/application/gallery/gallery_controller.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/player/advanced_video_controller.dart';
import 'package:privi/application/player/picture_in_picture_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/services/playback/media_kit_video_player_platform.dart';
import 'package:privi/data/services/playback_orientation_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/presentation/player/player_screen.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installVaultVideoPlayer();
  final metrics = <String, dynamic>{};
  final files = <String, File>{};
  late Directory fixtures;
  var screenshotReady = false;

  setUp(() => screenshotReady = false);

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!screenshotReady) {
      // integration_test automatically restores this surface after each test.
      await binding.convertFlutterSurfaceToImage();
      screenshotReady = true;
    }
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  setUpAll(() async {
    fixtures = await Directory('${(await getTemporaryDirectory()).path}/'
            'privi-playback-validation')
        .create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      for (final name in [
        'portrait.mp4',
        'landscape.mp4',
        'rotated.mp4',
        'rotated270.mp4',
        'sar.mp4',
        'portrait.webm',
        'hevc.mkv',
        'av1.mkv',
        'tracks.mkv',
        'chinese.ass',
      ]) {
        final request = await client.getUrl(
          Uri.parse(
            'http://10.0.2.2:8765/$name',
          ),
        );
        final response =
            await request.close().timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw StateError('Fixture $name: HTTP ${response.statusCode}');
        }
        final file = File('${fixtures.path}/$name');
        await response
            .pipe(file.openWrite())
            .timeout(const Duration(seconds: 15));
        files[name] = file;
      }
    } finally {
      client.close(force: true);
    }
    files['corrupt.mp4'] = await File('${fixtures.path}/corrupt.mp4')
        .writeAsString('Intentionally invalid synthetic video fixture.');
  });

  tearDownAll(() async {
    binding.reportData = {...?binding.reportData, ...metrics};
    await fixtures.delete(recursive: true);
  });

  Future<T> pumpOperation<T>(
    WidgetTester tester,
    Future<T> operation, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    var completed = false;
    T? result;
    Object? failure;
    StackTrace? failureStack;
    unawaited(
      operation.then<void>(
        (value) {
          result = value;
          completed = true;
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          completed = true;
        },
      ),
    );
    final watch = Stopwatch()..start();
    while (!completed && watch.elapsed < timeout) {
      // media_kit_video creates its native output after a Flutter frame.
      // Live integration tests must explicitly drive frames during creation.
      await tester
          .pump(const Duration(milliseconds: 100))
          .timeout(timeout - watch.elapsed);
    }
    if (!completed) {
      throw TimeoutException('Native operation exceeded $timeout');
    }
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    return result as T;
  }

  Future<VideoPlayerController> open(WidgetTester tester, String name) async {
    final watch = Stopwatch()..start();
    final controller = VideoPlayerController.file(files[name]!);
    try {
      await pumpOperation(tester, controller.initialize());
      (metrics['initialization_ms'] as List<dynamic>? ??
              (metrics['initialization_ms'] = <dynamic>[]))
          .add({'file': name, 'ms': watch.elapsedMilliseconds});
      return controller;
    } catch (error) {
      debugPrint('Native opening failed for $name: $error');
      try {
        await pumpOperation(
          tester,
          controller.dispose(),
          timeout: const Duration(seconds: 5),
        );
      } catch (cleanupError) {
        debugPrint('Native opening cleanup failed for $name: $cleanupError');
      }
      rethrow;
    }
  }

  Future<void> display(
    WidgetTester tester,
    VideoPlayerController controller, {
    VideoFitMode mode = VideoFitMode.fit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: VideoViewport(controller: controller, fitMode: mode),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'native dimensions and Best fit preserve portrait and rotation',
    (tester) async {
      final orientation = PlaybackOrientationService();
      await orientation.begin();
      await orientation.setMode('portrait');
      try {
        final cases = <String, double>{
          'portrait.mp4': 180 / 320,
          'rotated.mp4': 180 / 320,
          'rotated270.mp4': 180 / 320,
          'sar.mp4': 640 / 180,
          'portrait.webm': 180 / 320,
          'hevc.mkv': 180 / 320,
          'av1.mkv': 180 / 320,
          'tracks.mkv': 180 / 320,
        };
        for (final entry in cases.entries) {
          final controller = await open(tester, entry.key);
          try {
            expect(
              controller.value.aspectRatio,
              closeTo(entry.value, 0.02),
              reason: '${entry.key} must use actual display dimensions',
            );
            await display(tester, controller);
            final video =
                tester.getRect(find.byKey(const Key('video-display-rect')));
            final viewport = tester.getRect(find.byType(VideoViewport));
            expect(video.width / video.height, closeTo(entry.value, 0.02));
            expect(video.left, greaterThanOrEqualTo(viewport.left - 1));
            expect(video.top, greaterThanOrEqualTo(viewport.top - 1));
            expect(video.right, lessThanOrEqualTo(viewport.right + 1));
            expect(video.bottom, lessThanOrEqualTo(viewport.bottom + 1));
            await controller.play();
            await tester.pump(const Duration(milliseconds: 400));
            expect(controller.value.hasError, isFalse);
            if (['portrait.mp4', 'rotated.mp4', 'rotated270.mp4', 'sar.mp4']
                .contains(entry.key)) {
              await screenshot(tester, 'best-fit-${entry.key}');
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.dispose();
          }
        }
      } finally {
        await orientation.restore();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'a native opening failure can dispose and open another video',
    (tester) async {
      final platform =
          VideoPlayerPlatform.instance as MediaKitVideoPlayerPlatform;
      final failed = VideoPlayerController.file(files['corrupt.mp4']!);
      try {
        Object? openingError;
        try {
          await pumpOperation(tester, failed.initialize());
        } catch (error) {
          openingError = error;
        }
        // Inspect the error after all guarded frame APIs have completed.
        expect(openingError, isA<PlatformException>());
      } finally {
        await failed.dispose().timeout(const Duration(seconds: 5));
      }
      expect(platform.activePlayerCount, 0);
      final next = await open(tester, 'portrait.mp4');
      try {
        await display(tester, next);
        await next.play();
        expect(next.value.hasError, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await next.dispose();
      }
      expect(platform.activePlayerCount, 0);
      metrics['native_failure_recovery'] = 'passed';
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'native audio, ASS subtitles, delays, rate and A-B controls',
    (tester) async {
      final controller = await open(tester, 'tracks.mkv');
      final advanced = AdvancedVideoController(controller);
      try {
        await display(tester, controller);
        await advanced.refresh();
        expect(advanced.value.audioTracks.length, greaterThanOrEqualTo(2));
        expect(
          advanced.value.subtitleTracks.where((track) => track.id != 'no'),
          isNotEmpty,
        );
        await advanced.selectAudioTrack(advanced.value.audioTracks.last.id);
        await advanced.selectSubtitleTrack(
          advanced.value.subtitleTracks
              .firstWhere((track) => track.id != 'no')
              .id,
        );
        await advanced.importSubtitle(files['chinese.ass']!.path);
        await advanced.setAudioDelay(const Duration(milliseconds: 125));
        await advanced.setSubtitleDelay(const Duration(milliseconds: -250));
        expect(advanced.value.audioDelay.inMilliseconds, 125);
        expect(advanced.value.subtitleDelay.inMilliseconds, -250);
        await advanced.setAbLoop(
          const Duration(milliseconds: 500),
          const Duration(milliseconds: 1500),
        );
        expect(advanced.value.abLoopEnd, const Duration(milliseconds: 1500));
        for (final rate in [0.25, 1.0, 4.0]) {
          await controller.setPlaybackSpeed(rate);
          expect(controller.value.playbackSpeed, rate);
        }
        await controller.setPlaybackSpeed(1);
        await controller.seekTo(const Duration(seconds: 1));
        await controller.play();
        await tester.pump(const Duration(milliseconds: 400));
        await screenshot(tester, 'portrait-ass-best-fit');
        await advanced.setAbLoop(null, null);
        expect(advanced.value.abLoopEnd, isNull);
        await advanced.selectSubtitleTrack('no');
        expect(controller.value.hasError, isFalse);
      } finally {
        advanced.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    '100 native controller handoffs release every decoder',
    (tester) async {
      final platform =
          VideoPlayerPlatform.instance as MediaKitVideoPlayerPlatform;
      final switchTimes = <int>[];
      metrics['stress_rss_before_bytes'] = ProcessInfo.currentRss;
      for (var index = 0; index < 100; index++) {
        final timer = Stopwatch()..start();
        final controller =
            await open(tester, index.isEven ? 'portrait.mp4' : 'landscape.mp4');
        try {
          expect(platform.activePlayerCount, 1);
          await display(tester, controller);
          await controller.play();
          await tester.pump(const Duration(milliseconds: 30));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.dispose();
        }
        expect(platform.activePlayerCount, 0);
        switchTimes.add(timer.elapsedMilliseconds);
      }
      metrics['native_handoff_ms'] = switchTimes;
      metrics['native_handoffs'] = switchTimes.length;
      metrics['stress_rss_after_bytes'] = ProcessInfo.currentRss;
      metrics['process_peak_rss_bytes'] = ProcessInfo.maxRss;
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'native PiP returns through the root lock and revokes on screen off',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'player_external': false,
        'flag_secure': false,
        'locale_code': 'en',
      });
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase.memory();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          databaseProvider.overrideWithValue(database),
          lockControllerProvider.overrideWith(_IntegrationLock.new),
          galleryPermissionProvider
              .overrideWith((_) async => PermissionState.denied),
        ],
      );
      final item = MediaItem(
        id: 'synthetic-pip-video',
        privatePath: files['portrait.mp4']!.path,
        originalName: 'Portrait playback sample',
        mimeType: 'video/mp4',
        isVideo: true,
        rating: 0,
        dateAdded: DateTime(2026),
        sizeBytes: await files['portrait.mp4']!.length(),
      );

      Future<void> waitFor(bool Function() condition, String message) async {
        const timeout = Duration(seconds: 12);
        final watch = Stopwatch()..start();
        while (!condition() && watch.elapsed < timeout) {
          await tester
              .pump(const Duration(milliseconds: 100))
              .timeout(timeout - watch.elapsed);
        }
        expect(condition(), isTrue, reason: message);
      }

      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const PrivateHeartApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final navigator =
            tester.state<NavigatorState>(find.byType(Navigator).first);
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => PlayerScreen(
                key: const Key('native-pip-route'),
                items: [item],
                shuffle: false,
                title: 'Playback validation',
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final pip = container.read(pictureInPictureControllerProvider.notifier);
        await waitFor(
          () => container.read(pictureInPictureControllerProvider).supported,
          'Android emulator must expose native PiP',
        );
        await waitFor(
          () =>
              container
                  .read(pictureInPictureControllerProvider)
                  .controller
                  ?.value
                  .isInitialized ??
              false,
          'Real PlayerScreen must bind its initialized controller',
        );
        final controller =
            container.read(pictureInPictureControllerProvider).controller!;
        await tester.tap(find.byTooltip('Player settings'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('Loop video'));
        await tester.pump();
        await tester.tap(find.text('Loop video'));
        await tester.pump();
        await tester.ensureVisible(find.byTooltip('Close'));
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Loop video'), findsNothing);
        expect(controller.value.isLooping, isTrue);
        await controller.seekTo(Duration.zero);
        await controller.play();
        for (final direction in ['portrait', 'landscape']) {
          await PlaybackOrientationService.instance.setMode(direction);
          await waitFor(
            () =>
                (tester.view.physicalSize.width >
                    tester.view.physicalSize.height) ==
                (direction == 'landscape'),
            'Device must reach $direction',
          );
          await tester.pump(const Duration(milliseconds: 200));
          // Show the actual screen's controls if the hide timer already fired.
          if (find.byTooltip('Orientation').evaluate().isEmpty) {
            await tester.tap(find.byType(VideoViewport));
            await tester.pump();
          }
          // Keep the normal Android surface throughout the PiP test. Flutter's
          // screenshot image surface is only restored at test teardown.
          debugPrint('PRIVI_TEST_PLAYER_SCREENSHOT_$direction');
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
        }
        await PlaybackOrientationService.instance.setMode('portrait');
        await tester.pump(const Duration(milliseconds: 300));
        for (final action in ['EXPAND', 'SCREEN_OFF']) {
          (container.read(lockControllerProvider.notifier) as _IntegrationLock)
              .unlockForTest();
          await tester.pump(const Duration(milliseconds: 200));
          await controller.play();
          final entering = pip.enter();
          await tester.pump();
          await entering;
          await waitFor(
            () {
              final state = container.read(pictureInPictureControllerProvider);
              return state.isActive &&
                  state.grantActive &&
                  controller.value.isPlaying;
            },
            'PiP must become active',
          );
          expect(
            container.read(lockControllerProvider).status,
            LockStatus.locked,
          );
          expect(find.byKey(const ValueKey('pip-video-only')), findsOneWidget);
          if (action == 'SCREEN_OFF') {
            final revoked = Completer<void>();
            void checkRevocation() {
              if (!revoked.isCompleted &&
                  !container
                      .read(pictureInPictureControllerProvider)
                      .grantActive &&
                  !controller.value.isPlaying) {
                revoked.complete();
              }
            }

            final subscription = container.listen(
              pictureInPictureControllerProvider,
              (previous, next) => checkRevocation(),
            );
            controller.addListener(checkRevocation);
            try {
              debugPrint('PRIVI_TEST_PIP_SCREEN_OFF');
              // No frame is required while the screen is off. The host waits
              // for this acknowledgement before waking or reopening the app.
              await revoked.future.timeout(const Duration(seconds: 8));
              debugPrint('PRIVI_TEST_PIP_SCREEN_OFF_REVOKED');
            } finally {
              subscription.close();
              controller.removeListener(checkRevocation);
            }
          } else {
            debugPrint('PRIVI_TEST_PIP_EXPAND');
          }
          await waitFor(
            () =>
                !container
                    .read(pictureInPictureControllerProvider)
                    .grantActive &&
                !container.read(pictureInPictureControllerProvider).isActive,
            'Host action must return through a revoked PiP grant',
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            container.read(lockControllerProvider).status,
            LockStatus.locked,
          );
          expect(controller.value.isPlaying, isFalse);
          expect(
            find.byKey(const ValueKey('vault-lock-overlay')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('native-pip-route'), skipOffstage: false),
            findsOneWidget,
          );
          await waitFor(
            () => binding.lifecycleState == AppLifecycleState.resumed,
            'Fullscreen return must resume the Activity before the next entry',
          );
          debugPrint('PRIVI_TEST_PIP_FULLSCREEN_$action');
          // Leave the locked native window visible while adb captures its
          // shield/credential composition for the validation artifact.
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        metrics['pip_expand_and_screen_off'] = 'passed';
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final platform =
            VideoPlayerPlatform.instance as MediaKitVideoPlayerPlatform;
        await waitFor(
          () => platform.activePlayerCount == 0,
          'Leaving PlayerScreen must release every decoder',
        );
        container.dispose();
        await database.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Authentication itself is covered by lock tests; this harness exercises the
/// real root overlay, Android lifecycle, native PiP and decoder together.
class _IntegrationLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);

  void unlockForTest() =>
      state = const VaultLockState(status: LockStatus.unlocked);

  @override
  void onAppLifecycle(
    AppLifecycleState lifecycle, {
    bool externalPlayerReturnedCleanly = false,
  }) {}
}
