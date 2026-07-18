import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/data/services/biometric_service.dart';
import 'package:privi/data/services/security_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _CredentialSecurity extends SecurityService {
  _CredentialSecurity({this.biometricEnabled = false});

  final bool biometricEnabled;

  @override
  Future<bool> hasCredential() async => true;

  @override
  Future<String> lockKind() async => SecurityService.kindPattern;

  @override
  Future<bool> isBiometricEnabled() async => biometricEnabled;

  @override
  Future<bool> verifyPattern(String pattern) async => true;
}

final class _UnavailableBiometrics extends BiometricService {
  @override
  Future<bool> isHardwareAvailable() async => false;
}

final class _SuccessfulBiometrics extends BiometricService {
  @override
  Future<bool> isHardwareAvailable() async => true;

  @override
  Future<bool> authenticate({
    String reason = 'Unlock Privi',
    bool biometricOnly = true,
    String signInTitle = 'Privi',
    String biometricHint = 'Verify identity',
    String cancelButton = 'Cancel',
  }) async =>
      true;
}

Future<ProviderContainer> createLockContainer({
  int autoLockSeconds = 30,
  bool unlock = true,
  bool biometricEnabled = false,
  BiometricService? biometrics,
}) async {
  SharedPreferences.setMockInitialValues({
    'auto_lock_seconds': autoLockSeconds,
  });
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      securityServiceProvider.overrideWithValue(
        _CredentialSecurity(biometricEnabled: biometricEnabled),
      ),
      biometricServiceProvider.overrideWithValue(
        biometrics ?? _UnavailableBiometrics(),
      ),
    ],
  );
  final controller = container.read(lockControllerProvider.notifier);
  await pumpEventQueue();
  if (unlock) await controller.unlockWithPattern('0-1-2-3');
  return container;
}

void main() {
  test('clean external-media result bypasses resume lock', () async {
    final container = await createLockContainer(autoLockSeconds: 0);
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.beginExternalPlayerHandoff();
    controller.onAppLifecycle(AppLifecycleState.hidden);
    expect(container.read(lockControllerProvider).status, LockStatus.unlocked);

    controller.onAppLifecycle(
      AppLifecycleState.resumed,
      externalPlayerReturnedCleanly: true,
    );
    expect(container.read(lockControllerProvider).status, LockStatus.unlocked);
  });

  test('external-media resume without result locks immediately', () async {
    final container = await createLockContainer();
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.beginExternalPlayerHandoff();
    controller.onAppLifecycle(AppLifecycleState.hidden);
    controller.onAppLifecycle(AppLifecycleState.resumed);

    expect(container.read(lockControllerProvider).status, LockStatus.locked);
  });

  test('screen-off hidden-to-resumed transition locks immediately', () async {
    final container = await createLockContainer();
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.onAppLifecycle(AppLifecycleState.hidden);
    controller.onAppLifecycle(AppLifecycleState.resumed);

    expect(container.read(lockControllerProvider).status, LockStatus.locked);
  });

  test('clean result without a matching hand-off cannot bypass lock', () async {
    final container = await createLockContainer();
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.onAppLifecycle(AppLifecycleState.hidden);
    controller.onAppLifecycle(
      AppLifecycleState.resumed,
      externalPlayerReturnedCleanly: true,
    );

    expect(container.read(lockControllerProvider).status, LockStatus.locked);
  });

  test('biometric inactive-to-resumed keeps a successful unlock', () async {
    final container = await createLockContainer(
      unlock: false,
      biometricEnabled: true,
      biometrics: _SuccessfulBiometrics(),
    );
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.onAppLifecycle(AppLifecycleState.inactive);
    expect(await controller.unlockWithBiometric(), isTrue);
    controller.onAppLifecycle(AppLifecycleState.resumed);

    expect(container.read(lockControllerProvider).status, LockStatus.unlocked);
  });
}
