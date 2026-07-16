import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// Biometric convenience unlock (pattern/PIN remains root credential).
///
/// Android requires the host activity to be a [FragmentActivity]
/// (`FlutterFragmentActivity`) or authenticate returns
/// `ERROR_NOT_FRAGMENT_ACTIVITY` and never shows a prompt.
class BiometricService {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// Hardware present and usable (enrolled preferred).
  Future<bool> isHardwareAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final types = await _auth.getAvailableBiometrics();
      // Always log for adb: `adb logcat | grep biometric`
      debugPrint(
        'biometric status: supported=$supported canCheck=$canCheck '
        'types=$types',
      );
      if (types.isNotEmpty) return true;
      // Some OEMs return an empty type list even with enrolled fingerprints.
      return supported && canCheck;
    } catch (e) {
      debugPrint('biometric hw: $e');
      return false;
    }
  }

  Future<List<BiometricType>> availableTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  /// Device supports some form of local auth (biometrics and/or lock-screen PIN/pattern).
  Future<bool> canUseDeviceCredential() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('device credential: $e');
      return false;
    }
  }

  /// Returns true on success, false on cancel / failure / no hardware.
  /// Never throws for user cancel.
  Future<bool> authenticate({
    String reason = 'Unlock Privi',
    bool biometricOnly = true,
    String signInTitle = 'Privi',
    String biometricHint = 'Verify identity',
    String cancelButton = 'Cancel',
  }) async {
    try {
      debugPrint(
        'biometric authenticate start biometricOnly=$biometricOnly reason=$reason',
      );
      final ok = await _auth.authenticate(
        localizedReason: reason,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: signInTitle,
            biometricHint: biometricHint,
            cancelButton: cancelButton,
          ),
          IOSAuthMessages(
            cancelButton: cancelButton,
          ),
        ],
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      debugPrint('biometric authenticate result=$ok');
      return ok;
    } on PlatformException catch (e) {
      // Codes: NotAvailable, NotEnrolled, LockedOut, PermanentlyLockedOut,
      // PasscodeNotSet, FragmentActivity (if activity wrong), etc.
      debugPrint(
        'biometric auth platform: code=${e.code} message=${e.message} '
        'details=${e.details}',
      );
      return false;
    } catch (e) {
      debugPrint('biometric auth: $e');
      return false;
    }
  }
}
