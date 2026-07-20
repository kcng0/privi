import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/update/app_restart_service.dart';
import 'package:privi/data/services/ios_app_restart_service.dart';
import 'package:privi/data/services/ios_external_url_launcher.dart';
import 'package:privi/data/services/platform/android_privacy_shield_adapter.dart';
import 'package:privi/data/services/platform/ios_privacy_shield_adapter.dart';
import 'package:privi/data/services/platform/unsupported_external_player_gateway.dart';
import 'package:privi/data/services/secure_window_service.dart';
import 'package:privi/data/services/vault_storage_service.dart';

final class _FakeSecureWindowService extends SecureWindowService {
  bool? enabled;

  @override
  Future<void> setFlagSecure(bool value) async {
    enabled = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform privacy capabilities remain explicit and isolated', () async {
    final androidDelegate = _FakeSecureWindowService();
    final android = AndroidPrivacyShieldAdapter(delegate: androidDelegate);
    final ios = IosPrivacyShieldAdapter(
      channel: const MethodChannel('test/ios-privacy'),
    );

    expect(android.capabilities.screenshotsBlocked, isTrue);
    expect(android.capabilities.captureDetection, isFalse);
    expect(ios.capabilities.screenshotsBlocked, isFalse);
    expect(ios.capabilities.captureDetection, isTrue);

    await android.apply(true);
    expect(androidDelegate.enabled, isTrue);
  });

  test('iOS privacy adapter uses its dedicated channel', () async {
    const channel = MethodChannel('test/ios-privacy');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await IosPrivacyShieldAdapter(channel: channel).apply(true);

    expect(received?.method, 'setAppSwitcherShield');
    expect(received?.arguments, {'enabled': true});
  });

  test('iOS privacy adapter keeps native failures visible', () async {
    const channel = MethodChannel('test/ios-privacy-failure');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) => throw PlatformException(code: 'privacy_error'),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await expectLater(
      IosPrivacyShieldAdapter(channel: channel).apply(true),
      throwsA(isA<PlatformException>()),
    );
  });

  test('iOS external playback is an explicit unsupported capability', () async {
    const gateway = UnsupportedExternalPlayerGateway();
    expect(gateway.supported, isFalse);
    expect(
      await gateway.open(filePath: '/vault/video.mp4', mimeType: 'video/mp4'),
      isFalse,
    );
  });

  test('iOS update restart surfaces a manual relaunch requirement', () async {
    const restart = IosAppRestartService();
    expect(restart.automaticRestartSupported, isFalse);
    await expectLater(
      restart.restart(),
      throwsA(isA<RestartRequiredException>()),
    );
  });

  test('app-private storage refuses the Android shared-root operation',
      () async {
    final storage = VaultStorageService(initializeSharedRoot: false);
    await expectLater(storage.ensureHiddenRoot(), throwsUnsupportedError);
  });

  test('iOS URL launcher keeps URL opening on its own channel', () async {
    const channel = MethodChannel('test/ios-url-launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await const IosExternalUrlLauncher(channel: channel).open(
      Uri.parse('https://example.com/release'),
    );

    expect(received?.method, 'openUrl');
    expect(received?.arguments, {'url': 'https://example.com/release'});
  });
}
