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
  @override
  Future<bool> hasCredential() async => true;

  @override
  Future<String> lockKind() async => SecurityService.kindPattern;

  @override
  Future<bool> isBiometricEnabled() async => false;

  @override
  Future<bool> verifyPattern(String pattern) async => true;
}

final class _UnavailableBiometrics extends BiometricService {
  @override
  Future<bool> isHardwareAvailable() async => false;
}

Future<ProviderContainer> createUnlockedContainer({
  int autoLockSeconds = 30,
}) async {
  SharedPreferences.setMockInitialValues({
    'auto_lock_seconds': autoLockSeconds,
  });
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      securityServiceProvider.overrideWithValue(_CredentialSecurity()),
      biometricServiceProvider.overrideWithValue(_UnavailableBiometrics()),
    ],
  );
  final controller = container.read(lockControllerProvider.notifier);
  await pumpEventQueue();
  await controller.unlockWithPattern('0-1-2-3');
  return container;
}

void main() {
  test('clean external-player result bypasses resume lock', () async {
    final container = await createUnlockedContainer(autoLockSeconds: 0);
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

  test('external-player resume without result locks immediately', () async {
    final container = await createUnlockedContainer();
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.beginExternalPlayerHandoff();
    controller.onAppLifecycle(AppLifecycleState.hidden);
    controller.onAppLifecycle(AppLifecycleState.resumed);

    expect(container.read(lockControllerProvider).status, LockStatus.locked);
  });

  test('screen-off inactive-to-resumed transition locks immediately', () async {
    final container = await createUnlockedContainer();
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.onAppLifecycle(AppLifecycleState.inactive);
    controller.onAppLifecycle(AppLifecycleState.resumed);

    expect(container.read(lockControllerProvider).status, LockStatus.locked);
  });

  test('clean result without a matching hand-off cannot bypass lock', () async {
    final container = await createUnlockedContainer();
    addTearDown(container.dispose);
    final controller = container.read(lockControllerProvider.notifier);

    controller.onAppLifecycle(AppLifecycleState.hidden);
    controller.onAppLifecycle(
      AppLifecycleState.resumed,
      externalPlayerReturnedCleanly: true,
    );

    expect(container.read(lockControllerProvider).status, LockStatus.locked);
  });
}
