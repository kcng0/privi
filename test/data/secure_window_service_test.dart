import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/secure_window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.privi.app/window');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('FLAG_SECURE platform failures remain visible to the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) => throw PlatformException(code: 'window_error'),
    );

    await expectLater(
      SecureWindowService().setFlagSecure(true),
      throwsA(isA<PlatformException>()),
    );
  });
}
