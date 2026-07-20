import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/external_player_gateway.dart';
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

  test('external picture viewer uses the tracked media channel', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);

    final launched = await gateway.open(
      filePath: '/vault/photo.jpg',
      mimeType: 'image/jpeg',
    );

    expect(launched, isTrue);
    expect(receivedCall?.arguments, {
      'path': '/vault/photo.jpg',
      'mimeType': 'image/jpeg',
    });
  });

  test('VLC completion return can only be consumed once', () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('external_player_returned', {
        'resultCode': -1,
        'completionSupported': true,
        'positionMs': 119500,
        'durationMs': 120000,
      }),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeReturn(), ExternalPlayerReturn.completed);
    expect(gateway.takeReturn(), isNull);
  });

  test('early VLC Back is an interrupted return', () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('external_player_returned', {
        'resultCode': -1,
        'completionSupported': true,
        'positionMs': 45000,
        'durationMs': 120000,
      }),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeReturn(), ExternalPlayerReturn.interrupted);
  });

  test('VLC reset-at-end result uses tracked playback duration', () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('external_player_returned', {
        'resultCode': -1,
        'completionSupported': true,
        'positionMs': 0,
        'durationMs': 0,
        'expectedDurationMs': 120000,
        'elapsedMs': 121000,
      }),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeReturn(), ExternalPlayerReturn.completed);
  });

  test('Back during VLC startup does not look like reset-at-end', () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('external_player_returned', {
        'resultCode': -1,
        'completionSupported': true,
        'positionMs': 0,
        'durationMs': 0,
        'expectedDurationMs': 120000,
        'elapsedMs': 1000,
      }),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeReturn(), ExternalPlayerReturn.interrupted);
  });

  test('return without VLC completion metadata is interrupted', () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('external_player_returned', {
        'resultCode': 0,
        'completionSupported': true,
      }),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeReturn(), ExternalPlayerReturn.interrupted);
  });

  test('completion-shaped metadata from an unknown player is interrupted',
      () async {
    final gateway = MethodChannelExternalPlayerGateway(channel: channel);
    addTearDown(gateway.dispose);
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('external_player_returned', {
        'resultCode': -1,
        'completionSupported': false,
        'positionMs': 119500,
        'durationMs': 120000,
        'expectedDurationMs': 120000,
        'elapsedMs': 121000,
      }),
    );

    await messenger.handlePlatformMessage(
      MethodChannelExternalPlayerGateway.channelName,
      call,
      (ByteData? _) {},
    );

    expect(gateway.takeReturn(), ExternalPlayerReturn.interrupted);
  });
}
