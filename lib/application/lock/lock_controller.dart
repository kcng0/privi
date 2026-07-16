import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/security_service.dart';
import '../../domain/enums.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';

/// App vault lock UI state (not Flutter's shortcuts [LockState]).
class VaultLockState {
  const VaultLockState({
    required this.status,
    this.errorMessage,
    this.lockKind = SecurityService.kindPattern,
    this.pinLength = 4,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
  });

  final LockStatus status;
  final String? errorMessage;

  /// [SecurityService.kindPattern] (default) or [SecurityService.kindPin].
  final String lockKind;
  final int pinLength;
  final bool biometricEnabled;
  final bool biometricAvailable;

  bool get usesPattern => lockKind != SecurityService.kindPin;

  VaultLockState copyWith({
    LockStatus? status,
    String? errorMessage,
    String? lockKind,
    int? pinLength,
    bool? biometricEnabled,
    bool? biometricAvailable,
    bool clearError = false,
  }) {
    return VaultLockState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lockKind: lockKind ?? this.lockKind,
      pinLength: pinLength ?? this.pinLength,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    );
  }
}

class LockController extends Notifier<VaultLockState> {
  Timer? _autoLockTimer;

  /// Nested counter: viewer / player / external hand-off keep the vault open.
  int _suppressAutoLockDepth = 0;

  /// When true, one suppress level is released on the next [resumed].
  bool _releaseSuppressOnResume = false;

  @override
  VaultLockState build() {
    ref.onDispose(() {
      _autoLockTimer?.cancel();
      _suppressAutoLockDepth = 0;
      _releaseSuppressOnResume = false;
    });
    Future.microtask(_bootstrap);
    return const VaultLockState(status: LockStatus.locked);
  }

  void _cancelAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  /// Keep session unlocked (in-app viewer/player). Pair with [releaseAutoLockSuppress].
  void suppressAutoLock() {
    _suppressAutoLockDepth++;
    _cancelAutoLockTimer();
  }

  void releaseAutoLockSuppress() {
    if (_suppressAutoLockDepth > 0) {
      _suppressAutoLockDepth--;
    }
  }

  /// Suppress auto-lock while another app (VLC / system player) is open.
  /// Released automatically on the next [AppLifecycleState.resumed].
  void suppressAutoLockUntilResumed() {
    suppressAutoLock();
    _releaseSuppressOnResume = true;
  }

  Future<void> _bootstrap() async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    final has = await security.hasCredential();
    final kind =
        has ? await security.lockKind() : SecurityService.kindPattern;
    final bioEnabled = await security.isBiometricEnabled();
    final bioHw = await bio.isHardwareAvailable();
    if (!ref.mounted) return;
    state = VaultLockState(
      status: has ? LockStatus.locked : LockStatus.needsSetup,
      lockKind: kind,
      biometricEnabled: bioEnabled,
      biometricAvailable: bioHw,
    );
  }

  Future<void> setupPattern(String pattern) async {
    final security = ref.read(securityServiceProvider);
    await security.setPattern(pattern);
    if (!ref.mounted) return;
    _cancelAutoLockTimer();
    state = state.copyWith(
      status: LockStatus.unlocked,
      lockKind: SecurityService.kindPattern,
      clearError: true,
    );
  }

  /// Legacy PIN setup (still available if needed).
  Future<void> setupPin(String pin) async {
    final security = ref.read(securityServiceProvider);
    await security.setPin(pin);
    if (!ref.mounted) return;
    _cancelAutoLockTimer();
    state = state.copyWith(
      status: LockStatus.unlocked,
      lockKind: SecurityService.kindPin,
      pinLength: pin.length,
      clearError: true,
    );
  }

  Future<bool> unlockWithPattern(String pattern) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPattern(pattern);
    if (!ref.mounted) return false;
    if (ok) {
      _cancelAutoLockTimer();
      state = state.copyWith(
        status: LockStatus.unlocked,
        clearError: true,
        lockKind: SecurityService.kindPattern,
      );
      return true;
    }
    state = state.copyWith(errorMessage: 'Wrong pattern');
    return false;
  }

  Future<bool> unlock(String pin) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPin(pin);
    if (!ref.mounted) return false;
    if (ok) {
      _cancelAutoLockTimer();
      state = state.copyWith(
        status: LockStatus.unlocked,
        clearError: true,
        pinLength: pin.length,
        lockKind: SecurityService.kindPin,
      );
      return true;
    }
    state = state.copyWith(errorMessage: 'Wrong PIN');
    return false;
  }

  /// Biometric convenience unlock (requires root credential + enabled).
  Future<bool> unlockWithBiometric() async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    if (!await security.hasCredential()) return false;
    if (!await security.isBiometricEnabled()) return false;
    // Prefer biometrics; still allow device credential if OEM cancels bio-only.
    final ok = await bio.authenticate(
      reason: 'Unlock Privi',
      biometricOnly: false,
    );
    if (!ref.mounted) return false;
    if (ok) {
      _cancelAutoLockTimer();
      state = state.copyWith(status: LockStatus.unlocked, clearError: true);
      return true;
    }
    return false;
  }

  /// Enable/disable biometric. Cancel is soft-fail (returns false, no throw).
  /// Throws only when hardware truly unavailable.
  Future<bool> setBiometricEnabled(bool enabled) async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    if (enabled) {
      final hw = await bio.isHardwareAvailable();
      debugPrint('setBiometricEnabled hw=$hw');
      if (!hw) {
        throw StateError(
          'Biometrics not available — enroll fingerprint/face in system Settings first',
        );
      }
      // Confirm with a live biometric before enabling.
      // Allow device credential fallback if OEM biometric-only is flaky.
      final ok = await bio.authenticate(
        reason: 'Confirm to enable biometric unlock',
        biometricOnly: false,
      );
      debugPrint('setBiometricEnabled auth ok=$ok');
      if (!ok) {
        // User cancelled or failed — not an exceptional state.
        return false;
      }
    }
    await security.setBiometricEnabled(enabled);
    if (!ref.mounted) return false;
    state = state.copyWith(biometricEnabled: enabled);
    return true;
  }

  /// Forgot pattern: verify via Android system auth (biometrics or device PIN/pattern),
  /// then clear the vault credential so the user can set a new pattern.
  /// Returns true if recovery completed (status → needsSetup).
  Future<bool> recoverWithSystemAuth() async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    if (!await security.hasCredential()) {
      if (!ref.mounted) return false;
      state = state.copyWith(status: LockStatus.needsSetup, clearError: true);
      return true;
    }
    final supported = await bio.canUseDeviceCredential();
    if (!supported) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        errorMessage:
            'System lock screen not set up — set a PIN/pattern/fingerprint in Android Settings first',
      );
      return false;
    }
    final ok = await bio.authenticate(
      reason: 'Confirm it is you to reset Privi pattern',
      biometricOnly: false, // allow device PIN / pattern / biometric
    );
    if (!ok) {
      if (!ref.mounted) return false;
      state = state.copyWith(errorMessage: 'System authentication cancelled');
      return false;
    }
    await security.clearCredential();
    // Optional: leave biometric flag; user re-enables after setup if desired.
    if (!ref.mounted) return false;
    _cancelAutoLockTimer();
    state = VaultLockState(
      status: LockStatus.needsSetup,
      lockKind: SecurityService.kindPattern,
      biometricEnabled: state.biometricEnabled,
      biometricAvailable: state.biometricAvailable,
    );
    return true;
  }

  Future<void> changePattern({
    required String currentPattern,
    required String newPattern,
  }) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPattern(currentPattern);
    if (!ok) {
      // Allow changing from legacy PIN install by verifying current as PIN too.
      final pinOk = await security.verifyPin(currentPattern);
      if (!pinOk) throw StateError('Current pattern is incorrect');
    }
    await security.setPattern(newPattern);
    if (!ref.mounted) return;
    state = state.copyWith(lockKind: SecurityService.kindPattern);
  }

  /// Verify legacy PIN then replace root credential with [newPattern].
  Future<void> migratePinToPattern({
    required String currentPin,
    required String newPattern,
  }) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPin(currentPin);
    if (!ok) throw StateError('Current PIN is incorrect');
    await security.setPattern(newPattern);
    if (!ref.mounted) return;
    state = state.copyWith(lockKind: SecurityService.kindPattern, clearError: true);
  }

  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPin(currentPin);
    if (!ok) throw StateError('Current PIN is incorrect');
    await security.setPin(newPin);
    if (!ref.mounted) return;
    state = state.copyWith(
      pinLength: newPin.length,
      lockKind: SecurityService.kindPin,
    );
  }

  void lock() {
    _cancelAutoLockTimer();
    state = state.copyWith(status: LockStatus.locked, clearError: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Auto-lock when the app leaves the foreground for [autoLockSeconds].
  ///
  /// - Ignores [AppLifecycleState.inactive] (dialogs / transient focus).
  /// - Always arms the timer on paused/hidden/detached — even while a
  ///   viewer/player is open or an external app was launched — so hiding the
  ///   app for ≥ timeout (default 30s) always requires re-auth.
  /// - [suppressAutoLock] only softens *immediate* lock; it no longer
  ///   cancels the background timeout.
  void onAppLifecycle(AppLifecycleState lifecycle) {
    if (state.status != LockStatus.unlocked) return;
    final seconds = ref.read(settingsControllerProvider).autoLockSeconds;

    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _cancelAutoLockTimer();
        if (_releaseSuppressOnResume) {
          _releaseSuppressOnResume = false;
          releaseAutoLockSuppress();
        }
        return;
      case AppLifecycleState.inactive:
        // Ignore: system UI overlays / focus loss without leaving the app.
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _cancelAutoLockTimer();
        if (seconds <= 0) {
          lock();
        } else {
          _autoLockTimer = Timer(Duration(seconds: seconds), lock);
        }
    }
  }
}

final lockControllerProvider =
    NotifierProvider<LockController, VaultLockState>(LockController.new);
