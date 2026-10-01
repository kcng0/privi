import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  late _NativeHarness native;
  late AndroidVideoController output;
  late List<String> methods;
  Future<Object?> Function(MethodCall)? onCall;

  setUp(() {
    native = _NativeHarness();
    output = AndroidVideoController.forTesting(native.player, handle: 42);
    methods = [];
    onCall = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      methods.add(call.method);
      return onCall?.call(call) ?? Future<Object?>.value();
    });
  });

  tearDown(() async {
    await native.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> drain() =>
      output.lock.synchronized(() {}).timeout(const Duration(seconds: 2));

  Future<void> resizeFromNative() async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('VideoOutput.Resize', {
          'handle': 42,
          'id': 9,
          'wid': 123,
          'rect': {'left': 0, 'top': 0, 'width': 180, 'height': 320},
        }),
      ),
      (_) {},
    );
  }

  test('late surface reply and queued metadata cannot revive a released output',
      () async {
    final started = Completer<void>();
    final reply = Completer<Object?>();
    onCall = (call) {
      if (call.method == 'VideoOutputManager.SetSurfaceSize') {
        started.complete();
        return reply.future;
      }
      return Future<Object?>.value();
    };
    var updates = 0;
    output.rect.addListener(() => updates++);
    native.emitSize(180, 320);
    await started.future.timeout(const Duration(seconds: 2));
    native.emitSize(320, 180);
    await Future<void>.delayed(Duration.zero);

    await native.releaseOutput().timeout(const Duration(seconds: 2));
    await resizeFromNative();
    reply.complete();
    await drain();

    expect(updates, 0);
    expect(methods, [
      'VideoOutputManager.SetSurfaceSize',
      'VideoOutputManager.Dispose',
    ]);
    expect(native.properties, isEmpty);
    expect(native.seeks, isEmpty);
    expect(() => output.rect.addListener(() {}), throwsFlutterError);
  });

  test('metadata waiting for the player handle cannot create a late surface',
      () async {
    final requested = Completer<void>();
    final handle = Completer<int>();
    native.onHandle = () {
      requested.complete();
      return handle.future;
    };
    native.emitSize(180, 320);
    await requested.future.timeout(const Duration(seconds: 2));
    await native.releaseOutput().timeout(const Duration(seconds: 2));
    handle.complete(42);
    await drain();
    expect(methods, ['VideoOutputManager.Dispose']);
  });

  test('a suspended surface-property update stops before touching disposed mpv',
      () async {
    final started = Completer<void>();
    final property = Completer<void>();
    native.onProperty = (_, __) {
      started.complete();
      return property.future;
    };
    final changing = output.widListener();
    await started.future.timeout(const Duration(seconds: 2));
    await native.releaseOutput().timeout(const Duration(seconds: 2));
    property.complete();
    await changing.timeout(const Duration(seconds: 2));
    expect(native.properties, [('vo', 'null')]);
    expect(native.seeks, isEmpty);
  });

  test('the native disposed flag gates callbacks before video release starts',
      () async {
    // NativePlayer sets disposed before invoking PlatformPlayer.release.
    native.disposed = true;
    await output.widListener();
    await output.setProperty('vo', 'null');
    native.emitSize(180, 320);
    await Future<void>.delayed(Duration.zero);
    await drain();
    expect(native.properties, isEmpty);
    expect(native.seeks, isEmpty);
    expect(methods, isEmpty);
  });

  test('seek queued behind Player.dispose rechecks ownership without deadlock',
      () async {
    final propertiesDone = Completer<void>();
    native.onProperty = (_, __) async {
      if (native.properties.length == 4) propertiesDone.complete();
    };
    late Future<void> changing;
    await NativePlayer.lock.synchronized(() async {
      changing = output.widListener();
      await propertiesDone.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      // The real NativePlayer holds this same lock during release callbacks.
      await native.releaseOutput().timeout(const Duration(seconds: 2));
    }).timeout(const Duration(seconds: 2));
    await changing.timeout(const Duration(seconds: 2));
    expect(native.seeks, isEmpty);
    expect(methods, ['VideoOutputManager.Dispose']);
  });

  test('live metadata and surface updates still publish size and preserve seek',
      () async {
    final resized = Completer<void>();
    onCall = (call) async {
      if (call.method == 'VideoOutputManager.SetSurfaceSize') {
        resized.complete();
      }
      return null;
    };
    native.emitSize(180, 320);
    await resized.future.timeout(const Duration(seconds: 2));
    await drain();
    expect(output.rect.value, const Rect.fromLTWH(0, 0, 180, 320));
    await output.widListener().timeout(const Duration(seconds: 2));
    expect(native.seeks, [const Duration(seconds: 7)]);
  });

  test('native disposal errors propagate and notifiers are still released',
      () async {
    onCall = (call) async {
      if (call.method == 'VideoOutputManager.Dispose') {
        throw PlatformException(code: 'dispose_failed');
      }
      return null;
    };
    await expectLater(
      native.releaseOutput(),
      throwsA(isA<PlatformException>()),
    );
    expect(() => output.rect.addListener(() {}), throwsFlutterError);
    await resizeFromNative();
    // The explicit release above already verified the failure; avoid invoking
    // the SDK's generic release-error logger again during test cleanup.
    native.release.clear();
  });
}

class _NativeHarness implements NativePlayer {
  _NativeHarness() {
    _signals.state = const PlayerState(position: Duration(seconds: 7));
    player = Player(platformPlayer: this);
  }

  final _signals = _PlayerSignals();
  late final Player player;
  @override
  PlayerState get state => _signals.state;
  @override
  PlayerStream get stream => _signals.stream;
  @override
  List<Future<void> Function()> get release => _signals.release;
  @override
  bool disposed = false;
  final properties = <(String, String)>[];
  final seeks = <Duration>[];
  Future<int> Function()? onHandle;
  Future<void> Function(String, String)? onProperty;

  @override
  Future<int> get handle => onHandle?.call() ?? Future.value(42);

  void emitSize(int width, int height) => _signals.videoParamsController.add(
        VideoParams(dw: width, dh: height, rotate: 0),
      );

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    if (disposed) throw StateError('Property write after native disposal');
    properties.add((property, value));
    await onProperty?.call(property, value);
  }

  @override
  Future<void> seek(Duration duration, {bool synchronized = true}) async {
    Future<void> perform() async {
      if (disposed) throw StateError('Seek after native disposal');
      seeks.add(duration);
    }

    if (synchronized) {
      await NativePlayer.lock.synchronized(perform);
    } else {
      await perform();
    }
  }

  Future<void> releaseOutput() async {
    disposed = true;
    for (final callback in release) {
      await callback();
    }
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    disposed = true;
    await _signals.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlayerSignals extends PlatformPlayer {
  _PlayerSignals() : super(configuration: const PlayerConfiguration());
}
