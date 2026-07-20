import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lock/lock_controller.dart';
import '../providers.dart';
import 'external_player_gateway.dart';

final class ExternalPlayerCoordinator {
  const ExternalPlayerCoordinator({
    required ExternalPlayerGateway player,
    required LockController lock,
  })  : _player = player,
        _lock = lock;

  final ExternalPlayerGateway _player;
  final LockController _lock;

  bool get supported => _player.supported;

  Future<bool> open({
    required String filePath,
    required String mimeType,
  }) async {
    if (!_player.supported) return false;
    _lock.beginExternalPlayerHandoff();
    try {
      final launched = await _player.open(
        filePath: filePath,
        mimeType: mimeType,
      );
      if (!launched) _lock.cancelExternalPlayerHandoff();
      return launched;
    } catch (_) {
      _lock.cancelExternalPlayerHandoff();
      rethrow;
    }
  }

  ExternalPlayerReturn? onAppLifecycle(AppLifecycleState state) {
    final playerReturn =
        state == AppLifecycleState.resumed ? _player.takeReturn() : null;
    _lock.onAppLifecycle(
      state,
      externalPlayerReturnedCleanly: playerReturn != null,
    );
    return playerReturn;
  }
}

final externalPlayerCoordinatorProvider = Provider<ExternalPlayerCoordinator>((
  ref,
) {
  return ExternalPlayerCoordinator(
    player: ref.watch(externalPlayerGatewayProvider),
    lock: ref.read(lockControllerProvider.notifier),
  );
});
