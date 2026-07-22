import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/backup/vault_backup_controller.dart';
import 'package:privi/data/services/vault_backup_service.dart';
import 'package:privi/presentation/settings/vault_backup_progress_dialog.dart';

VaultBackupDialogText _text() {
  return VaultBackupDialogText(
    operationTitle: 'Export vault',
    completedTitle: 'Backup verified',
    cancelledTitle: 'Cancelled',
    cancelledBody: 'No changes saved.',
    errorTitle: 'Export failed',
    cancel: 'Cancel',
    cancelling: 'Finishing current file...',
    close: 'Close',
    retry: 'Retry',
    checksumVerified: 'SHA-256 checked',
    checkedWithoutChecksum: 'Files checked - no checksums',
    progressLabel: 'Backup progress',
    stageLabel: (stage) => stage.name,
    itemCount: (count) => '$count items',
    totalSize: (bytes) => '$bytes B',
    progressCount: (completed, total) => '$completed / $total',
    errorMessage: (_) => 'Backup file is damaged',
  );
}

Widget _dialog(
  VaultBackupUiState state, {
  VoidCallback? onCancel,
  VoidCallback? onRetry,
  VoidCallback? onClose,
}) {
  return MaterialApp(
    home: Scaffold(
      body: VaultBackupProgressDialog(
        state: state,
        text: _text(),
        onCancel: onCancel ?? () {},
        onRetry: onRetry ?? () {},
        onClose: onClose ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows narrow progress and requests cooperative cancellation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var cancelCalls = 0;
    const state = VaultBackupUiState(
      operation: VaultBackupOperation.export,
      directory: '/backup',
      status: VaultBackupUiStatus.running,
      progress: VaultBackupProgress(
        stage: VaultBackupStage.copying,
        completed: 3,
        total: 10,
        currentFile:
            'a-very-long-media-file-name-that-must-stay-within-the-dialog.jpg',
      ),
    );

    await tester.pumpWidget(
      _dialog(state, onCancel: () => cancelCalls++),
    );

    expect(find.text('copying'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('vault-backup-current-file')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('vault-backup-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('vault-backup-cancel')));
    expect(cancelCalls, 1);
  });

  testWidgets('shows cancelling state and disables repeated cancellation',
      (tester) async {
    const state = VaultBackupUiState(
      operation: VaultBackupOperation.export,
      directory: '/backup',
      status: VaultBackupUiStatus.cancelling,
      progress: VaultBackupProgress(
        stage: VaultBackupStage.copying,
        completed: 3,
        total: 10,
      ),
    );

    await tester.pumpWidget(_dialog(state));

    expect(find.text('Finishing current file...'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('vault-backup-cancel')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('shows verified completion', (tester) async {
    const state = VaultBackupUiState(
      operation: VaultBackupOperation.export,
      directory: '/backup',
      status: VaultBackupUiStatus.completed,
      result: VaultBackupResult(
        itemCount: 1,
        totalBytes: 12,
        checksumsVerified: true,
        status: VaultBackupResultStatus.completed,
      ),
    );

    await tester.pumpWidget(_dialog(state));

    expect(find.text('Backup verified'), findsOneWidget);
    expect(find.text('1 items · 12 B'), findsOneWidget);
    expect(find.text('SHA-256 checked'), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-backup-close')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows cancellation once with a distinct result message',
      (tester) async {
    const state = VaultBackupUiState(
      operation: VaultBackupOperation.export,
      directory: '/backup',
      status: VaultBackupUiStatus.cancelled,
      result: VaultBackupResult(
        itemCount: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      ),
    );

    await tester.pumpWidget(_dialog(state));

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('No changes saved.'), findsOneWidget);
  });

  testWidgets('maps typed failures and identifies the failed stage',
      (tester) async {
    const state = VaultBackupUiState(
      operation: VaultBackupOperation.restore,
      directory: '/backup',
      status: VaultBackupUiStatus.failed,
      error: VaultBackupException(
        VaultBackupErrorCode.payloadDigestMismatch,
        fileName: 'photo.jpg',
        stage: VaultBackupStage.checkingBackup,
      ),
    );

    await tester.pumpWidget(_dialog(state));

    expect(find.textContaining('VaultBackupException'), findsNothing);
    expect(find.text('Backup file is damaged'), findsOneWidget);
    expect(find.text('checkingBackup'), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-backup-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
