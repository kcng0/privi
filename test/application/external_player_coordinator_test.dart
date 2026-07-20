import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/player/external_player_coordinator.dart';
import 'package:privi/application/player/external_player_gateway.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}

final class _ExternalPlayerGateway implements ExternalPlayerGateway {
  ExternalPlayerReturn? pendingReturn;

  @override
  bool get supported => true;

  @override
  Future<bool> open({
    required String filePath,
    required String mimeType,
  }) async =>
      true;

  @override
  ExternalPlayerReturn? takeReturn() {
    final result = pendingReturn;
    pendingReturn = null;
    return result;
  }
}

void main() {
  test('resume returns the one-shot outcome and preserves the unlocked route',
      () async {
    SharedPreferences.setMockInitialValues({'auto_lock_seconds': 0});
    final preferences = await SharedPreferences.getInstance();
    final gateway = _ExternalPlayerGateway();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        externalPlayerGatewayProvider.overrideWithValue(gateway),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
      ],
    );
    addTearDown(container.dispose);
    final coordinator = container.read(externalPlayerCoordinatorProvider);

    expect(
      await coordinator.open(
        filePath: '/vault/video.mp4',
        mimeType: 'video/mp4',
      ),
      isTrue,
    );
    coordinator.onAppLifecycle(AppLifecycleState.hidden);
    gateway.pendingReturn = ExternalPlayerReturn.interrupted;

    expect(
      coordinator.onAppLifecycle(AppLifecycleState.resumed),
      ExternalPlayerReturn.interrupted,
    );
    expect(container.read(lockControllerProvider).status, LockStatus.unlocked);
    expect(coordinator.onAppLifecycle(AppLifecycleState.resumed), isNull);
  });
}
