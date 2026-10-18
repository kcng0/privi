import 'dart:async';
import 'dart:convert';
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
import 'package:privi/data/services/playback/libvlc_video_player_platform.dart';
import 'package:privi/data/services/playback/vault_video_player.dart';
import 'package:privi/data/services/playback_orientation_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/presentation/lock/lock_screen.dart';
import 'package:privi/presentation/player/player_screen.dart';
import 'package:privi/presentation/player/video_player_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  final binding = ApplicationFrameIntegrationTestBinding();
  // Android screenshots inspect saturated fixture pixels. A red DEBUG banner
  // would be unrelated video content, especially in Original-size mode.
  WidgetsApp.debugAllowBannerOverride = false;
  installVaultVideoPlayer();
  final playback = _InteractionPlaybackPlatform();
  VideoPlayerPlatform.instance = playback;
  final metrics = <String, dynamic>{};
  final files = <String, File>{};
  late Directory fixtures;
  var deviceActionId = 0;

  Future<Map<String, String>> recordDiagnostics(
    VideoPlayerController controller,
    AdvancedVideoController advanced,
    String label,
  ) async {
    final native = await advanced.readPlaybackDiagnostics();
    expect(native['engine'], 'libvlc');
    (metrics['native_diagnostics_probes'] as Map<String, dynamic>? ??
        (metrics['native_diagnostics_probes'] = <String, dynamic>{}))[label] = {
      ...native,
      'facade-position-ms': controller.value.position.inMilliseconds,
      'native-position-ms': (await controller.position)?.inMilliseconds,
      'captured-at': DateTime.now().toUtc().toIso8601String(),
    };
    return native;
  }

  Future<Map<String, dynamic>> recordWindowDiagnostics(String label) async {
    final native = await const MethodChannel('com.privi.app/window')
        .invokeMapMethod<String, dynamic>('getWindowDiagnostics')
        .timeout(const Duration(seconds: 5));
    if (native == null) {
      throw StateError('Native window diagnostics are unavailable: $label');
    }
    final observation = <String, dynamic>{
      ...native,
      'captured-at': DateTime.now().toUtc().toIso8601String(),
    };
    (metrics['native_window_diagnostics'] as Map<String, dynamic>? ??
        (metrics['native_window_diagnostics'] =
            <String, dynamic>{}))[label] = observation;
    final composition = observation['flutter-composition'];
    if (composition != null) {
      if (composition is! Map || composition['snapshot-elapsed-ns'] is! int) {
        throw FormatException('Invalid composition snapshot reference: $label');
      }
    }
    debugPrint(
      'PRIVI_TEST_WINDOW ${jsonEncode({
            'metrics-label': label,
            if (composition is Map)
              'snapshot-elapsed-ns': composition['snapshot-elapsed-ns'],
          })}',
    );
    return observation;
  }

  Future<Map<String, dynamic>> deviceAction(
    WidgetTester tester,
    Map<String, Object?> action,
  ) async {
    final id = 'action-${++deviceActionId}';
    final actionRequest = <String, Object?>{'id': id, ...action};
    final bytes = utf8.encode(jsonEncode(actionRequest));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final watch = Stopwatch()..start();
    var phase = 'registration';
    var receivedResult = false;
    Duration remaining() {
      final duration = const Duration(seconds: 20) - watch.elapsed;
      if (duration <= Duration.zero) {
        throw TimeoutException('No real Android acknowledgement for $id');
      }
      return duration;
    }

    try {
      // Register exactly once. An uncertain POST must never emit a marker or
      // be retried: only the fenced logcat owner may dispatch the saved action.
      final registration = await client
          .postUrl(Uri.parse('http://10.0.2.2:8766/action'))
          .timeout(remaining());
      registration.followRedirects = false;
      registration.headers.contentType = ContentType.json;
      registration.contentLength = bytes.length;
      registration.add(bytes);
      final accepted = await registration.close().timeout(remaining());
      final acknowledgement =
          await utf8.decoder.bind(accepted).join().timeout(remaining());
      if (accepted.statusCode != 201 && accepted.statusCode != 202) {
        throw StateError(
          'Device action registration $id: HTTP ${accepted.statusCode}: '
          '$acknowledgement',
        );
      }
      final registered = jsonDecode(acknowledgement);
      if (registered is! Map ||
          registered['id'] != id ||
          registered['registered'] != true) {
        throw FormatException(
          'Invalid action registration acknowledgement: $id',
        );
      }
      phase = 'result';
      debugPrint('PRIVI_TEST_DEVICE $id');
      while (watch.elapsed < const Duration(seconds: 20)) {
        final request = await client
            .getUrl(Uri.parse('http://10.0.2.2:8766/result/$id'))
            .timeout(remaining());
        final response = await request.close().timeout(remaining());
        final body =
            await utf8.decoder.bind(response).join().timeout(remaining());
        if (response.statusCode == 200) {
          final result = jsonDecode(body) as Map<String, dynamic>;
          receivedResult = true;
          expect(
            result['ok'],
            isTrue,
            reason: 'Real Android action $id: ${result['error']}',
          );
          (metrics['device_actions'] as List<dynamic>? ??
                  (metrics['device_actions'] = <dynamic>[]))
              .add(result);
          return {...result, 'id': id};
        }
        if (response.statusCode != 404) {
          throw StateError('Device action server: HTTP ${response.statusCode}');
        }
        // Capturing/input acknowledgement must never create a Flutter frame.
        // Only application requests may drive native SurfaceView composition.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw TimeoutException('No real Android acknowledgement for $id');
    } catch (error) {
      if (!receivedResult) {
        (metrics['device_action_transport_failures'] as List<dynamic>? ??
                (metrics['device_action_transport_failures'] = <dynamic>[]))
            .add({
          'id': id,
          'phase': phase,
          'request': actionRequest,
          'elapsed-ms': watch.elapsedMilliseconds,
          'error': error.toString(),
        });
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<_ScreenCoordinates> screenCoordinates(WidgetTester tester) async {
    // A FlutterView can be inset from the Android display by system bars,
    // cutouts or window placement. The offset is already in physical pixels.
    // Re-read for every action/capture; rotation and PiP can change it.
    final offset = await const MethodChannel('com.privi.app/window')
        .invokeListMethod<int>('getFlutterViewScreenOffset')
        .timeout(const Duration(seconds: 5));
    if (offset == null || offset.length != 2) {
      throw StateError(
        'getFlutterViewScreenOffset must return two physical coordinates: $offset',
      );
    }
    final scale = tester.view.devicePixelRatio;
    if (!scale.isFinite || scale <= 0) {
      throw StateError('Invalid FlutterView devicePixelRatio: $scale');
    }
    return _ScreenCoordinates(
      scale,
      Offset(offset[0].toDouble(), offset[1].toDouble()),
    );
  }

  Future<Map<String, Object>> physicalViewport(WidgetTester tester) async {
    final coordinates = await screenCoordinates(tester);
    final rect = tester.getRect(find.byType(VideoViewport).first);
    final topLeft = coordinates.toScreen(rect.topLeft);
    final bottomRight = coordinates.toScreen(rect.bottomRight);
    return {
      'viewport': [topLeft.dx, topLeft.dy, bottomRight.dx, bottomRight.dy],
      'coordinates': {
        ...coordinates.evidence,
        'viewport_logical': [rect.left, rect.top, rect.right, rect.bottom],
      },
    };
  }

  Future<Map<String, dynamic>> screenshot(
    WidgetTester tester,
    String name, {
    double? aspect,
    List<int>? physicalSize,
    String? compareTo,
    bool paused = false,
    bool graphicsDiagnostics = false,
    bool surfaceComposition = false,
    Map<String, Object?>? uiWitness,
  }) async =>
      deviceAction(tester, {
        'op': 'capture',
        'name': name,
        ...await physicalViewport(tester),
        if (aspect != null) 'aspect': aspect,
        if (physicalSize != null) 'physicalSize': physicalSize,
        if (compareTo != null) 'compareTo': compareTo,
        if (paused) 'expect': 'static',
        if (graphicsDiagnostics) 'graphicsDiagnostics': true,
        if (surfaceComposition) 'surfaceComposition': true,
        if (uiWitness != null) 'ui_witness': uiWitness,
      });

  Future<void> nativeInput(
    WidgetTester tester,
    String operation,
    Offset point,
  ) async {
    final coordinates = await screenCoordinates(tester);
    final physicalPoint = coordinates.toScreen(point);
    await deviceAction(tester, {
      'op': operation,
      'point': [physicalPoint.dx, physicalPoint.dy],
      'coordinates': {
        ...coordinates.evidence,
        'point_logical': [point.dx, point.dy],
      },
    });
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
      // Native platform-view creation needs Flutter frames while awaiting it.
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!completed) {
      throw TimeoutException('Native operation exceeded $timeout');
    }
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    return result as T;
  }

  Future<VideoPlayerController> open(WidgetTester tester, String name) async {
    final watch = Stopwatch()..start();
    final controller = VaultVideoPlayerController.file(files[name]!);
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
    // This standalone harness owns only this synthetic controller. Production
    // PlayerScreen below obtains its grant from the real lifecycle owner.
    await playback.setPresentationAllowed(controller.playerId, true);
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
            await controller.setLooping(true);
            await controller.play();
            await tester.pump(const Duration(milliseconds: 800));
            expect(controller.value.hasError, isFalse);
            final probe = AdvancedVideoController(controller);
            try {
              await recordDiagnostics(controller, probe, 'first-${entry.key}');
            } finally {
              probe.dispose();
            }
            // LibVLC's Flutter box is the viewport, not the displayed video.
            // Measure saturated fixture pixels in the actual Android screenshot.
            await screenshot(
              tester,
              'best-fit-${entry.key}',
              aspect: entry.value,
            );
            if (entry.key == 'portrait.mp4') {
              for (final mode in [
                VideoFitMode.fitScreen,
                VideoFitMode.fill,
                VideoFitMode.original,
                VideoFitMode.ratio16x9,
                VideoFitMode.ratio4x3,
              ]) {
                await display(tester, controller, mode: mode);
                await tester.pump(const Duration(milliseconds: 600));
                final viewport = (await physicalViewport(tester))['viewport']!
                    as List<double>;
                final viewportAspect =
                    (viewport[2] - viewport[0]) / (viewport[3] - viewport[1]);
                await screenshot(
                  tester,
                  'portrait-${mode.name}',
                  aspect: switch (mode) {
                    VideoFitMode.fill ||
                    VideoFitMode.fitScreen =>
                      viewportAspect,
                    VideoFitMode.ratio16x9 => 16 / 9,
                    VideoFitMode.ratio4x3 => 4 / 3,
                    _ => 180 / 320,
                  },
                  physicalSize:
                      mode == VideoFitMode.original ? [180, 320] : null,
                );
              }
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
      final platform = playback;
      final failed = VaultVideoPlayerController.file(files['corrupt.mp4']!);
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
      Future<void> recordSubtitlePixels(
        VideoPlayerController controller,
        String label,
      ) async {
        final observation = <String, Object?>{
          'captured-at': DateTime.now().toUtc().toIso8601String(),
        };
        try {
          observation['metadata'] = await const MethodChannel(
            'com.privi.app/libvlc',
          ).invokeMapMethod<String, String>(
            'debugReadSubtitleSurfacePixels',
            {'id': controller.playerId},
          ).timeout(const Duration(seconds: 5));
        } on PlatformException catch (error) {
          observation['platform-error'] = {
            'code': error.code,
            'message': error.message,
            'details': error.details,
          };
        } on TimeoutException catch (error) {
          observation['timeout-error'] = error.toString();
        } on MissingPluginException catch (error) {
          observation['missing-plugin-error'] = error.toString();
        }
        (metrics['native_subtitle_surface_pixels'] as Map<String, dynamic>? ??
            (metrics['native_subtitle_surface_pixels'] =
                <String, dynamic>{}))[label] = observation;
      }

      Future<Map<String, String>> awaitAssPlaying(
        VideoPlayerController controller,
        AdvancedVideoController advanced,
        String label, {
        required String readinessMetric,
      }) async {
        const timeout = Duration(seconds: 12);
        final watch = Stopwatch()..start();
        final observations = <Map<String, Object?>>[];
        (metrics[readinessMetric] as Map<String, dynamic>? ??
                (metrics[readinessMetric] = <String, dynamic>{}))[label] =
            observations;
        while (watch.elapsed < timeout) {
          final native = await recordDiagnostics(
            controller,
            advanced,
            label,
          ).timeout(timeout - watch.elapsed);
          final probe = (metrics['native_diagnostics_probes']
              as Map<String, dynamic>)[label] as Map<String, dynamic>;
          observations.add({
            'elapsed-ms': watch.elapsedMilliseconds,
            'native-player-state': native['native-player-state'],
            'native-is-playing': native['native-is-playing'],
            'input-reopen-count': native['input-reopen-count'],
            'native-position-ms': probe['native-position-ms'],
            'facade-position-ms': probe['facade-position-ms'],
            'captured-at': probe['captured-at'],
          });
          if (native['native-is-playing'] == 'true') return native;
          // A legal 3s loop reopens its input at EOF. Observe that transition
          // without pumping, seeking, replaying or retrying a captured image.
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError(
          'ASS did not resume native Playing within 12s: $label $observations',
        );
      }

      // Isolate steady embedded ASS playback from the later external-subtitle,
      // seek and A-B scenario. Source pixels (including CJK and burned-in HUD)
      // remain the visual evidence; clocks below are separate diagnostic probes.
      final steady = await open(tester, 'tracks.mkv');
      final steadyAdvanced = AdvancedVideoController(steady);
      try {
        await display(tester, steady);
        await steadyAdvanced.refresh();
        final subtitle = steadyAdvanced.value.subtitleTracks
            .firstWhere((track) => track.id != '-1');
        await steadyAdvanced.selectSubtitleTrack(subtitle.id);
        expect(steadyAdvanced.value.abLoopStart, isNull);
        expect(steadyAdvanced.value.abLoopEnd, isNull);
        await steady.setLooping(true);
        await steady.play();
        await Future<void>.delayed(const Duration(milliseconds: 800));
        Future<void> checkSteadyCue(String label) async {
          final native = await awaitAssPlaying(
            steady,
            steadyAdvanced,
            label,
            readinessMetric: 'ass_embedded_readiness',
          );
          final position = await steady.position;
          expect(position, isNotNull);
          expect(
            position!.inMilliseconds,
            inInclusiveRange(0, 2999),
            reason:
                'The external chinese.ass cue spans 0-3s; steady captures must remain inside it',
          );
          expect(
            native['native-is-playing'],
            'true',
            reason:
                'Steady ASS must capture playback rather than an EOF-stopped input',
          );
        }

        await checkSteadyCue('ass-steady-first-before');
        final firstNative = await steady.position;
        final firstFacade = steady.value.position;
        expect(firstNative, isNotNull);
        await recordDiagnostics(steady, steadyAdvanced, 'ass-steady-first');
        await recordSubtitlePixels(steady, 'ass-steady-first');
        final first = await screenshot(
          tester,
          'portrait-ass-steady-first',
          aspect: 180 / 320,
        );
        await checkSteadyCue('ass-steady-first-after');
        final watch = Stopwatch()..start();
        Duration? nextNative;
        while (watch.elapsed < const Duration(seconds: 3)) {
          nextNative = await steady.position;
          if (nextNative != null &&
              nextNative != firstNative &&
              steady.value.position != firstFacade) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(nextNative, isNotNull);
        expect(
          nextNative,
          isNot(firstNative),
          reason:
              'Steady ASS native position must progress without a seek/A-B request',
        );
        expect(
          steady.value.position,
          isNot(firstFacade),
          reason:
              'Steady ASS facade position must progress without a seek/A-B request',
        );
        metrics['ass_steady_position_probes'] = {
          'first_native_ms': firstNative!.inMilliseconds,
          'second_native_ms': nextNative!.inMilliseconds,
          'first_facade_ms': firstFacade.inMilliseconds,
          'second_facade_ms': steady.value.position.inMilliseconds,
          'selected_subtitle_id': subtitle.id,
          'explicit_seek_requests': playback.seeks
              .where((entry) => entry.$1 == steady.playerId)
              .length,
          'ab_loop_configured': steadyAdvanced.value.abLoopEnd != null,
          'cjk_and_burned_in_hud':
              'inspect actual native PNGs against chinese.ass fixture',
        };
        await checkSteadyCue('ass-steady-second-before');
        await screenshot(
          tester,
          'portrait-ass-steady-second',
          aspect: 180 / 320,
          compareTo: first['id'] as String,
        );
        await checkSteadyCue('ass-steady-second-after');

        // Same embedded ASS input: ordinary seek before any external slave,
        // subtitle delay or A-B configuration, for the decoder comparison.
        await steady.seekTo(const Duration(milliseconds: 1000));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await awaitAssPlaying(
          steady,
          steadyAdvanced,
          'ass-embedded-after-seek-1000-before',
          readinessMetric: 'ass_embedded_readiness',
        );
        expect(
          (await steady.position)?.inMilliseconds,
          inInclusiveRange(0, 2999),
        );
        await recordSubtitlePixels(
          steady,
          'ass-embedded-after-seek-1000-before',
        );
        await screenshot(
          tester,
          'portrait-ass-embedded-after-seek-1000',
          aspect: 180 / 320,
        );
        await awaitAssPlaying(
          steady,
          steadyAdvanced,
          'ass-embedded-after-seek-1000-after',
          readinessMetric: 'ass_embedded_readiness',
        );
        expect(
          (await steady.position)?.inMilliseconds,
          inInclusiveRange(0, 2999),
        );
      } finally {
        steadyAdvanced.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await steady.dispose();
      }

      // Keep the imported ASS input independent of the embedded-track and
      // original combined controls scenarios. Each phase retains native pixels
      // and clock/configuration probes; glyph presence is reviewed in the PNGs.
      final external = await open(tester, 'tracks.mkv');
      final externalAdvanced = AdvancedVideoController(external);
      try {
        await display(tester, external);
        await externalAdvanced.refresh();
        await externalAdvanced.importSubtitle(files['chinese.ass']!.path);
        expect(externalAdvanced.value.audioDelay, Duration.zero);
        expect(externalAdvanced.value.subtitleDelay, Duration.zero);
        expect(externalAdvanced.value.abLoopStart, isNull);
        expect(externalAdvanced.value.abLoopEnd, isNull);
        await external.setLooping(true);
        await external.play();
        await Future<void>.delayed(const Duration(milliseconds: 800));

        Future<Map<String, String>> awaitExternalPlaying(String label) =>
            awaitAssPlaying(
              external,
              externalAdvanced,
              label,
              readinessMetric: 'ass_external_readiness',
            );

        Future<Map<String, dynamic>> externalFrame(
          String phase, {
          String? compareTo,
        }) async {
          final before = await awaitExternalPlaying(
            'ass-external-$phase-before',
          );
          await recordSubtitlePixels(external, 'ass-external-$phase-before');
          expect(before['native-is-playing'], 'true');
          expect(
            (await external.position)?.inMilliseconds,
            inInclusiveRange(0, 2999),
            reason: 'The external ASS cue spans 0-3s',
          );
          final frame = await screenshot(
            tester,
            'portrait-ass-external-$phase',
            aspect: 180 / 320,
            compareTo: compareTo,
          );
          final after = await awaitExternalPlaying(
            'ass-external-$phase-after',
          );
          await recordSubtitlePixels(external, 'ass-external-$phase-after');
          expect(after['native-is-playing'], 'true');
          expect(
            (await external.position)?.inMilliseconds,
            inInclusiveRange(0, 2999),
            reason:
                'The external ASS cue must also remain active after capture',
          );
          return frame;
        }

        final first = await externalFrame('steady-first');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await externalFrame('steady-second', compareTo: first['id'] as String);
        metrics['ass_external_steady_probes'] = {
          'explicit_seek_requests': playback.seeks
              .where((entry) => entry.$1 == external.playerId)
              .length,
          'ab_loop_configured': externalAdvanced.value.abLoopEnd != null,
          'cjk': 'inspect native PNGs against the same chinese.ass fixture',
        };
        await external.seekTo(const Duration(milliseconds: 1000));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await externalFrame('after-seek-1000');
        await externalAdvanced.setAudioDelay(const Duration(milliseconds: 125));
        await externalAdvanced
            .setSubtitleDelay(const Duration(milliseconds: -250));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await externalFrame('after-delay');
        await externalAdvanced.setAbLoop(
          const Duration(milliseconds: 500),
          const Duration(milliseconds: 1500),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await externalFrame('after-ab');
      } finally {
        externalAdvanced.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await external.dispose();
      }

      // Freeze the short input before its EOF so decoder re-selection can be
      // compared on the same input. Glyph presence still requires actual PNGs.
      final paused = await open(tester, 'tracks.mkv');
      final pausedAdvanced = AdvancedVideoController(paused);
      try {
        await display(tester, paused);
        await pausedAdvanced.refresh();
        await pausedAdvanced.importSubtitle(files['chinese.ass']!.path);
        expect(pausedAdvanced.value.audioDelay, Duration.zero);
        expect(pausedAdvanced.value.subtitleDelay, Duration.zero);
        expect(pausedAdvanced.value.abLoopEnd, isNull);
        await paused.play();
        await awaitAssPlaying(
          paused,
          pausedAdvanced,
          'ass-paused-playing-before-pause',
          readinessMetric: 'ass_paused_readiness',
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await paused.pause();
        Map<String, String>? baseline;
        Future<Map<String, String>> pausedObservation(
          String label, {
          int? targetMs,
        }) async {
          final watch = Stopwatch()..start();
          late Map<String, String> native;
          int? position;
          while (true) {
            native = await recordDiagnostics(paused, pausedAdvanced, label)
                .timeout(const Duration(seconds: 12) - watch.elapsed);
            final probe = (metrics['native_diagnostics_probes']
                as Map<String, dynamic>)[label] as Map<String, dynamic>;
            position = probe['native-position-ms'] as int?;
            final ready = native['native-player-state'] == '4' &&
                native['native-is-playing'] == 'false' &&
                !paused.value.isPlaying &&
                position != null &&
                (targetMs == null || (position - targetMs).abs() <= 30);
            if (ready || watch.elapsed >= const Duration(seconds: 12)) break;
            final remaining = const Duration(seconds: 12) - watch.elapsed;
            if (remaining <= Duration.zero) break;
            await Future<void>.delayed(
              remaining < const Duration(milliseconds: 100)
                  ? remaining
                  : const Duration(milliseconds: 100),
            );
            if (watch.elapsed >= const Duration(seconds: 12)) break;
          }
          expect(native['native-player-state'], '4');
          expect(native['native-is-playing'], 'false');
          expect(paused.value.isPlaying, isFalse);
          expect(position, inInclusiveRange(0, 2999));
          baseline ??= native;
          expect(native['input-reopen-count'], baseline!['input-reopen-count']);
          expect(native['surface-generation'], baseline!['surface-generation']);
          (metrics['ass_paused_observations'] as Map<String, dynamic>? ??
              (metrics['ass_paused_observations'] =
                  <String, dynamic>{}))[label] = {
            'target-ms': targetMs,
            'native-position-ms': position,
            'target-reached': targetMs == null ||
                (position != null && (position - targetMs).abs() <= 30),
            'input-reopen-count': native['input-reopen-count'],
            'surface-generation': native['surface-generation'],
            'glyph-result': 'requires actual PNG review, including baseline',
          };
          await recordSubtitlePixels(paused, label);
          return native;
        }

        Future<Map<String, dynamic>> pausedFrame(
          String phase, {
          int? targetMs,
          String? compareTo,
          bool surfaceComposition = false,
        }) async {
          await pausedObservation(
            'ass-paused-$phase-before',
            targetMs: targetMs,
          );
          final frame = await screenshot(
            tester,
            'portrait-ass-paused-$phase',
            aspect: 180 / 320,
            compareTo: compareTo,
            paused: compareTo != null,
            surfaceComposition: surfaceComposition,
          );
          await pausedObservation(
            'ass-paused-$phase-after',
            targetMs: targetMs,
          );
          return frame;
        }

        final first =
            await pausedFrame('steady-first', surfaceComposition: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await pausedFrame('steady-second', compareTo: first['id'] as String);
        await paused.seekTo(const Duration(milliseconds: 1000));
        await pausedFrame(
          'after-seek-1000',
          targetMs: 1000,
          surfaceComposition: true,
        );
        final selected = await pausedObservation('ass-paused-before-reselect');
        final actual = selected['subtitle-track-actual'];
        expect(int.tryParse(actual ?? ''), greaterThanOrEqualTo(0));
        await pausedAdvanced.selectSubtitleTrack('-1');
        await pausedAdvanced.selectSubtitleTrack(actual!);
        await paused.seekTo(const Duration(milliseconds: 1000));
        await pausedFrame(
          'after-reselect-seek-1000',
          targetMs: 1000,
          surfaceComposition: true,
        );
      } finally {
        pausedAdvanced.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await paused.dispose();
      }

      final controller = await open(tester, 'tracks.mkv');
      final advanced = AdvancedVideoController(controller);
      try {
        await display(tester, controller);
        await advanced.refresh();
        expect(advanced.value.audioTracks.length, greaterThanOrEqualTo(2));
        expect(
          advanced.value.subtitleTracks.where((track) => track.id != '-1'),
          isNotEmpty,
        );
        await advanced.selectAudioTrack(advanced.value.audioTracks.last.id);
        await advanced.selectSubtitleTrack(
          advanced.value.subtitleTracks
              .firstWhere((track) => track.id != '-1')
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
        await tester.pump(const Duration(milliseconds: 800));
        await advanced.refresh();
        expect(advanced.value.audioTracks.last.isSelected, isTrue);
        await recordDiagnostics(controller, advanced, 'ass-before-capture');
        await screenshot(tester, 'portrait-ass-best-fit', aspect: 180 / 320);
        // Inspect another actual video frame while the A-B interval remains
        // inside the fixture's 0-3s cue. This wait never submits a Flutter frame.
        await Future<void>.delayed(const Duration(seconds: 2));
        await recordDiagnostics(controller, advanced, 'ass-later-capture');
        await screenshot(tester, 'portrait-ass-later', aspect: 180 / 320);
        await advanced.setAbLoop(null, null);
        expect(advanced.value.abLoopEnd, isNull);
        await advanced.selectSubtitleTrack('-1');
        expect(controller.value.hasError, isFalse);
      } finally {
        advanced.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.dispose();
      }

      // These external inputs independently define which cues a positive delay
      // must preserve across paused seeks. The PNGs, not track/alpha metadata,
      // decide whether the expected labels were actually presented.
      final originalAss = await files['chinese.ass']!.readAsString();
      final firstDialogue = originalAss.indexOf('Dialogue:');
      if (firstDialogue < 0) {
        throw StateError('The ASS fixture has no dialogue/header boundary');
      }
      final assHeader = originalAss.substring(0, firstDialogue);
      ({int startMs, int endMs, String text, int y}) cue(
        int startMs,
        int endMs,
        String text,
        int y,
      ) =>
          (startMs: startMs, endMs: endMs, text: text, y: y);
      final delayedCueCases = [
        (
          name: 'positive-delay-seek',
          targetMs: 1500,
          cues: [
            cue(0, 750, 'DELAY_A 甲', 240),
            cue(1000, 2000, 'DELAY_B 乙', 275),
          ],
        ),
        (
          name: 'overlap-delay-seek',
          targetMs: 2500,
          cues: [
            cue(0, 2800, 'OVERLAP_A 甲', 240),
            cue(1000, 1200, 'OVERLAP_B 乙', 275),
          ],
        ),
        (
          name: 'expired-queue-delay-seek',
          targetMs: 2500,
          cues: [
            cue(0, 2800, 'QUEUE_A 甲', 240),
            for (var index = 1; index <= 100; index++)
              cue(
                index * 10,
                (index + 1) * 10,
                'EXPIRED_${index.toString().padLeft(3, '0')} 舊',
                205,
              ),
            cue(1300, 2800, 'QUEUE_B 乙', 275),
          ],
        ),
      ];
      String assTime(int milliseconds) {
        final centiseconds = milliseconds ~/ 10;
        return '${centiseconds ~/ 360000}:'
            '${(centiseconds ~/ 6000 % 60).toString().padLeft(2, '0')}:'
            '${(centiseconds ~/ 100 % 60).toString().padLeft(2, '0')}.'
            '${(centiseconds % 100).toString().padLeft(2, '0')}';
      }

      for (final scenario in delayedCueCases) {
        const delayMs = 1000;
        final name = 'ass-${scenario.name}';
        final subtitleFile = File('${fixtures.path}/$name.ass');
        final dialogues = scenario.cues
            .map(
              (entry) =>
                  'Dialogue: 0,${assTime(entry.startMs)},${assTime(entry.endMs)},'
                  'Default,,0,0,0,,{\\an5\\pos(90,${entry.y})}${entry.text}\n',
            )
            .join();
        await subtitleFile.writeAsString('$assHeader$dialogues');
        final expectation = <String, Object?>{
          'subtitle-input': await subtitleFile.readAsString(),
          'source-cues': [
            for (final entry in scenario.cues)
              {
                'start-ms': entry.startMs,
                'end-exclusive-ms': entry.endMs,
                'delayed-start-ms': entry.startMs + delayMs,
                'delayed-end-exclusive-ms': entry.endMs + delayMs,
                'text': entry.text,
                'position': [90, entry.y],
              },
          ],
          'requested-delay-ms': delayMs,
          'requested-seek-ms': scenario.targetMs,
          'expected-visible-labels': [
            for (final entry in scenario.cues)
              if (entry.startMs + delayMs <= scenario.targetMs &&
                  scenario.targetMs < entry.endMs + delayMs)
                entry.text,
          ],
          'expected-absent-labels': [
            for (final entry in scenario.cues)
              if (entry.startMs + delayMs > scenario.targetMs ||
                  scenario.targetMs >= entry.endMs + delayMs)
                entry.text,
          ],
          'glyph-result':
              'requires actual native PNG review against these cues',
        };
        (metrics['ass_delayed_cue_inputs'] as Map<String, dynamic>? ??
            (metrics['ass_delayed_cue_inputs'] =
                <String, dynamic>{}))[name] = expectation;
        final delayed = await open(tester, 'tracks.mkv');
        final delayedAdvanced = AdvancedVideoController(delayed);
        try {
          await display(tester, delayed);
          await delayedAdvanced.refresh();
          await delayedAdvanced.importSubtitle(subtitleFile.path);
          await delayed.play();
          await awaitAssPlaying(
            delayed,
            delayedAdvanced,
            '$name-playing-before-pause',
            readinessMetric: 'ass_delayed_cue_readiness',
          );
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await delayed.pause();
          Map<String, String>? baseline;
          Future<void> observePaused(String label, {int? targetMs}) async {
            final watch = Stopwatch()..start();
            final observations = <Map<String, Object?>>[];
            (metrics['ass_delayed_cue_readiness']
                as Map<String, dynamic>)[label] = observations;
            late Map<String, String> native;
            int? position;
            while (true) {
              native = await recordDiagnostics(delayed, delayedAdvanced, label)
                  .timeout(const Duration(seconds: 12) - watch.elapsed);
              final probe = (metrics['native_diagnostics_probes']
                  as Map<String, dynamic>)[label] as Map<String, dynamic>;
              position = probe['native-position-ms'] as int?;
              observations
                  .add({...probe, 'elapsed-ms': watch.elapsedMilliseconds});
              final ready = native['native-player-state'] == '4' &&
                  native['native-is-playing'] == 'false' &&
                  !delayed.value.isPlaying &&
                  position != null &&
                  (targetMs == null || (position - targetMs).abs() <= 30);
              if (ready || watch.elapsed >= const Duration(seconds: 12)) break;
              final remaining = const Duration(seconds: 12) - watch.elapsed;
              if (remaining <= Duration.zero) break;
              await Future<void>.delayed(
                remaining < const Duration(milliseconds: 100)
                    ? remaining
                    : const Duration(milliseconds: 100),
              );
              if (watch.elapsed >= const Duration(seconds: 12)) break;
            }
            expect(native['native-player-state'], '4');
            expect(native['native-is-playing'], 'false');
            expect(delayed.value.isPlaying, isFalse);
            expect(position, inInclusiveRange(0, 2999));
            if (targetMs != null) {
              expect(position, inInclusiveRange(targetMs - 30, targetMs + 30));
            }
            baseline ??= native;
            expect(
              native['input-reopen-count'],
              baseline!['input-reopen-count'],
            );
            expect(
              native['surface-generation'],
              baseline!['surface-generation'],
            );
          }

          await observePaused('$name-paused-before-delay');
          expectation['player-id'] = delayed.playerId;
          expectation['baseline-input-reopen-count'] =
              baseline!['input-reopen-count'];
          expectation['baseline-surface-generation'] =
              baseline!['surface-generation'];
          await delayedAdvanced
              .setSubtitleDelay(const Duration(milliseconds: delayMs));
          await delayed.seekTo(Duration(milliseconds: scenario.targetMs));
          await observePaused(
            '$name-before-capture',
            targetMs: scenario.targetMs,
          );
          await recordSubtitlePixels(delayed, '$name-before-capture');
          final frame =
              await screenshot(tester, 'portrait-$name', aspect: 180 / 320);
          expectation['capture'] = frame;
          await observePaused(
            '$name-after-capture',
            targetMs: scenario.targetMs,
          );
          await recordSubtitlePixels(delayed, '$name-after-capture');
        } finally {
          delayedAdvanced.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await delayed.dispose();
          await subtitleFile.delete();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    '100 native controller handoffs release every decoder',
    (tester) async {
      final platform = playback;
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
      final sceneWatch = Stopwatch()..start();
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
      final rootTimeline = <Map<String, Object?>>[];
      metrics['root_lock_timeline'] = rootTimeline;
      void recordRootEvent(String event, Map<String, Object?> details) {
        final entry = <String, Object?>{
          'event': event,
          'at': DateTime.now().toUtc().toIso8601String(),
          ...details,
        };
        rootTimeline.add(entry);
        debugPrint('PRIVI_TEST_ROOT ${jsonEncode(entry)}');
      }

      final lockEvents = container.listen(
        lockControllerProvider,
        (previous, next) {
          recordRootEvent('lock-state', {
            'from': previous?.status.name,
            'to': next.status.name,
          });
        },
        fireImmediately: true,
      );
      final pipEvents = container
          .read(pictureInPictureGatewayProvider)
          .events
          .listen((event) {
        recordRootEvent('native-pip', {
          'type': event.type.name,
          'session': event.sessionId,
        });
      });

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
          // Native lifecycle transitions can stop Flutter frames. Await real
          // time and let only the application's own requests drive rendering.
          await Future<void>.delayed(const Duration(milliseconds: 100));
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
        final playerId = controller.playerId;
        final advanced = AdvancedVideoController(controller);
        addTearDown(advanced.dispose);
        int rates() =>
            playback.rates.where((entry) => entry.$1 == playerId).length;
        int seeks() =>
            playback.seeks.where((entry) => entry.$1 == playerId).length;
        int pauses() => playback.pauses.where((id) => id == playerId).length;
        final originalSpeed = controller.value.playbackSpeed;
        final initialRates = rates();
        final initialSeeks = seeks();
        final initialPauses = pauses();
        Offset blankPoint() {
          final rect = tester.getRect(find.byType(VideoGestureSurface));
          return Offset(
            rect.left + rect.width * .2,
            rect.top + rect.height * .35,
          );
        }

        Future<void> toggleControls(bool visible) async {
          await nativeInput(tester, 'tap', blankPoint());
          await waitFor(
            () =>
                find.byTooltip('Player settings').evaluate().isNotEmpty ==
                visible,
            'Real Android blank tap must ${visible ? 'show' : 'hide'} controls',
          );
        }

        Future<Map<String, String>> diagnostics(String label) =>
            recordDiagnostics(controller, advanced, label);

        Map<String, Object?> rootUiWitness() {
          final lock = container.read(lockControllerProvider);
          final state = container.read(pictureInPictureControllerProvider);
          final content = find.byKey(
            const ValueKey('vault-content-interaction'),
            skipOffstage: false,
          );
          final ignoring = content.evaluate().isEmpty
              ? null
              : tester.widget<IgnorePointer>(content).ignoring;
          return {
            'lock_status': lock.status.name,
            'lock_overlay_count': find
                .byKey(
                  const ValueKey('vault-lock-overlay'),
                  skipOffstage: false,
                )
                .evaluate()
                .length,
            'lock_screen_count':
                find.byType(LockScreen, skipOffstage: false).evaluate().length,
            'content_ignoring': ignoring,
            'retained_route_visible':
                find.byKey(const Key('native-pip-route')).evaluate().isNotEmpty,
            'same_provider_container': content.evaluate().isNotEmpty &&
                identical(
                  ProviderScope.containerOf(
                    tester.element(content),
                    listen: false,
                  ),
                  container,
                ),
            'pip_active': state.isActive,
            'pip_grant': state.grantActive,
            'lifecycle': binding.lifecycleState?.name,
            'scheduled_frame': binding.hasScheduledFrame,
          };
        }

        bool rootIsUnlocked(Map<String, Object?> witness) =>
            witness['lock_status'] == LockStatus.unlocked.name &&
            witness['lock_overlay_count'] == 0 &&
            witness['lock_screen_count'] == 0 &&
            witness['content_ignoring'] == false &&
            witness['retained_route_visible'] == true &&
            witness['same_provider_container'] == true &&
            witness['pip_active'] == false &&
            witness['pip_grant'] == false;

        Future<void> awaitUnlockedRoot(String label) async {
          final watch = Stopwatch()..start();
          while (!rootIsUnlocked(rootUiWitness()) &&
              watch.elapsed < const Duration(seconds: 12)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          final witness = rootUiWitness();
          recordRootEvent(label, witness);
          if (!rootIsUnlocked(witness)) {
            await diagnostics('$label-blocked');
            await deviceAction(tester, {
              'op': 'screenshot',
              'name': '$label-blocked',
              'ui_witness': witness,
            });
          }
          expect(
            rootIsUnlocked(witness),
            isTrue,
            reason:
                'Unlock must remove the real lock UI and restore the retained route: $witness',
          );
        }

        Future<void> movingFrames(
          String label, {
          bool graphicsDiagnostics = false,
          bool surfaceComposition = false,
        }) async {
          final before = rootUiWitness();
          before['native_window'] =
              await recordWindowDiagnostics('$label-first-before');
          expect(
            rootIsUnlocked(before),
            isTrue,
            reason: 'Video sampling requires the unlocked root UI: $before',
          );
          final first = await screenshot(
            tester,
            '$label-first',
            aspect: 180 / 320,
            uiWitness: before,
            graphicsDiagnostics: graphicsDiagnostics,
            surfaceComposition: surfaceComposition,
          );
          await Future<void>.delayed(const Duration(milliseconds: 900));
          final after = rootUiWitness();
          after['native_window'] =
              await recordWindowDiagnostics('$label-second-before');
          expect(
            rootIsUnlocked(after),
            isTrue,
            reason:
                'The root must remain unlocked during video sampling: $after',
          );
          await screenshot(
            tester,
            '$label-second',
            aspect: 180 / 320,
            uiWitness: after,
            compareTo: first['id'] as String,
            surfaceComposition: surfaceComposition,
          );
        }

        Future<void> diagnoseExpandSeekFailure(
          Object original,
          StackTrace originalStack,
        ) async {
          const label = 'diagnostic-expand-failure-seek';
          final report = <String, Object?>{
            'status': 'collecting',
            'original-error': original.toString(),
            'original-stack': originalStack.toString(),
            'player-id': controller.playerId,
            'controller-initialized': controller.value.isInitialized,
            'controller-error': controller.value.errorDescription,
            'interpretation': 'This seek can trigger native events and Flutter '
                'frames. PNG recovery alone does not prove keyframe causality; '
                'the original failure is always retained.',
          };
          metrics['pip_expand_failure_seek_probe'] = report;
          report['scene-elapsed-ms'] = sceneWatch.elapsedMilliseconds;
          // Existing bounded diagnostics/two captures can take about 93s in
          // total. Reserve two minutes of this test's unchanged 4m deadline,
          // including cleanup, so the original failure can still be rethrown.
          if (sceneWatch.elapsed >= const Duration(minutes: 2)) {
            report['status'] = 'not-executed';
            report['reasons'] = ['insufficient-original-test-deadline-budget'];
            return;
          }
          report['window-before'] =
              await recordWindowDiagnostics('$label-before');
          final before = await diagnostics('$label-position')
              .timeout(const Duration(seconds: 3));
          final positionProbe = (metrics['native_diagnostics_probes']
                  as Map<String, dynamic>)['$label-position']
              as Map<String, dynamic>;
          final position = positionProbe['native-position-ms'] as int?;
          final confirmed = await diagnostics('$label-confirm-input')
              .timeout(const Duration(seconds: 3));
          final state = container.read(pictureInPictureControllerProvider);
          final window = report['window-before'] as Map<String, dynamic>;
          final witness = rootUiWitness();
          report['ui-before'] = witness;
          report['native-before'] = before;
          report['native-confirm-input'] = confirmed;
          report['position-sample'] = positionProbe;
          report['controller-error'] = controller.value.errorDescription;
          final sameInput = [
            'input-reopen-count',
            'surface-generation',
            'active-view-id',
          ].every(
            (key) => before[key] != null && before[key] == confirmed[key],
          );
          final reasons = <String>[
            if (!controller.value.isInitialized || controller.value.hasError)
              'controller-uninitialized-or-failed',
            if (confirmed['native-player-created'] != 'true' ||
                !['3', '4'].contains(confirmed['native-player-state']))
              'no-active-native-input',
            if (confirmed['native-is-seekable'] != 'true')
              'seekability-${confirmed['native-is-seekable'] ?? 'unknown'}',
            if (position == null ||
                position < 0 ||
                position >= controller.value.duration.inMilliseconds)
              'no-valid-native-position',
            if (!sameInput) 'input-changed-during-position-sample',
            if (confirmed['pending-seek-ms'] != 'none')
              'native-seek-already-pending',
            if (!identical(state.controller, controller) ||
                state.currentMediaId != item.id)
              'controller-or-media-changed',
            if (!rootIsUnlocked(witness) ||
                !pip.canPlay(controller: controller, mediaId: item.id) ||
                confirmed['presentation-allowed'] != 'true' ||
                window['activity-window-focused'] != true ||
                window['screen-interactive'] != true ||
                window['keyguard-locked'] != false ||
                window['native-cover-present'] != false)
              'playback-not-authorized',
          ];
          if (reasons.isNotEmpty) {
            report['status'] = 'not-executed';
            report['reasons'] = reasons;
            return;
          }
          report['command'] = 'controller.seekTo';
          report['target-ms'] = position;
          report['command-at'] = DateTime.now().toUtc().toIso8601String();
          report['status'] = 'seek-issued';
          try {
            await controller
                .seekTo(Duration(milliseconds: position!))
                .timeout(const Duration(seconds: 3));
            await waitFor(
              () =>
                  controller.value.isInitialized && controller.value.isPlaying,
              'Diagnostic seek must retain the existing playing controller',
            );
            await diagnostics('$label-after-seek')
                .timeout(const Duration(seconds: 3));
            await movingFrames(label, surfaceComposition: true);
            report['status'] = 'completed-original-failure-retained';
          } finally {
            try {
              report['native-after'] = await diagnostics('$label-after-samples')
                  .timeout(const Duration(seconds: 3));
              final after = report['native-after'] as Map<String, String>;
              final sameInputAfter = [
                'input-reopen-count',
                'surface-generation',
                'active-view-id',
              ].every((key) => confirmed[key] == after[key]);
              report['input-identity-preserved'] = sameInputAfter;
              if (!sameInputAfter) {
                report['status'] =
                    'inconclusive-input-changed-original-failure-retained';
              }
            } catch (error, stack) {
              report['after-diagnostics-error'] = error.toString();
              report['after-diagnostics-stack'] = stack.toString();
            }
          }
        }

        // The Android SurfaceView must pass the actual blank touch through.
        await toggleControls(false);
        await toggleControls(true);
        await toggleControls(false);
        final heldAt = DateTime.now();
        await nativeInput(tester, 'down', blankPoint());
        try {
          await waitFor(
            () =>
                controller.value.playbackSpeed == 2 &&
                rates() == initialRates + 1 &&
                find.text('2x').evaluate().length == 1,
            'Real Android long press must apply 2x and render its badge',
          );
          expect(find.text('2x'), findsOneWidget);
          expect(find.byTooltip('Player settings'), findsNothing);
          await diagnostics('hold-2x-start');
          final first = await screenshot(tester, 'hold-2x-first');
          await Future<void>.delayed(const Duration(milliseconds: 2100));
          expect(find.text('2x'), findsOneWidget);
          await screenshot(
            tester,
            'hold-2x-second',
            compareTo: first['id'] as String,
          );
          await diagnostics('hold-2x-end');
          expect(rates(), initialRates + 1);
          expect(seeks(), initialSeeks);
          expect(controller.value.isPlaying, isTrue);
          metrics['native_hold_duration_ms'] =
              DateTime.now().difference(heldAt).inMilliseconds;
        } finally {
          await nativeInput(tester, 'up', blankPoint());
        }
        await waitFor(
          () =>
              controller.value.playbackSpeed == originalSpeed &&
              rates() == initialRates + 2 &&
              find.text('2x').evaluate().isEmpty,
          'Android UP must restore the previous speed once and remove its badge',
        );
        expect(find.text('2x'), findsNothing);
        await diagnostics('hold-release-1x');
        await movingFrames('hold-release-1x');

        // Exercise the user-facing settings slider, not a facade speed setter.
        await toggleControls(true);
        await tester.tap(find.byTooltip('Player settings'));
        await tester.pump(const Duration(milliseconds: 300));
        final speedSlider = find.byWidgetPredicate(
          (widget) => widget is Slider && widget.min == .25 && widget.max == 4,
        );
        await tester.ensureVisible(speedSlider);
        await tester.pump();
        final speedRect = tester.getRect(speedSlider);
        // Material Slider's track has 24 logical pixels of horizontal padding.
        await tester.tapAt(
          Offset(
            speedRect.left +
                24 +
                (speedRect.width - 48) * ((2 - .25) / (4 - .25)),
            speedRect.center.dy,
          ),
        );
        await waitFor(
          () => controller.value.playbackSpeed == 2,
          'Settings slider must select 2x',
        );
        await tester.ensureVisible(find.byTooltip('Close'));
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pump(const Duration(milliseconds: 300));
        if (find.byTooltip('Player settings').evaluate().isNotEmpty) {
          await toggleControls(false);
        }
        await diagnostics('menu-2x');
        await movingFrames('menu-2x');
        // Restore via the same real settings control.
        await toggleControls(true);
        await tester.tap(find.byTooltip('Player settings'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(speedSlider);
        await tester.pump();
        final restoreRect = tester.getRect(speedSlider);
        await tester.tapAt(
          Offset(
            restoreRect.left +
                24 +
                (restoreRect.width - 48) * ((1 - .25) / (4 - .25)),
            restoreRect.center.dy,
          ),
        );
        await waitFor(
          () => controller.value.playbackSpeed == 1,
          'Settings slider must restore 1x',
        );
        await tester.ensureVisible(find.byTooltip('Close'));
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pump(const Duration(milliseconds: 300));
        if (find.byTooltip('Player settings').evaluate().isNotEmpty) {
          await toggleControls(false);
        }
        await diagnostics('menu-release-1x');
        await movingFrames('menu-release-1x');

        final swipe = await tester.startGesture(blankPoint());
        await swipe.moveBy(const Offset(-60, 0));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(controller.value.isPlaying, isTrue);
        expect(pauses(), initialPauses);
        expect(seeks(), initialSeeks);
        await swipe.moveBy(const Offset(-20, 0));
        await swipe.up();
        await waitFor(
          () => seeks() == initialSeeks + 1,
          'Releasing a swipe must submit one final native seek',
        );
        expect(controller.value.isPlaying, isTrue);
        metrics['interaction_command_probes'] = {
          'hold_and_menu_speed_commands': rates() - initialRates,
          'hold_and_swipe_seek_commands': seeks() - initialSeeks,
          'hold_and_swipe_pause_commands': pauses() - initialPauses,
        };
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
            await nativeInput(tester, 'tap', blankPoint());
          }
          // The viewport also recognizes double taps; a single tap takes
          // effect only after that gesture's decision timeout.
          await waitFor(
            () => find.byTooltip('Orientation').evaluate().isNotEmpty,
            'A single tap must reveal the $direction controls',
          );
          await screenshot(tester, 'player-$direction-controls');
          await toggleControls(false);
          await movingFrames('orientation-$direction');
          expect(tester.takeException(), isNull);
        }
        await PlaybackOrientationService.instance.setMode('portrait');
        await waitFor(
          () =>
              tester.view.physicalSize.height > tester.view.physicalSize.width,
          'Device must return to portrait before PiP entry',
        );
        // User Pause updates both playlist intent and the native facade. Surface
        // recreation must restore that paused picture without changing intent.
        await toggleControls(true);
        await nativeInput(
          tester,
          'tap',
          tester.getCenter(find.byTooltip('Pause')),
        );
        await waitFor(
          () => !controller.value.isPlaying,
          'The actual Pause button must pause playback',
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await toggleControls(false);
        await toggleControls(true);
        await toggleControls(false);
        await PlaybackOrientationService.instance.setMode('landscape');
        await waitFor(
          () =>
              tester.view.physicalSize.width > tester.view.physicalSize.height,
          'Paused video must rotate to landscape',
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
        final pausedFirst = await screenshot(tester, 'paused-rotation-first');
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await screenshot(
          tester,
          'paused-rotation-second',
          compareTo: pausedFirst['id'] as String,
          paused: true,
        );
        expect(controller.value.isPlaying, isFalse);
        final pausedProbe = await diagnostics('paused-after-surface-restore');
        expect(pausedProbe['native-is-playing'], 'false');
        expect(pausedProbe['play-requested'], 'false');
        await PlaybackOrientationService.instance.setMode('portrait');
        await waitFor(
          () =>
              tester.view.physicalSize.height > tester.view.physicalSize.width,
          'Paused video must rotate back to portrait',
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await screenshot(tester, 'paused-portrait-restored');
        expect(controller.value.isPlaying, isFalse);
        await toggleControls(true);
        await nativeInput(
          tester,
          'tap',
          tester.getCenter(find.byTooltip('Play')),
        );
        await waitFor(
          () => controller.value.isPlaying,
          'The actual Play button must resume the retained video',
        );
        await toggleControls(false);
        await movingFrames('user-play-after-paused-rotation');
        await const MethodChannel('com.privi.app/window')
            .invokeMethod<void>('startCompositionDiagnostics')
            .timeout(const Duration(seconds: 5));
        for (final action in ['EXPAND', 'SCREEN_OFF']) {
          (container.read(lockControllerProvider.notifier) as _IntegrationLock)
              .unlockForTest();
          await awaitUnlockedRoot('before-${action.toLowerCase()}');
          await waitFor(
            () => pip.canPlay(controller: controller, mediaId: item.id),
            'PiP entry requires a focused foreground Activity',
          );
          debugPrint('PiP entry lifecycle: ${binding.lifecycleState}');
          expect(
            await pip.playIfAllowed(controller: controller, mediaId: item.id),
            isTrue,
          );
          await pip.enter().timeout(const Duration(seconds: 6));
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
          await Future<void>.delayed(const Duration(milliseconds: 800));
          // PiP moves the Activity window relative to the full display. Keep
          // its raw composition for the reviewer; the fullscreen content ROI
          // must not accidentally measure launcher/OS animation as video motion.
          await deviceAction(tester, {
            'op': 'screenshot',
            'name': 'native-pip-${action.toLowerCase()}',
          });
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
          await waitFor(
            () => binding.lifecycleState == AppLifecycleState.resumed,
            'Fullscreen return must resume the Activity before the next entry',
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
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
          final fullscreenWindow = await recordWindowDiagnostics(
            'native-fullscreen-${action.toLowerCase()}',
          );
          await deviceAction(tester, {
            'op': 'capture',
            'name': 'native-fullscreen-${action.toLowerCase()}',
            ...await physicalViewport(tester),
            'expectNoVideo': true,
            'native_window_witness': fullscreenWindow,
            if (action == 'SCREEN_OFF') 'graphicsDiagnostics': true,
          });
          (container.read(lockControllerProvider.notifier) as _IntegrationLock)
              .unlockForTest();
          await awaitUnlockedRoot('after-${action.toLowerCase()}');
          await waitFor(
            () => pip.canPlay(controller: controller, mediaId: item.id),
            'Unlocked retained route must regain playback ownership',
          );
          expect(
            await pip.playIfAllowed(controller: controller, mediaId: item.id),
            isTrue,
          );
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (find.byTooltip('Player settings').evaluate().isNotEmpty) {
            await toggleControls(false);
          }
          await diagnostics('surface-before-${action.toLowerCase()}-capture');
          try {
            await movingFrames(
              'surface-after-${action.toLowerCase()}',
              graphicsDiagnostics: action == 'SCREEN_OFF',
            );
          } catch (error, stack) {
            if (action == 'EXPAND') {
              try {
                await diagnoseExpandSeekFailure(error, stack);
              } catch (diagnosticError, diagnosticStack) {
                final report = metrics.putIfAbsent(
                  'pip_expand_failure_seek_probe',
                  () => <String, Object?>{},
                ) as Map<String, Object?>;
                report['status'] =
                    'diagnostic-failed-original-failure-retained';
                report['diagnostic-error'] = diagnosticError.toString();
                report['diagnostic-stack'] = diagnosticStack.toString();
              }
            }
            Error.throwWithStackTrace(error, stack);
          }
          await diagnostics('surface-after-${action.toLowerCase()}');
        }
        metrics['pip_expand_and_screen_off'] = 'passed';
      } finally {
        // Detach the read-only observer before removing the scene. A stop
        // failure must still fail this test without replacing its original
        // exception or preventing controller/database cleanup.
        try {
          await const MethodChannel('com.privi.app/window')
              .invokeMethod<void>('stopCompositionDiagnostics')
              .timeout(const Duration(seconds: 5));
        } catch (error, stackTrace) {
          metrics['composition_diagnostics_stop_error'] = error.toString();
          addTearDown(() => Error.throwWithStackTrace(error, stackTrace));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final platform = playback;
        await waitFor(
          () => platform.activePlayerCount == 0,
          'Leaving PlayerScreen must release every decoder',
        );
        lockEvents.close();
        await pipEvents.cancel();
        container.dispose();
        await database.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// Counts calls at the real bridge, rather than video_player's optimistic value.
class _InteractionPlaybackPlatform extends LibVlcVideoPlayerPlatform {
  final _livePlayers = <int>{};
  int get activePlayerCount => _livePlayers.length;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = await super.createWithOptions(options);
    if (id != null) _livePlayers.add(id);
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    await super.dispose(playerId);
    _livePlayers.remove(playerId);
  }

  final rates = <(int, double)>[];
  final seeks = <(int, Duration)>[];
  final pauses = <int>[];

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    rates.add((playerId, speed));
    return super.setPlaybackSpeed(playerId, speed);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) {
    seeks.add((playerId, position));
    return super.seekTo(playerId, position);
  }

  @override
  Future<void> pause(int playerId) {
    pauses.add(playerId);
    return super.pause(playerId);
  }
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

/// LiveTest's fullyLive policy schedules another engine frame after every draw,
/// even when the application is idle. That masks a SurfaceView which only
/// advances while Flutter submits frames. Benchmark disables that extra loop;
/// the synchronous scheduling overrides still run SchedulerBinding's real
/// application-request path, including hasScheduledFrame/lifecycle bookkeeping.
/// Explicit tester.pump is reserved for setup and other deliberate test actions.
class ApplicationFrameIntegrationTestBinding
    extends IntegrationTestWidgetsFlutterBinding {
  ApplicationFrameIntegrationTestBinding() {
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
    // ADB input is a device-source event. WidgetTester's default inspector
    // consumes it unless real device events explicitly reach the application.
    shouldPropagateDevicePointerEvents = true;
  }

  @override
  void scheduleFrame() {
    final previous = framePolicy;
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    try {
      super.scheduleFrame();
    } finally {
      framePolicy = previous;
    }
  }

  @override
  void scheduleForcedFrame() {
    final previous = framePolicy;
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    try {
      super.scheduleForcedFrame();
    } finally {
      framePolicy = previous;
    }
  }
}

/// Converts FlutterView logical coordinates to Android display physical pixels.
class _ScreenCoordinates {
  const _ScreenCoordinates(this.devicePixelRatio, this.screenOffset);

  final double devicePixelRatio;
  final Offset screenOffset;

  Offset toScreen(Offset logical) => logical * devicePixelRatio + screenOffset;

  Map<String, Object> get evidence => {
        'device_pixel_ratio': devicePixelRatio,
        'flutter_view_screen_offset_px': [screenOffset.dx, screenOffset.dy],
      };
}
