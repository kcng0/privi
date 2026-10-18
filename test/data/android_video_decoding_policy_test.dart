import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:privi/data/services/playback/media_kit_video_player_platform.dart';

void main() {
  test('only common 8-bit SDR copy-back output is eligible', () {
    for (final pixel in ['yuv420p', 'yuvj420p', 'nv12', 'nv21']) {
      for (final color in [
        ('bt.709', 'bt.709'),
        ('bt.601', 'bt.601-525'),
        ('bt.601', 'bt.601-625'),
      ]) {
        for (final gamma in ['bt.1886', 'srgb']) {
          expect(
            _eligible({
              'pixelFormat': pixel,
              'colorMatrix': color.$1,
              'primaries': color.$2,
              'gamma': gamma,
            }),
            isTrue,
            reason: '$pixel / $color / $gamma',
          );
        }
      }
    }
  });

  final excluded = <String, Map<String, String>>{
    'HDR10': {
      'pixelFormat': 'p010',
      'colorMatrix': 'bt.2020-ncl',
      'primaries': 'bt.2020',
      'gamma': 'pq',
    },
    'HLG even with 8-bit decoded output': {'gamma': 'hlg'},
    'Dolby Vision PQ base layer': {
      'colorMatrix': 'bt.2020-ncl',
      'primaries': 'bt.2020',
      'gamma': 'pq',
    },
    'PQ even with SDR primaries': {'gamma': 'pq'},
    'SDR BT.2020 wide gamut': {
      'colorMatrix': 'bt.2020-ncl',
      'primaries': 'bt.2020',
    },
    'Display P3 wide gamut': {'primaries': 'display-p3'},
    '10-bit planar SDR': {'pixelFormat': 'yuv420p10'},
    '10-bit semi-planar SDR': {'pixelFormat': 'p010'},
    '12-bit SDR': {'pixelFormat': 'yuv420p12'},
    'unknown hardware pixel format': {'pixelFormat': 'mediacodec'},
    'non-allowlisted format': {'pixelFormat': 'yuv444p'},
    'unknown matrix': {'colorMatrix': 'auto'},
    'unknown primaries': {'primaries': 'auto'},
    'unknown transfer': {'gamma': 'auto'},
    'unmatched matrix and primaries': {'colorMatrix': 'bt.601'},
    'FFmpeg color name is not an mpv name': {'colorMatrix': 'bt709'},
    'emulator or hardware disabled': {'hwdec': 'no'},
    'explicit user policy': {'hwdec': 'auto'},
    'software fallback': {'currentHwdec': 'no'},
    'already direct': {'currentHwdec': 'mediacodec'},
  };
  for (final entry in excluded.entries) {
    test('preserves existing decoding for ${entry.key}', () {
      expect(_eligible(entry.value), isFalse);
    });
  }
  for (final field in _knownSdr.keys) {
    test('missing $field cannot opt in', () {
      expect(_eligible({field: ''}), isFalse);
    });
  }

  group('paused initialization', () {
    late _NativeProperties native;
    late MediaKitAdvancedVideoPort port;
    setUp(() {
      native = _NativeProperties();
      port = MediaKitAdvancedVideoPort(
        native.player,
        readProperty: native.read,
        writeProperty: native.write,
      );
    });
    tearDown(() async {
      await port.close();
      await native.player.dispose();
    });

    test('waits for dimensions and duration, then verifies one paused switch',
        () async {
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls, isEmpty);
      native.state = native.state.copyWith(width: 1920, height: 1080);
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls, isEmpty);
      native.state =
          native.state.copyWith(duration: const Duration(seconds: 30));
      // Dart videoParams has not arrived: the decision uses native metadata.
      expect(native.state.videoParams.pixelformat, isNull);
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls, [
        'read hwdec',
        'read hwdec-current',
        'read video-dec-params/pixelformat',
        'read video-dec-params/colormatrix',
        'read video-dec-params/primaries',
        'read video-dec-params/gamma',
        'read pause',
        'write hwdec=mediacodec,auto-safe',
        'read hwdec',
      ]);
      native.calls.clear();
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls, ['read hwdec']);
      expect(native.state.playing, isFalse);
    });

    test('cannot switch a playing player or an unpaused native engine',
        () async {
      native.makeReady();
      native.state = native.state.copyWith(playing: true);
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls, isEmpty);
      native.state = native.state.copyWith(playing: false);
      native.beforeRead = (name) async {
        if (name == 'video-dec-params/gamma') native.properties['pause'] = 'no';
      };
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls.where((call) => call.startsWith('write ')), isEmpty);
    });

    test('unavailable metadata, emulator and software fallback do not write',
        () async {
      native.makeReady();
      native.properties.remove('video-dec-params/gamma');
      await port.configureAndroidDecodingAfterMetadata();
      native.properties['hwdec'] = 'no';
      await port.configureAndroidDecodingAfterMetadata();
      native.properties['hwdec'] = 'auto-safe';
      native.properties['hwdec-current'] = 'no';
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls.where((call) => call.startsWith('write ')), isEmpty);
    });

    test(
        'guessed SDR output cannot opt unknown raw colors into direct decoding',
        () async {
      native.makeReady();
      native.properties.addAll({
        'video-dec-params/colormatrix': 'auto',
        'video-dec-params/primaries': 'auto',
        'video-dec-params/gamma': 'auto',
        'video-params/pixelformat': 'yuv420p',
        'video-params/colormatrix': 'bt.709',
        'video-params/primaries': 'bt.709',
        'video-params/gamma': 'bt.1886',
      });
      await port.configureAndroidDecodingAfterMetadata();
      expect(native.calls.where((call) => call.startsWith('write ')), isEmpty);
      expect(native.calls, isNot(contains('read video-params/primaries')));
    });

    test('does not finish before native configuration is read back', () async {
      native.makeReady();
      final reading = Completer<void>();
      final release = Completer<void>();
      native.beforeRead = (name) async {
        if (name == 'hwdec' &&
            native.properties[name] == 'mediacodec,auto-safe') {
          reading.complete();
          await release.future;
        }
      };
      var completed = false;
      final configured = port.configureAndroidDecodingAfterMetadata().then((_) {
        completed = true;
      });
      await reading.future;
      expect(completed, isFalse);
      release.complete();
      await configured;
      expect(completed, isTrue);
    });

    test('rejected configuration remains diagnosable and fails initialization',
        () async {
      native.makeReady();
      native.ignoreWrites = true;
      await expectLater(
        port.configureAndroidDecodingAfterMetadata(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'native rejection',
            contains('read back auto-safe'),
          ),
        ),
      );
      expect(port.value.error, contains('mpv rejected hwdec'));
      expect(native.properties['hwdec'], 'auto-safe');
    });
  });
}

const _knownSdr = {
  'hwdec': 'auto-safe',
  'currentHwdec': 'mediacodec-copy',
  'pixelFormat': 'yuv420p',
  'colorMatrix': 'bt.709',
  'primaries': 'bt.709',
  'gamma': 'bt.1886',
};

bool _eligible(Map<String, String> overrides) {
  final values = {..._knownSdr, ...overrides};
  return shouldPreferDirectAndroidDecoding(
    hwdec: values['hwdec']!,
    currentHwdec: values['currentHwdec']!,
    pixelFormat: values['pixelFormat']!,
    colorMatrix: values['colorMatrix']!,
    primaries: values['primaries']!,
    gamma: values['gamma']!,
  );
}

class _NativeProperties extends PlatformPlayer {
  _NativeProperties() : super(configuration: const PlayerConfiguration()) {
    player = Player(platformPlayer: this);
  }

  late final Player player;
  final calls = <String>[];
  final properties = {
    'hwdec': 'auto-safe',
    'hwdec-current': 'mediacodec-copy',
    'video-dec-params/pixelformat': 'yuv420p',
    'video-dec-params/colormatrix': 'bt.709',
    'video-dec-params/primaries': 'bt.709',
    'video-dec-params/gamma': 'bt.1886',
    'pause': 'yes',
  };
  bool ignoreWrites = false;
  Future<void> Function(String)? beforeRead;

  void makeReady() {
    state = state.copyWith(
      width: 1920,
      height: 1080,
      duration: const Duration(seconds: 30),
    );
  }

  Future<String> read(String name) async {
    calls.add('read $name');
    await beforeRead?.call(name);
    return properties[name] ?? '';
  }

  Future<void> write(String name, String value) async {
    calls.add('write $name=$value');
    if (!ignoreWrites) properties[name] = value;
  }
}
