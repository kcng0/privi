import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import 'lock_controller.dart';

/// Shared biometric unlock / enable prompts (setup, lock, settings).
///
/// Always pass localized copy so Android's "Verify identity" sheet is not English-only.
extension BiometricUi on WidgetRef {
  Future<bool> unlockWithBiometricUi(BuildContext context) {
    final l10n = context.l10n;
    return read(lockControllerProvider.notifier).unlockWithBiometric(
      reason: l10n.unlockPrivi,
      signInTitle: l10n.appName,
      biometricHint: l10n.verifyIdentity,
      cancelButton: l10n.cancel,
    );
  }

  Future<bool> setBiometricEnabledUi(
    BuildContext context,
    bool enabled,
  ) {
    final l10n = context.l10n;
    return read(lockControllerProvider.notifier).setBiometricEnabled(
      enabled,
      reason: l10n.confirmBiometricEnable,
      signInTitle: l10n.appName,
      biometricHint: l10n.verifyIdentity,
      cancelButton: l10n.cancel,
    );
  }

  Future<bool> recoverWithSystemAuthUi(BuildContext context) {
    final l10n = context.l10n;
    return read(lockControllerProvider.notifier).recoverWithSystemAuth(
      reason: l10n.confirmResetPattern,
      signInTitle: l10n.appName,
      biometricHint: l10n.verifyIdentity,
      cancelButton: l10n.cancel,
    );
  }
}
