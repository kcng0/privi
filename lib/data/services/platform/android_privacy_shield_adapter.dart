import '../../../application/platform/privacy_shield.dart';
import '../secure_window_service.dart';

final class AndroidPrivacyShieldAdapter implements PrivacyShield {
  AndroidPrivacyShieldAdapter({SecureWindowService? delegate})
      : _delegate = delegate ?? SecureWindowService();

  final SecureWindowService _delegate;
  static const _capabilities = PrivacyCapabilities(
    appSwitcherProtected: true,
    screenshotsBlocked: true,
    captureDetection: false,
  );

  @override
  PrivacyCapabilities get capabilities => _capabilities;

  @override
  Future<PrivacyCapabilities> apply(bool enabled) async {
    await _delegate.setFlagSecure(enabled);
    return _capabilities;
  }
}
