import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media_rename_service.dart';
import 'file_system_gateway.dart';
import 'hide_preparer.dart';
import 'import_models.dart';

class TransferOutcome {
  const TransferOutcome._({
    required this.job,
    required this.ok,
    this.destinationPath,
    this.sizeBytes,
    this.errorCode,
    this.rawError,
  });

  factory TransferOutcome.success({
    required PreparedHide job,
    required String destinationPath,
    required int sizeBytes,
  }) {
    return TransferOutcome._(
      job: job,
      ok: true,
      destinationPath: destinationPath,
      sizeBytes: sizeBytes,
    );
  }

  factory TransferOutcome.failure({
    required PreparedHide job,
    required ImportErrorCode errorCode,
    String? rawError,
  }) {
    return TransferOutcome._(
      job: job,
      ok: false,
      errorCode: errorCode,
      rawError: rawError,
    );
  }

  final PreparedHide job;
  final bool ok;
  final String? destinationPath;
  final int? sizeBytes;
  final ImportErrorCode? errorCode;
  final String? rawError;
}

class VaultTransferRunner {
  const VaultTransferRunner({
    required MediaRenameService renamer,
    required FileSystemGateway fileSystem,
  })  : _renamer = renamer,
        _files = fileSystem;

  final MediaRenameService _renamer;
  final FileSystemGateway _files;

  static const int nativeBatchChunk = 8;

  Future<List<TransferOutcome>> run(
    List<PreparedHide> jobs, {
    required ImportSession session,
    Future<List<PreparedHide>> Function(List<PreparedHide> jobs)? beforeChunk,
    Future<void> Function(List<TransferOutcome> outcomes)? onChunk,
    bool collectOutcomes = true,
  }) async {
    final allOutcomes = <TransferOutcome>[];
    for (var offset = 0;
        offset < jobs.length && !session.isCancelled;
        offset += nativeBatchChunk) {
      final end = offset + nativeBatchChunk > jobs.length
          ? jobs.length
          : offset + nativeBatchChunk;
      var chunk = jobs.sublist(offset, end);
      if (beforeChunk != null) {
        chunk = await beforeChunk(List<PreparedHide>.unmodifiable(chunk));
        if (chunk.length != end - offset) {
          throw StateError('beforeChunk must preserve the transfer batch');
        }
      }
      if (session.isCancelled) break;
      final outcomes = await _transferChunk(chunk, session);
      if (collectOutcomes) allOutcomes.addAll(outcomes);
      await onChunk?.call(List<TransferOutcome>.unmodifiable(outcomes));
    }
    return List<TransferOutcome>.unmodifiable(allOutcomes);
  }

  Future<List<TransferOutcome>> _transferChunk(
    List<PreparedHide> chunk,
    ImportSession session,
  ) async {
    final requests = [
      for (final job in chunk)
        MediaHideRequest(
          clientId: job.id,
          path: job.originalPath,
          mediaId: job.source.assetId,
          newPath: job.destinationPath,
          isVideo: job.isVideo,
        ),
    ];

    List<MediaRenameResult> results;
    try {
      results = await _withTimeout(
        _renamer.hideToVaultBatch(requests),
        timeout: Duration(seconds: 20 + chunk.length * 5),
        label: 'hide batch timed out (${chunk.length} items)',
      );
    } catch (error, stackTrace) {
      debugPrint('hide batch failed: $error\n$stackTrace');
      results = const [];
    }

    final byId = <String, MediaRenameResult>{};
    for (final result in results) {
      final id = result.clientId;
      if (id != null) byId[id] = result;
    }
    for (var index = 0;
        index < chunk.length && index < results.length;
        index++) {
      byId.putIfAbsent(chunk[index].id, () => results[index]);
    }

    final outcomes = <TransferOutcome>[];
    for (final job in chunk) {
      if (session.isCancelled) break;
      final result = await _resolveResult(job, byId[job.id]);
      outcomes.add(await _toOutcome(job, result));
    }
    return outcomes;
  }

  Future<MediaRenameResult> _resolveResult(
    PreparedHide job,
    MediaRenameResult? batchResult,
  ) async {
    var result = batchResult;
    if (result == null || !result.ok) {
      final recovered = await _recoverExistingDestination(job.destinationPath);
      if (recovered != null) return _recovered(job, recovered);

      try {
        final single = await _withTimeout(
          _renamer.hideToVault(
            path: job.originalPath,
            mediaId: job.source.assetId,
            newPath: job.destinationPath,
            isVideo: job.isVideo,
          ),
          timeout: const Duration(seconds: 30),
          label: 'hide timed out: ${job.originalName}',
        );
        result = MediaRenameResult(
          ok: single.ok,
          newPath: single.newPath,
          error: single.error,
          needManageStorage: single.needManageStorage,
          size: single.size,
          clientId: job.id,
          method: single.method,
        );
      } catch (error) {
        result = MediaRenameResult(
          ok: false,
          error: error.toString(),
          clientId: job.id,
        );
      }

      if (!result.ok) {
        final recoveredAgain =
            await _recoverExistingDestination(job.destinationPath);
        if (recoveredAgain != null) return _recovered(job, recoveredAgain);
      }
    }
    return result;
  }

  Future<TransferOutcome> _toOutcome(
    PreparedHide job,
    MediaRenameResult result,
  ) async {
    if (!result.ok) {
      return TransferOutcome.failure(
        job: job,
        errorCode: result.needManageStorage
            ? ImportErrorCode.needManageStorage
            : _errorCode(result.error),
        rawError: result.error,
      );
    }

    final path = result.newPath ?? job.destinationPath;
    var size = result.size ?? 0;
    if (size <= 0) size = await _recoverExistingDestination(path) ?? 0;
    if (size <= 0) {
      return TransferOutcome.failure(
        job: job,
        errorCode: ImportErrorCode.emptyDest,
        rawError: 'empty_dest',
      );
    }
    return TransferOutcome.success(
      job: job,
      destinationPath: path,
      sizeBytes: size,
    );
  }

  Future<int?> _recoverExistingDestination(String path) async {
    try {
      if (!await _files.exists(path)) return null;
      final length = await _files.length(path);
      return length > 0 ? length : null;
    } catch (error, stackTrace) {
      debugPrint('destination recovery ($path): $error\n$stackTrace');
      return null;
    }
  }

  static MediaRenameResult _recovered(PreparedHide job, int size) {
    return MediaRenameResult(
      ok: true,
      newPath: job.destinationPath,
      size: size,
      clientId: job.id,
      method: 'recovered',
    );
  }

  static ImportErrorCode _errorCode(String? error) {
    if (error != null && error.toLowerCase().contains('timeout')) {
      return ImportErrorCode.timeout;
    }
    return ImportErrorCode.transferFailed;
  }

  static Future<T> _withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
    required String label,
  }) {
    return future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(label, timeout),
    );
  }
}
