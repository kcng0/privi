import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/picture_in_picture_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/data/services/playback_orientation_service.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/video_presentation_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}
}

class _Orientation extends PlaybackOrientationService {
  final calls = <String>[];
  @override
  Future<void> begin() async {
    calls.add('begin');
  }

  @override
  Future<void> setMode(String mode) async {
    calls.add(mode);
  }

  @override
  Future<void> restore() async {
    calls.add('restore');
  }
}

class _Pip extends PictureInPictureController {
  @override
  PictureInPictureState build() => const PictureInPictureState();
}

class _Session extends ConsumerStatefulWidget {
  const _Session({required this.video});
  final VideoPlayerController video;
  @override
  ConsumerState<_Session> createState() => _SessionState();
}

class _SessionState extends ConsumerState<_Session>
    with VideoPresentationSession<_Session> {
  @override
  void dispose() {
    disposeVideoPresentation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bindVideoPresentation(widget.video, '/preview-not-requested.mp4');
    return Scaffold(
      body: Stack(
        children: [
          if (videoChromeAllowed) videoSessionTopActions(),
          if (videoTouchLocked) videoUnlockControl(),
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
      'sensor default and axis lock survive media changes and restore on exit',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _VideoPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = originalPlatform);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final orientation = _Orientation();
    final original = PlaybackOrientationService.instance;
    PlaybackOrientationService.instance = orientation;
    addTearDown(() => PlaybackOrientationService.instance = original);
    final videos = [
      VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/first.mp4'),
      ),
      VideoPlayerController.networkUrl(
        Uri.parse('https://example.com/second.mp4'),
      ),
    ];
    addTearDown(() async {
      for (final video in videos) {
        await video.dispose();
      }
    });
    Widget app(int index) => ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            pictureInPictureControllerProvider.overrideWith(_Pip.new),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: _Session(video: videos[index]),
          ),
        );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    expect(orientation.calls, ['begin', 'auto']);
    await tester.tap(find.byTooltip('Lock current orientation'));
    await tester.pumpAndSettle();
    expect(orientation.calls.last, 'sensorPortrait');
    expect(
      preferences.getString('player_last_locked_orientation'),
      'sensorPortrait',
    );
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(orientation.calls, ['begin', 'auto', 'sensorPortrait']);
    await tester.tap(find.byTooltip('Lock touch controls'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unlock orientation'), findsNothing);
    expect(find.byKey(const Key('video-unlock-touch')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-unlock-touch')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unlock orientation'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(orientation.calls.last, 'restore');
  });
}
