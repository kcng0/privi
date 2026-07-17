import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/platform_app_restart_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('restart');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('requests a full process restart', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return <String, Object>{'success': true, 'mode': 'process'};
    });

    await const PlatformAppRestartService().restart();

    expect(receivedCall?.method, 'restartApp');
    expect(receivedCall?.arguments, containsPair('mode', 'process'));
  });

  test('surfaces a rejected process restart', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object>{
        'success': false,
        'mode': 'process',
        'code': 'RESTART_FAILED',
        'message': 'No activity available',
      };
    });

    await expectLater(
      const PlatformAppRestartService().restart(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('RESTART_FAILED: No activity available'),
        ),
      ),
    );
  });
}
