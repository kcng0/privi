import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/playback_display_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlaybackDisplayService service;
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    const channel = MethodChannel('com.privi.app/window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getBrightness' => 0.25,
        'getVolume' => 0.8,
        _ => null,
      };
    });
    service = PlaybackDisplayService(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.privi.app/window'),
      null,
    );
  });

  test('reads and writes clamped brightness and volume', () async {
    expect(await service.getBrightness(), 0.25);
    expect(await service.getVolume(), 0.8);

    await service.setBrightness(1.4);
    await service.setVolume(-0.2);
    await service.resetBrightness();

    expect(calls.map((call) => call.method), [
      'getBrightness',
      'getVolume',
      'setBrightness',
      'setVolume',
      'resetBrightness',
    ]);
    expect(calls[2].arguments, {'value': 1.0});
    expect(calls[3].arguments, {'value': 0.0});
  });
}
