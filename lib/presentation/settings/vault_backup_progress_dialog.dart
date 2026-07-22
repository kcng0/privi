import 'package:flutter/material.dart';

import '../../application/backup/vault_backup_controller.dart';
import '../../data/services/vault_backup_service.dart';

final class VaultBackupDialogText {
  const VaultBackupDialogText({
    required this.operationTitle,
    required this.completedTitle,
    required this.cancelledTitle,
    required this.cancelledBody,
    required this.errorTitle,
    required this.cancel,
    required this.cancelling,
    required this.close,
    required this.retry,
    required this.checksumVerified,
    required this.checkedWithoutChecksum,
    required this.progressLabel,
    required this.stageLabel,
    required this.itemCount,
    required this.totalSize,
    required this.progressCount,
    required this.errorMessage,
  });

  final String operationTitle;
  final String completedTitle;
  final String cancelledTitle;
  final String cancelledBody;
  final String errorTitle;
  final String cancel;
  final String cancelling;
  final String close;
  final String retry;
  final String checksumVerified;
  final String checkedWithoutChecksum;
  final String progressLabel;
  final String Function(VaultBackupStage stage) stageLabel;
  final String Function(int count) itemCount;
  final String Function(int bytes) totalSize;
  final String Function(int completed, int total) progressCount;
  final String Function(Object error) errorMessage;
}

class VaultBackupProgressDialog extends StatelessWidget {
  const VaultBackupProgressDialog({
    super.key,
    required this.state,
    required this.text,
    required this.onCancel,
    required this.onRetry,
    required this.onClose,
  });

  final VaultBackupUiState state;
  final VaultBackupDialogText text;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (!state.dialogVisible) {
      throw StateError('Vault backup dialog requires an operation state.');
    }
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('vault-backup-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Text(
          switch (state.status) {
            VaultBackupUiStatus.cancelled => text.cancelledTitle,
            VaultBackupUiStatus.completed => text.completedTitle,
            VaultBackupUiStatus.failed => text.errorTitle,
            _ => text.operationTitle,
          },
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
          child: switch (state.status) {
            VaultBackupUiStatus.completed ||
            VaultBackupUiStatus.cancelled =>
              _ResultContent(result: state.result!, text: text),
            VaultBackupUiStatus.failed =>
              _ErrorContent(error: state.error!, text: text),
            _ => _ProgressContent(
                progress: state.progress,
                cancelling: state.status == VaultBackupUiStatus.cancelling,
                text: text,
              ),
          },
        ),
        actions: _actions(context),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (state.status == VaultBackupUiStatus.failed) {
      return [
        TextButton(onPressed: onClose, child: Text(text.close)),
        FilledButton(
          key: const ValueKey('vault-backup-retry'),
          onPressed: onRetry,
          child: Text(text.retry),
        ),
      ];
    }
    if (state.status == VaultBackupUiStatus.completed ||
        state.status == VaultBackupUiStatus.cancelled) {
      return [
        TextButton(
          key: const ValueKey('vault-backup-close'),
          onPressed: onClose,
          child: Text(text.close),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('vault-backup-cancel'),
        onPressed:
            state.status == VaultBackupUiStatus.cancelling ? null : onCancel,
        child: Text(text.cancel),
      ),
    ];
  }
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({
    required this.progress,
    required this.cancelling,
    required this.text,
  });

  final VaultBackupProgress progress;
  final bool cancelling;
  final VaultBackupDialogText text;

  @override
  Widget build(BuildContext context) {
    final count = text.progressCount(progress.completed, progress.total);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text.stageLabel(progress.stage),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(count),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 24,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: progress.currentFile == null
                ? const SizedBox.shrink()
                : Text(
                    progress.currentFile!,
                    key: const ValueKey('vault-backup-current-file'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: text.progressLabel,
          value: count,
          child: LinearProgressIndicator(
            key: const ValueKey('vault-backup-progress'),
            value: progress.fraction,
          ),
        ),
        if (cancelling) ...[
          const SizedBox(height: 12),
          Text(text.cancelling),
        ],
      ],
    );
  }
}

class _ResultContent extends StatelessWidget {
  const _ResultContent({required this.result, required this.text});

  final VaultBackupResult result;
  final VaultBackupDialogText text;

  @override
  Widget build(BuildContext context) {
    if (result.cancelled) {
      return Row(
        children: [
          const Icon(Icons.cancel_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(text.cancelledBody)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${text.itemCount(result.itemCount)} · '
                '${text.totalSize(result.totalBytes)}',
              ),
              const SizedBox(height: 4),
              Text(
                result.checksumsVerified
                    ? text.checksumVerified
                    : text.checkedWithoutChecksum,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.error, required this.text});

  final Object error;
  final VaultBackupDialogText text;

  @override
  Widget build(BuildContext context) {
    final stage = error is VaultBackupException
        ? (error as VaultBackupException).stage
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stage != null) ...[
          Text(
            text.stageLabel(stage),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
        ],
        Text(text.errorMessage(error)),
      ],
    );
  }
}
