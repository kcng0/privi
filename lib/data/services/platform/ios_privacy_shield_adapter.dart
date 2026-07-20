import 'package:flutter/services.dart';

import '../../../application/platform/privacy_shield.dart';

/// iOS adapter for the native app-switcher privacy overlay.
///
/// iOS has no public equivalent of Android FLAG_SECURE, so the capability
/// explicitly reports `screenshotsBlocked: false` even when the snapshot shield
/// is installed successfully.
final class IosPrivacyShieldAdapter implements PrivacyShield {
  IosPrivacyShieldAdapter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const channelName = _channelName;
  static const _channelName = 'com.privi.app/privacy';

  final MethodChannel _channel;
  static const _capabilities = PrivacyCapabilities(
    appSwitcherProtected: true,
    screenshotsBlocked: false,
    captureDetection: true,
  );

  @override
  PrivacyCapabilities get capabilities => _capabilities;

  @override
  Future<PrivacyCapabilities> apply(bool enabled) async {
    await _channel.invokeMethod<void>('setAppSwitcherShield', {
      'enabled': enabled,
    });
    return _capabilities;
  }
}
