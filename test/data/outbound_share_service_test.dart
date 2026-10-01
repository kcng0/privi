import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/outbound_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(OutboundShareService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('system chooser sends MediaStore ids without copying files', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });

    final service = OutboundShareService(
      channel: channel,
      useSystemChooser: true,
    );
    await service.share(const [
      OutboundShareFile(
        mediaId: '42',
        mimeType: 'video/*',
        name: 'clip.mp4',
        isVideo: true,
      ),
    ]);

    expect(receivedCall?.method, 'share');
    expect(receivedCall?.arguments, {
      'items': [
        {
          'mediaId': '42',
          'mimeType': 'video/*',
          'name': 'clip.mp4',
          'isVideo': true,
        },
      ],
    });
  });

  test('system chooser sends vault paths through FileProvider', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });

    final service = OutboundShareService(
      channel: channel,
      useSystemChooser: true,
    );
    await service.share(const [
      OutboundShareFile(
        path: '/vault/hidden.mp4',
        mimeType: 'video/mp4',
        name: 'hidden.mp4',
        isVideo: true,
      ),
    ]);

    expect(receivedCall?.arguments, {
      'items': [
        {
          'path': '/vault/hidden.mp4',
          'mimeType': 'video/mp4',
          'name': 'hidden.mp4',
          'isVideo': true,
        },
      ],
    });
  });

  test('non-Android fallback shares vault files as XFiles', () async {
    var shared = <XFile>[];
    final service = OutboundShareService(
      useSystemChooser: false,
      shareXFiles: (files) async {
        shared = files;
      },
    );

    await service.share(const [
      OutboundShareFile(
        path: '/vault/hidden.mp4',
        mimeType: 'video/mp4',
        name: 'hidden.mp4',
        isVideo: true,
      ),
    ]);

    expect(shared.single.path, '/vault/hidden.mp4');
    expect(shared.single.mimeType, 'video/mp4');
    expect(shared.single.name, 'hidden.mp4');
  });
}
