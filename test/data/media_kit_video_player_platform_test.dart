import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:privi/data/services/playback/media_kit_video_player_platform.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  test('duration and a single dimension cannot initialize video', () async {
    final changes = StreamController<void>.broadcast();
    final errors = StreamController<String>.broadcast();
    addTearDown(changes.close);
    addTearDown(errors.close);
    var duration = Duration.zero;
    var size = Size.zero;
    var completed = false;
    final ready = waitForPlaybackMetadata(
      duration: () => duration,
      displaySize: () => size,
      metadataChanges: [changes.stream],
      errors: errors.stream,
    ).then((event) {
      completed = true;
      return event;
    });
    duration = const Duration(minutes: 2);
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    size = const Size(1920, 0);
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    size = const Size(1080, 1920);
    changes.add(null);
    final event = await ready;
    expect(event.size, const Size(1080, 1920));
    expect(event.rotationCorrection, 0);
    expect(event.duration, const Duration(minutes: 2));
    expect(changes.hasListener, isFalse);
    expect(errors.hasListener, isFalse);
  });

  test('zero dimensions time out with metadata diagnostics and unsubscribe',
      () async {
    final changes = StreamController<void>.broadcast();
    final errors = StreamController<String>.broadcast();
    addTearDown(changes.close);
    addTearDown(errors.close);
    await expectLater(
      waitForPlaybackMetadata(
        duration: () => const Duration(seconds: 30),
        displaySize: () => Size.zero,
        metadataChanges: [changes.stream],
        errors: errors.stream,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.message,
          'diagnostics',
          allOf(contains('30000ms'), contains('0.0×0.0')),
        ),
      ),
    );
    expect(changes.hasListener, isFalse);
    expect(errors.hasListener, isFalse);
  });

  test('display dimensions arriving first wait for finite file duration',
      () async {
    final changes = StreamController<void>.broadcast();
    final errors = StreamController<String>.broadcast();
    addTearDown(changes.close);
    addTearDown(errors.close);
    var duration = Duration.zero;
    var size = Size.zero;
    var completed = false;
    final ready = waitForPlaybackMetadata(
      duration: () => duration,
      displaySize: () => size,
      metadataChanges: [changes.stream],
      errors: errors.stream,
    ).then((event) {
      completed = true;
      return event;
    });
    size = const Size(1080, 1920);
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    duration = const Duration(seconds: 42);
    changes.add(null);
    final event = await ready;
    expect(event.duration, const Duration(seconds: 42));
    expect(event.size, const Size(1080, 1920));
    expect(changes.hasListener, isFalse);
    expect(errors.hasListener, isFalse);
  });

  test('missing file duration times out even with known display dimensions',
      () async {
    await expectLater(
      waitForPlaybackMetadata(
        duration: () => Duration.zero,
        displaySize: () => const Size(1080, 1920),
        metadataChanges: const [],
        errors: const Stream<String>.empty(),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.message,
          'diagnostics',
          allOf(contains('duration=0ms'), contains('1080.0×1920.0')),
        ),
      ),
    );
  });

  test('readiness propagates decode failure and cancels metadata listeners',
      () async {
    final changes = StreamController<void>.broadcast();
    final errors = StreamController<String>.broadcast();
    addTearDown(changes.close);
    addTearDown(errors.close);
    final ready = waitForPlaybackMetadata(
      duration: () => Duration.zero,
      displaySize: () => Size.zero,
      metadataChanges: [changes.stream],
      errors: errors.stream,
    );
    final expectation = expectLater(ready, throwsA(isA<PlatformException>()));
    errors.add('decoder initialization failed');
    await expectation;
    expect(changes.hasListener, isFalse);
    expect(errors.hasListener, isFalse);
  });

  test('mpv display size includes SAR and rotation without a second transform',
      () {
    final platform = _MetadataPlayer();
    final player = Player(platformPlayer: platform);
    addTearDown(player.dispose);
    platform.state = const PlayerState(
      width: 1080,
      height: 1920,
      videoParams: VideoParams(dw: 1920, dh: 1080, rotate: 90),
    );
    expect(initializedEventFromPlayer(player).size, const Size(1080, 1920));
    expect(initializedEventFromPlayer(player).rotationCorrection, 0);
    platform.state = const PlayerState(
      width: 768,
      height: 576,
      videoParams: VideoParams(w: 720, h: 576, dw: 768, dh: 576),
    );
    expect(initializedEventFromPlayer(player).size, const Size(768, 576));
    platform.state = const PlayerState(
      videoParams: VideoParams(dw: 1920, dh: 1080, rotate: 270),
    );
    expect(() => initializedEventFromPlayer(player), throwsStateError);
  });

  test('maps file, network, content, and asset URIs for mpv', () {
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.file,
          uri: '/tmp/clip.mp4',
        ),
      ),
      'file:///tmp/clip.mp4',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.file,
          uri: 'file:///tmp/clip.mp4',
        ),
      ),
      'file:///tmp/clip.mp4',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.network,
          uri: 'https://example.com/a.mkv',
        ),
      ),
      'https://example.com/a.mkv',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.contentUri,
          uri: 'content://media/external/video/1',
        ),
      ),
      'content://media/external/video/1',
    );
    expect(
      mediaUriForDataSource(
        DataSource(
          sourceType: DataSourceType.asset,
          asset: 'videos/demo.mp4',
        ),
      ),
      'asset:///videos/demo.mp4',
    );
  });

  test('detects MediaCodec capability errors including High@L5.2 AVC', () {
    const exo =
        'Video player had error b1.k: MediaCodecVideoRenderer error, index=0, '
        'avc.1.640034, 4946019, und, [2560, 1440, 120.0, ColorInfo(Unset color '
        'space, Unset color range, Unset color transfer, false, 8bit Luma, 8bit '
        'Chrome)].  [-1, -1]), format_supported=NO_EXCEEDS_CAPABILITIES, null, '
        'null)';
    const reported =
        'video/avc, avc1.640034, 5340298, und no exceeds capabilities';
    expect(isDecoderCapabilityError(exo), isTrue);
    expect(isDecoderCapabilityError(reported), isTrue);
    expect(isDecoderCapabilityError('Failed to open file'), isFalse);
  });
}

class _MetadataPlayer extends PlatformPlayer {
  _MetadataPlayer() : super(configuration: const PlayerConfiguration());
}
