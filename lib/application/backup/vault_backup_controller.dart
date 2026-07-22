import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/vault_backup_service.dart';
import '../providers.dart';

enum VaultBackupOperation { export, restore }

enum VaultBackupUiStatus {
  idle,
  selectingDirectory,
  running,
  cancelling,
  completed,
  cancelled,
  failed,
}

final class VaultBackupUiState {
  const VaultBackupUiState({
    this.operation,
    this.directory,
    this.status = VaultBackupUiStatus.idle,
    this.progress = const VaultBackupProgress(
      stage: VaultBackupStage.preparing,
      completed: 0,
      total: 0,
    ),
    this.result,
    this.error,
  });

  final VaultBackupOperation? operation;
  final String? directory;
  final VaultBackupUiStatus status;
  final VaultBackupProgress progress;
  final VaultBackupResult? result;
  final Object? error;

  bool get busy => switch (status) {
        VaultBackupUiStatus.selectingDirectory ||
        VaultBackupUiStatus.running ||
        VaultBackupUiStatus.cancelling =>
          true,
        _ => false,
      };

  bool get dialogVisible => switch (status) {
        VaultBackupUiStatus.running ||
        VaultBackupUiStatus.cancelling ||
        VaultBackupUiStatus.completed ||
        VaultBackupUiStatus.cancelled ||
        VaultBackupUiStatus.failed =>
          true,
        _ => false,
      };
}

class VaultBackupController extends Notifier<VaultBackupUiState> {
  VaultBackupSession? _session;

  @override
  VaultBackupUiState build() => const VaultBackupUiState();

  Future<bool> selectDirectoryAndStart({
    required VaultBackupOperation operation,
    required Future<String?> Function() selectDirectory,
  }) async {
    _ensureAvailable();
    state = VaultBackupUiState(
      operation: operation,
      status: VaultBackupUiStatus.selectingDirectory,
    );
    String? directory;
    try {
      directory = await selectDirectory();
    } catch (_) {
      if (ref.mounted) state = const VaultBackupUiState();
      rethrow;
    }
    if (!ref.mounted) return false;
    if (directory == null) {
      state = const VaultBackupUiState();
      return false;
    }
    unawaited(_run(operation: operation, directory: directory));
    return true;
  }

  Future<void> start({
    required VaultBackupOperation operation,
    required String directory,
  }) {
    _ensureAvailable();
    return _run(operation: operation, directory: directory);
  }

  Future<void> retry() {
    final operation = state.operation;
    final directory = state.directory;
    if (operation == null || directory == null) {
      throw StateError('No vault backup operation is available to retry.');
    }
    return start(operation: operation, directory: directory);
  }

  void cancel() {
    final session = _session;
    if (session == null || state.status != VaultBackupUiStatus.running) {
      throw StateError('No running vault backup operation can be cancelled.');
    }
    session.cancel();
    state = VaultBackupUiState(
      operation: state.operation,
      directory: state.directory,
      status: VaultBackupUiStatus.cancelling,
      progress: state.progress,
    );
  }

  void dismiss() {
    if (state.busy) {
      throw StateError('A running vault backup operation cannot be dismissed.');
    }
    state = const VaultBackupUiState();
  }

  Future<void> _run({
    required VaultBackupOperation operation,
    required String directory,
  }) async {
    final session = VaultBackupSession();
    _session = session;
    state = VaultBackupUiState(
      operation: operation,
      directory: directory,
      status: VaultBackupUiStatus.running,
    );
    try {
      final service = ref.read(vaultBackupServiceProvider);
      final result = await switch (operation) {
        VaultBackupOperation.export => service.exportToDirectory(
            directory,
            session: session,
            onProgress: (progress) => _updateProgress(session, progress),
          ),
        VaultBackupOperation.restore => service.importFromDirectory(
            directory,
            session: session,
            onProgress: (progress) => _updateProgress(session, progress),
          ),
      };
      if (!ref.mounted || !identical(_session, session)) return;
      state = VaultBackupUiState(
        operation: operation,
        directory: directory,
        status: result.cancelled
            ? VaultBackupUiStatus.cancelled
            : VaultBackupUiStatus.completed,
        progress: state.progress,
        result: result,
      );
      if (!result.cancelled && operation == VaultBackupOperation.restore) {
        ref.invalidate(vaultSizeBytesProvider);
        ref.invalidate(albumsProvider);
      }
    } catch (error, stackTrace) {
      debugPrint('vault backup controller: $error\n$stackTrace');
      if (!ref.mounted || !identical(_session, session)) return;
      state = VaultBackupUiState(
        operation: operation,
        directory: directory,
        status: VaultBackupUiStatus.failed,
        progress: state.progress,
        error: error,
      );
    } finally {
      if (identical(_session, session)) _session = null;
    }
  }

  void _updateProgress(
    VaultBackupSession session,
    VaultBackupProgress progress,
  ) {
    if (!ref.mounted || !identical(_session, session)) return;
    state = VaultBackupUiState(
      operation: state.operation,
      directory: state.directory,
      status: session.isCancelled
          ? VaultBackupUiStatus.cancelling
          : VaultBackupUiStatus.running,
      progress: progress,
    );
  }

  void _ensureAvailable() {
    if (state.busy) {
      throw StateError('A vault backup operation is already in progress.');
    }
  }
}

final vaultBackupControllerProvider =
    NotifierProvider<VaultBackupController, VaultBackupUiState>(
  VaultBackupController.new,
);
