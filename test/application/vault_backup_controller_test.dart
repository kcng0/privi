import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/backup/vault_backup_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/data/services/vault_backup_service.dart';

typedef _BackupHandler = Future<VaultBackupResult> Function(
  VaultBackupSession? session,
  VaultBackupProgressCallback? onProgress,
);

final class _FakeVaultBackupOperations implements VaultBackupOperations {
  _FakeVaultBackupOperations({
    List<_BackupHandler>? exports,
    List<_BackupHandler>? restores,
  })  : _exports = [...?exports],
        _restores = [...?restores];

  final List<_BackupHandler> _exports;
  final List<_BackupHandler> _restores;
  int exportCalls = 0;
  int restoreCalls = 0;
  VaultBackupSession? lastExportSession;
  VaultBackupSession? lastRestoreSession;

  @override
  Future<VaultBackupResult> exportToDirectory(
    String destinationDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) {
    exportCalls++;
    lastExportSession = session;
    if (_exports.isEmpty) {
      throw StateError('No fake export handler is configured.');
    }
    return _exports.removeAt(0)(session, onProgress);
  }

  @override
  Future<VaultBackupResult> importFromDirectory(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) {
    restoreCalls++;
    lastRestoreSession = session;
    if (_restores.isEmpty) {
      throw StateError('No fake restore handler is configured.');
    }
    return _restores.removeAt(0)(session, onProgress);
  }
}

void main() {
  test('successful export exposes progress and completed result', () async {
    final fake = _FakeVaultBackupOperations(
      exports: [
        (session, onProgress) async {
          onProgress?.call(
            const VaultBackupProgress(
              stage: VaultBackupStage.copying,
              completed: 1,
              total: 2,
              currentFile: 'one.jpg',
            ),
          );
          return const VaultBackupResult(
            itemCount: 2,
            totalBytes: 42,
            checksumsVerified: true,
            status: VaultBackupResultStatus.completed,
          );
        },
      ],
    );
    final container = ProviderContainer(
      overrides: [vaultBackupServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultBackupControllerProvider.notifier);

    final operation = controller.start(
      operation: VaultBackupOperation.export,
      directory: '/backup',
    );
    expect(
      container.read(vaultBackupControllerProvider).status,
      VaultBackupUiStatus.running,
    );

    await operation;

    final state = container.read(vaultBackupControllerProvider);
    expect(fake.exportCalls, 1);
    expect(state.status, VaultBackupUiStatus.completed);
    expect(state.progress.currentFile, 'one.jpg');
    expect(state.result?.itemCount, 2);
    expect(state.result?.checksumsVerified, isTrue);
  });

  test('failed export can be retried with the same directory', () async {
    final fake = _FakeVaultBackupOperations(
      exports: [
        (_, __) async {
          throw const VaultBackupException(
            VaultBackupErrorCode.sourceMissing,
            fileName: 'missing.jpg',
            stage: VaultBackupStage.checkingSource,
          );
        },
        (_, __) async => const VaultBackupResult(
              itemCount: 1,
              totalBytes: 7,
              checksumsVerified: true,
              status: VaultBackupResultStatus.completed,
            ),
      ],
    );
    final container = ProviderContainer(
      overrides: [vaultBackupServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultBackupControllerProvider.notifier);

    await controller.start(
      operation: VaultBackupOperation.export,
      directory: '/backup',
    );
    final failed = container.read(vaultBackupControllerProvider);
    expect(failed.status, VaultBackupUiStatus.failed);
    expect(failed.directory, '/backup');
    expect(failed.error, isA<VaultBackupException>());

    await controller.retry();

    final retried = container.read(vaultBackupControllerProvider);
    expect(fake.exportCalls, 2);
    expect(retried.status, VaultBackupUiStatus.completed);
    expect(retried.result?.itemCount, 1);
  });

  test('cancelling a running restore reports cancelled result', () async {
    final result = Completer<VaultBackupResult>();
    final fake = _FakeVaultBackupOperations(
      restores: [
        (_, __) => result.future,
      ],
    );
    final container = ProviderContainer(
      overrides: [vaultBackupServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultBackupControllerProvider.notifier);

    final operation = controller.start(
      operation: VaultBackupOperation.restore,
      directory: '/backup',
    );
    expect(
      container.read(vaultBackupControllerProvider).status,
      VaultBackupUiStatus.running,
    );

    controller.cancel();
    expect(
      container.read(vaultBackupControllerProvider).status,
      VaultBackupUiStatus.cancelling,
    );
    expect(fake.lastRestoreSession?.isCancelled, isTrue);

    result.complete(
      const VaultBackupResult(
        itemCount: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      ),
    );
    await operation;

    final state = container.read(vaultBackupControllerProvider);
    expect(state.status, VaultBackupUiStatus.cancelled);
    expect(state.result?.cancelled, isTrue);
  });

  test('directory selection rejects a second backup workflow', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(vaultBackupControllerProvider.notifier);
    final picker = Completer<String?>();
    var pickerCalls = 0;

    final first = controller.selectDirectoryAndStart(
      operation: VaultBackupOperation.export,
      selectDirectory: () {
        pickerCalls++;
        return picker.future;
      },
    );
    expect(container.read(vaultBackupControllerProvider).busy, isTrue);

    await expectLater(
      controller.selectDirectoryAndStart(
        operation: VaultBackupOperation.restore,
        selectDirectory: () async {
          pickerCalls++;
          return '/second';
        },
      ),
      throwsStateError,
    );
    expect(pickerCalls, 1);

    picker.complete(null);
    expect(await first, isFalse);
    expect(container.read(vaultBackupControllerProvider).busy, isFalse);
  });

  test('busy operation cannot be dismissed', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(vaultBackupControllerProvider.notifier);
    final picker = Completer<String?>();
    final selection = controller.selectDirectoryAndStart(
      operation: VaultBackupOperation.export,
      selectDirectory: () => picker.future,
    );

    expect(controller.dismiss, throwsStateError);

    picker.complete(null);
    await selection;
  });
}
