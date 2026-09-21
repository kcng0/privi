import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/viewer/viewer_screen.dart';
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

  Future<void> close() => _firstPlayerEvents.close();

  @override
  Future<void> init() async {}

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
  Future<void> play(int playerId) async {}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform originalPlatform;
  late _SerialProbeVideoPlatform videoPlatform;
  late ProviderContainer container;

  setUp(() async {
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
    container.dispose();
    VideoPlayerPlatform.instance = originalPlatform;
    await videoPlatform.close();
  });

  testWidgets('folder viewer serializes Next while the first video is held',
      (tester) async {
    final stubPath = File('test/fixtures/video_stub.mp4').absolute.path;
    final items = [
      _video('video-0', stubPath),
      _video('video-1', stubPath),
      _video('video-2', stubPath),
    ];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ViewerScreen(items: items, initialIndex: 0),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20 && videoPlatform.createCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(videoPlatform.createCalls, 1);
    expect(find.text('video-0.mp4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(videoPlatform.createCalls, 1);
    expect(videoPlatform.maxActivePlayers, 1);
    expect(find.text('video-1.mp4'), findsOneWidget);

    videoPlatform.initializeFirstPlayer();
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(videoPlatform.maxActivePlayers, lessThanOrEqualTo(2));
  });

  testWidgets('portrait folder video hides status and navigation bars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    final stubPath = File('test/fixtures/video_stub.mp4').absolute.path;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ViewerScreen(
            items: [_video('video-0', stubPath)],
            initialIndex: 0,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(modes, contains('SystemUiMode.immersiveSticky'));
  });
}
