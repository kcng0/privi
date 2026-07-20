final class PrivacyCapabilities {
  const PrivacyCapabilities({
    required this.appSwitcherProtected,
    required this.screenshotsBlocked,
    required this.captureDetection,
    this.diagnostic,
  });

  final bool appSwitcherProtected;
  final bool screenshotsBlocked;
  final bool captureDetection;
  final String? diagnostic;
}

/// Platform privacy guarantees when the shield is enabled.
///
/// The values describe platform support, not the current enabled state. This
/// lets presentation code use accurate copy even while the setting is off.
abstract interface class PrivacyShield {
  PrivacyCapabilities get capabilities;

  Future<PrivacyCapabilities> apply(bool enabled);
}
