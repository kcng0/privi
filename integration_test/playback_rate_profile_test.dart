import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as video;
import 'package:path_provider/path_provider.dart';
import 'package:privi/data/services/playback/media_kit_video_player_platform.dart';
import 'package:privi/data/services/playback_orientation_service.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _fixtureBase = String.fromEnvironment(
  'PROFILE_FIXTURE_BASE',
  defaultValue: 'http://127.0.0.1:8766',
);

// Run through scripts/run-playback-rate-profile.sh: device gestures and screenshots
// come from adb, not WidgetTester's synthetic pointer events. No app code changes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installVaultVideoPlayer();
  final platform = _ProfilePlatform();
  VideoPlayerPlatform.instance = platform;

  testWidgets(
    '1080p real-time playback rate profile',
    (tester) async {
      final previousPolicy = binding.framePolicy;
      final previousDeviceEvents = binding.shouldPropagateDevicePointerEvents;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      // LiveTestWidgetsFlutterBinding otherwise drops real Android MotionEvents.
      binding.shouldPropagateDevicePointerEvents = true;
      final scenes = <Map<String, Object?>>[];
      final surfaceEvents = <Map<String, Object?>>[];
      final flutterFrames = <Map<String, Object?>>[];
      final metrics = <String, Object?>{
        'schema_version': 1,
        'clock': 'Stopwatch monotonic microseconds; waits use real wall time',
        'harness':
            'real VideoGestureSurface + VideoViewport; menu equivalent is '
                'VideoPlayerController.setPlaybackSpeed, without a held pointer',
        'fixture': 'synthetic-1080p24.mp4; 1920x1080 H264 yuv420p + AAC; 40s',
        'limits': [
          'Emulator software decode/SwiftShader does not predict A52 hardware decode.',
          'Rate command counts, time-pos progress and source FPS are not output FPS.',
          'Flutter FrameTiming measures Flutter work, not native video presentation. '
              'Callbacks are batched; scene attribution uses callback delivery time.',
          'mpv counters are specific to its VO/decoder and framedrop/display-sync '
              'configuration; zero does not prove every frame reached the screen.',
          'Empty getProperty results are unsupported OR unavailable with the '
              'media_kit string API. No zero is substituted.',
          'Surface rect/id notifiers record output changes; repeated native resize '
              'calls with unchanged values are not observable through this API.',
          'Screenshots run after each measured interval. Optional screenrecord '
              'adds encoder load and its capture cadence is not video output FPS.',
        ],
        'property_reference': 'https://mpv.io/manual/stable/#properties',
        'bundled_property_reference': 'https://github.com/mpv-player/mpv/blob/'
            '78d43740f52db817d98bcf24fb30a76ab6fa13ff/DOCS/man/input.rst',
        'source_fps_property_names': ['container-fps', 'estimated-vf-fps'],
        'scenes': scenes,
        'rate_commands': platform.commands,
        'surface_events': surfaceEvents,
        'flutter_frames': flutterFrames,
      };
      Directory? fixtures;
      VideoPlayerController? controller;
      video.PlatformVideoController? output;
      void Function()? surfaceChanged;
      final orientation = PlaybackOrientationService();
      void onTimings(List<FrameTiming> timings) {
        for (final timing in timings) {
          flutterFrames.add({
            'callback_wall_us': platform.clock.elapsedMicroseconds,
            'scene': platform.scene,
            'build_us': timing.buildDuration.inMicroseconds,
            'raster_us': timing.rasterDuration.inMicroseconds,
            'total_span_us': timing.totalSpan.inMicroseconds,
          });
        }
      }

      Future<void> waitFor(
        bool Function() ready,
        String message, {
        Duration timeout = const Duration(seconds: 15),
      }) async {
        final watch = Stopwatch()..start();
        while (!ready() && watch.elapsed < timeout) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (!ready()) throw TimeoutException(message, timeout);
      }

      try {
        fixtures = await Directory('${(await getTemporaryDirectory()).path}/'
                'privi-playback-rate-profile')
            .create(recursive: true);
        final file = File('${fixtures.path}/synthetic-1080p24.mp4');
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final response = await (await client.getUrl(
            Uri.parse('$_fixtureBase/synthetic-1080p24.mp4'),
          ))
              .close()
              .timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) {
            throw HttpException('Fixture HTTP ${response.statusCode}');
          }
          await response
              .pipe(file.openWrite())
              .timeout(const Duration(seconds: 60));
        } finally {
          client.close(force: true);
        }
        final item = MediaItem(
          id: 'synthetic-rate-profile',
          privatePath: file.path,
          originalName: '1080p rate profile',
          mimeType: 'video/mp4',
          isVideo: true,
          rating: 0,
          dateAdded: DateTime(2026),
          sizeBytes: await file.length(),
        );
        controller = VideoPlayerController.file(File(item.privatePath));
        final current = controller;
        // Native output creation needs live Flutter frames, as in playback_test.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: VideoGestureSurface(
                controller: current,
                seekSeconds: 10,
                onTap: () {},
                child: VideoViewport(
                  controller: current,
                  fitMode: VideoFitMode.fit,
                ),
              ),
            ),
          ),
        );
        await current.initialize().timeout(const Duration(seconds: 45));
        await orientation.begin();
        await orientation.setMode('landscape');
        await VideoSystemUi.apply(true);
        await waitFor(
          () =>
              tester.view.physicalSize.width > tester.view.physicalSize.height,
          'Android did not enter landscape',
        );
        await current.play();
        await waitFor(
          () => find.byType(video.Video).evaluate().isNotEmpty,
          'Native video widget did not mount',
        );
        final nativeVideo =
            tester.widget<video.Video>(find.byType(video.Video));
        output = await nativeVideo.controller.platform.future
            .timeout(const Duration(seconds: 15));
        surfaceChanged = () {
          final rect = output!.rect.value;
          surfaceEvents.add({
            'wall_us': platform.clock.elapsedMicroseconds,
            'scene': platform.scene,
            'texture_id': output.id.value,
            'native_rect': rect == null
                ? null
                : [rect.left, rect.top, rect.width, rect.height],
          });
        };
        output.rect.addListener(surfaceChanged);
        output.id.addListener(surfaceChanged);
        surfaceChanged();
        binding.addTimingsCallback(onTimings);
        final port = platform.advancedPortFor(current.playerId)
            as MediaKitAdvancedVideoPort;
        final native = port.player.platform as NativePlayer;
        metrics['mpv_version'] = await native.getProperty('mpv-version');
        const hwdecOverride = String.fromEnvironment('PRIVI_PROFILE_HWDEC');
        metrics['hwdec_override'] =
            hwdecOverride.isEmpty ? null : hwdecOverride;
        if (hwdecOverride.isNotEmpty) {
          await native.setProperty('hwdec', hwdecOverride);
          await Future<void>.delayed(const Duration(seconds: 2));
          expect(await native.getProperty('hwdec'), hwdecOverride);
        }
        metrics['device'] = {
          'physical_size': [
            tester.view.physicalSize.width,
            tester.view.physicalSize.height,
          ],
          'device_pixel_ratio': tester.view.devicePixelRatio,
        };

        // Official mpv properties; unsupported/version/VO-specific properties are
        // preserved as empty, never interpreted as zero. vo-passes is node-valued:
        // some builds cannot stringify it, so the string API may report no value.
        Future<Map<String, Object?>> snapshot() async {
          final result = <String, Object?>{};
          for (final name in [
            'speed',
            'time-pos',
            'frame-drop-count',
            'decoder-frame-drop-count',
            'vo-delayed-frame-count',
            'hwdec',
            'hwdec-current',
            'video-codec',
            'video-format',
            'video-params/w',
            'video-params/h',
            'avsync',
            'seeking',
            'core-idle',
            'paused-for-cache',
            'pause',
            'framedrop',
            'video-sync',
            'display-sync-active',
            'vo',
            'current-vo',
            'wid',
            'android-surface-size',
            'container-fps',
            'estimated-vf-fps',
            'vo-passes',
          ]) {
            final started = platform.clock.elapsedMicroseconds;
            final raw = await native
                .getProperty(name)
                .timeout(const Duration(seconds: 3));
            result[name] = {
              'status': raw.isEmpty ? 'unsupported_or_unavailable' : 'ok',
              'raw': raw,
              'value': num.tryParse(raw) ?? (raw.isEmpty ? null : raw),
              'read_start_us': started,
              'read_end_us': platform.clock.elapsedMicroseconds,
            };
          }
          result['flutter_video_rect_logical'] = _rect(
            tester.getRect(find.byKey(const Key('video-display-rect'))),
          );
          return result;
        }

        Future<void> prepare(double rate) async {
          platform.scene = 'prepare';
          await current.pause();
          await current.setPlaybackSpeed(rate);
          await current.seekTo(const Duration(seconds: 3));
          await current.play();
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }

        Future<void> measure(String name, double expectedRate) async {
          platform.scene = name;
          final commandIndex = platform.commands.length;
          final surfaceIndex = surfaceEvents.length;
          final start = await snapshot();
          final started = platform.clock.elapsedMicroseconds;
          await Future<void>.delayed(const Duration(seconds: 3));
          final ended = platform.clock.elapsedMicroseconds;
          final end = await snapshot();
          final scene = <String, Object?>{
            'name': name,
            'expected_native_rate': expectedRate,
            'start_wall_us': started,
            'end_wall_us': ended,
            'wall_seconds': (ended - started) / 1e6,
            'start': start,
            'end': end,
            'rate_commands_during_window':
                platform.commands.length - commandIndex,
            'surface_changes_during_window':
                surfaceEvents.length - surfaceIndex,
            'counter_deltas': <String, Object?>{},
          };
          for (final property in [
            'frame-drop-count',
            'decoder-frame-drop-count',
            'vo-delayed-frame-count',
          ]) {
            final a = _number(start, property);
            final b = _number(end, property);
            (scene['counter_deltas'] as Map<String, Object?>)[property] =
                a == null || b == null
                    ? {'status': 'unsupported_or_unavailable', 'delta': null}
                    : {
                        'status': b < a ? 'counter_reset' : 'ok',
                        'delta': b < a ? null : b - a,
                      };
          }
          final a = _number(start, 'time-pos');
          final b = _number(end, 'time-pos');
          final startRead = start['time-pos']! as Map<String, Object?>;
          final endRead = end['time-pos']! as Map<String, Object?>;
          final timePosWall = ((endRead['read_start_us']! as int) +
                  (endRead['read_end_us']! as int) -
                  (startRead['read_start_us']! as int) -
                  (startRead['read_end_us']! as int)) /
              2e6;
          scene['time_pos_wall_seconds'] = timePosWall;
          scene['media_seconds_per_wall_second'] =
              a == null || b == null ? null : (b - a) / timePosWall;
          scenes.add(scene);
          // Capture outside the timing window, including the real native surface.
          debugPrint('PRIVI_RATE_CAPTURE $name');
          final captureClient = HttpClient();
          try {
            var captured = false;
            final watch = Stopwatch()..start();
            while (!captured && watch.elapsed < const Duration(seconds: 5)) {
              final response = await (await captureClient.getUrl(
                Uri.parse(
                  '$_fixtureBase/capture-$name.done',
                ),
              ))
                  .close()
                  .timeout(const Duration(seconds: 2));
              final body = await response.transform(utf8.decoder).join();
              captured = response.statusCode == 200 && body.trim() == 'ok';
              if (!captured) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }
            if (!captured) throw StateError('Host screenshot failed: $name');
          } finally {
            captureClient.close(force: true);
          }
          expect(current.value.hasError, isFalse);
          expect(
            _number(end, 'speed'),
            expectedRate,
            reason: '$name must measure its intended native speed',
          );
        }

        Future<void> hold(String name, double baseline) async {
          await prepare(baseline);
          platform.scene = name;
          final commandIndex = platform.commands.length;
          final point =
              tester.getRect(find.byType(VideoGestureSurface)).centerLeft +
                  const Offset(40, 0);
          final dpr = tester.view.devicePixelRatio;
          final requested = platform.clock.elapsedMicroseconds;
          debugPrint('PRIVI_RATE_HOLD $name '
              '${(point.dx * dpr).round()} ${(point.dy * dpr).round()} 8000');
          await waitFor(
            () => find.text('2x').evaluate().isNotEmpty,
            'Real Android hold did not show the 2x badge',
          );
          final recognized = platform.clock.elapsedMicroseconds;
          await waitFor(
            () => port.player.state.rate == 2,
            'Long press did not apply native rate 2',
          );
          await measure(name, 2);
          final heldCommands = platform.commands.length - commandIndex;
          await waitFor(
            () => find.text('2x').evaluate().isEmpty,
            'Real Android hold did not release',
            timeout: const Duration(seconds: 12),
          );
          final released = platform.clock.elapsedMicroseconds;
          await waitFor(
            () => port.player.state.rate == baseline,
            'Release did not restore the baseline speed',
          );
          (metrics['holds'] as List<Map<String, Object?>>? ??
                  (metrics['holds'] = <Map<String, Object?>>[]))
              .add({
            'name': name,
            'baseline_rate': baseline,
            'request_wall_us': requested,
            'badge_visible_wall_us': recognized,
            'badge_gone_wall_us': released,
            'request_to_badge_ms': (recognized - requested) / 1000,
            'commands_before_release': heldCommands,
            'no_rate_change_control': baseline == 2,
          });
          await measure('${name}_release', baseline);
          if (baseline == 2) {
            expect(
              heldCommands,
              0,
              reason: 'The 2x hold control must not send a native rate command',
            );
          }
        }

        debugPrint('PRIVI_RATE_RUN_START');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await prepare(1);
        await measure('baseline_1x', 1);
        await prepare(2);
        await measure('menu_2x_no_touch', 2);
        await hold('hold_1x_to_2x', 1);
        await hold('hold_2x_unchanged', 2);
        metrics['completed'] = true;
      } finally {
        debugPrint('PRIVI_RATE_RUN_END');
        binding.removeTimingsCallback(onTimings);
        if (output != null && surfaceChanged != null) {
          output.rect.removeListener(surfaceChanged);
          output.id.removeListener(surfaceChanged);
        }
        binding.reportData = {...?binding.reportData, ...metrics};
        await tester.pumpWidget(const SizedBox.shrink());
        await controller?.dispose().timeout(const Duration(seconds: 10));
        await VideoSystemUi.restore();
        await orientation.restore();
        if (fixtures != null) await fixtures.delete(recursive: true);
        binding.framePolicy = previousPolicy;
        binding.shouldPropagateDevicePointerEvents = previousDeviceEvents;
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.width, rect.height];

num? _number(Map<String, Object?> snapshot, String key) =>
    (snapshot[key]! as Map<String, Object?>)['value'] as num?;

class _ProfilePlatform extends MediaKitVideoPlayerPlatform {
  final clock = Stopwatch()..start();
  final commands = <Map<String, Object?>>[];
  String scene = 'initialization';

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    final started = clock.elapsedMicroseconds;
    final command = <String, Object?>{
      'scene': scene,
      'player_id': playerId,
      'requested_rate': speed,
      'start_wall_us': started,
    };
    commands.add(command);
    try {
      await super.setPlaybackSpeed(playerId, speed);
      command['status'] = 'accepted';
    } catch (error) {
      command['status'] = 'error';
      command['error'] = '$error';
      rethrow;
    } finally {
      command['end_wall_us'] = clock.elapsedMicroseconds;
      command['latency_us'] = clock.elapsedMicroseconds - started;
    }
  }
}
