import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/intent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    MethodChannelExternalPlayerGateway.channelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('opens through native activity-result channel', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);

    final launched = await gateway.open(
      filePath: '/vault/video.mp4',
      mimeType: 'video/mp4',
    );

    expect(launched, isTrue);
    expect(receivedCall?.method, 'openExternalPlayer');
    expect(receivedCall?.arguments, {
      'path': '/vault/video.mp4',
      'mimeType': 'video/mp4',
    });
  });

  test('clean return signal can only be consumed once', () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('intent_returned_cleanly'),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeCleanReturn(), isTrue);
    expect(gateway.takeCleanReturn(), isFalse);
  });
}
