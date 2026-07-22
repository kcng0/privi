part of 'vault_backup_service.dart';

final class _VaultBackupFileOps {
  const _VaultBackupFileOps();

  Future<_HashedFile> hashSource(
    File source,
    String fileName, {
    required String? expectedDigest,
  }) async {
    if (!await source.exists()) {
      throw VaultBackupException(
        VaultBackupErrorCode.sourceMissing,
        fileName: fileName,
        stage: VaultBackupStage.checkingSource,
      );
    }
    FileStat before;
    try {
      before = await source.stat();
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.sourceUnreadable,
        fileName: fileName,
        stage: VaultBackupStage.checkingSource,
        cause: error,
      );
    }
    if (before.type != FileSystemEntityType.file) {
      throw VaultBackupException(
        VaultBackupErrorCode.sourceUnreadable,
        fileName: fileName,
        stage: VaultBackupStage.checkingSource,
      );
    }
    if (before.size <= 0) {
      throw VaultBackupException(
        VaultBackupErrorCode.sourceEmpty,
        fileName: fileName,
        stage: VaultBackupStage.checkingSource,
      );
    }
    try {
      final digest = await digestFile(source);
      final after = await source.stat();
      if (after.type != FileSystemEntityType.file ||
          after.size != before.size) {
        throw VaultBackupException(
          VaultBackupErrorCode.sourceChanged,
          fileName: fileName,
          stage: VaultBackupStage.checkingSource,
        );
      }
      if (expectedDigest != null &&
          (!_isSha256Digest(expectedDigest) || digest != expectedDigest)) {
        throw VaultBackupException(
          VaultBackupErrorCode.sourceChanged,
          fileName: fileName,
          stage: VaultBackupStage.checkingSource,
        );
      }
      return _HashedFile(length: after.size, digest: digest);
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.sourceUnreadable,
        fileName: fileName,
        stage: VaultBackupStage.checkingSource,
        cause: error,
      );
    }
  }

  Future<_HashedFile> hashPayload(
    File? source,
    String fileName, {
    required int? expectedLength,
    required String? expectedDigest,
  }) async {
    if (source == null) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadMissing,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      final length = await source.length();
      if (length <= 0) {
        throw VaultBackupException(
          VaultBackupErrorCode.payloadEmpty,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      if (expectedLength != null && length != expectedLength) {
        throw VaultBackupException(
          VaultBackupErrorCode.payloadLengthMismatch,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final digest = await digestFile(source);
      if (expectedDigest != null && digest != expectedDigest) {
        throw VaultBackupException(
          VaultBackupErrorCode.payloadDigestMismatch,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return _HashedFile(length: length, digest: digest);
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadUnreadable,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  Future<void> copyAndVerify({
    required File source,
    required File target,
    required int? expectedLength,
    required String? expectedDigest,
    required String fileName,
    required VaultBackupErrorCode mismatchCode,
    required VaultBackupStage stage,
  }) async {
    try {
      await source.openRead().pipe(target.openWrite());
      final length = await target.length();
      if (expectedLength != null && length != expectedLength) {
        throw VaultBackupException(
          mismatchCode == VaultBackupErrorCode.sourceChanged
              ? VaultBackupErrorCode.sourceChanged
              : VaultBackupErrorCode.payloadLengthMismatch,
          fileName: fileName,
          stage: stage,
        );
      }
      final digest = await digestFile(target);
      if (expectedDigest != null && digest != expectedDigest) {
        throw VaultBackupException(
          mismatchCode,
          fileName: fileName,
          stage: stage,
        );
      }
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        mismatchCode == VaultBackupErrorCode.sourceChanged
            ? VaultBackupErrorCode.sourceChanged
            : VaultBackupErrorCode.payloadUnreadable,
        fileName: fileName,
        stage: stage,
        cause: error,
      );
    }
  }

  Future<String> digestFile(File file) async {
    final hash = await sha256.bind(file.openRead()).first;
    return base64UrlEncode(hash.bytes);
  }

  Future<File?> backupFile(
    Directory mediaDirectory,
    String name, {
    required bool required,
  }) async {
    _validateBackupName(name);
    final mediaType = await FileSystemEntity.type(
      mediaDirectory.path,
      followLinks: false,
    );
    if (mediaType == FileSystemEntityType.link) {
      throw VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (mediaType != FileSystemEntityType.directory) {
      throw VaultBackupException(
        required
            ? VaultBackupErrorCode.payloadMissing
            : VaultBackupErrorCode.payloadUnreadable,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final file = File(p.join(mediaDirectory.path, name));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (required) {
        throw VaultBackupException(
          VaultBackupErrorCode.payloadMissing,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return null;
    }
    if (type == FileSystemEntityType.link) {
      throw VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (type != FileSystemEntityType.file) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadUnreadable,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      final root = await mediaDirectory.resolveSymbolicLinks();
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        throw VaultBackupException(
          VaultBackupErrorCode.unsafePath,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return file;
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadUnreadable,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  Future<void> removeFiles(Iterable<File> files) async {
    Object? firstError;
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error, stackTrace) {
        debugPrint('vault backup cleanup failed: $error\n$stackTrace');
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        cause: firstError,
      );
    }
  }

  Future<void> removeDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error, stackTrace) {
      debugPrint('vault backup staging cleanup failed: $error\n$stackTrace');
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        cause: error,
      );
    }
  }
}

void _emitBackupProgress(
  VaultBackupProgressCallback? callback,
  VaultBackupStage stage,
  int completed,
  int total, [
  String? currentFile,
]) {
  if (callback == null) return;
  try {
    callback(
      VaultBackupProgress(
        stage: stage,
        completed: completed,
        total: total,
        currentFile: currentFile,
      ),
    );
  } catch (error, stackTrace) {
    // Progress is an observer. A disposed UI must not turn a committed backup
    // into a failed operation or trigger restore cleanup after a DB commit.
    debugPrint('vault backup progress observer failed: $error\n$stackTrace');
  }
}

void _checkBackupCancelled(VaultBackupSession session) {
  if (session.isCancelled) throw _VaultBackupCancelled();
}

int _manifestInt(Object? value, String label) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: label,
    stage: VaultBackupStage.checkingBackup,
  );
}

int? _optionalManifestInt(Object? value, String label) {
  if (value == null) return null;
  if (value is int) return value;
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: label,
    stage: VaultBackupStage.checkingBackup,
  );
}

bool? _optionalManifestBool(Object? value, String label) {
  if (value == null) return null;
  if (value is bool) return value;
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: label,
    stage: VaultBackupStage.checkingBackup,
  );
}

String? _optionalManifestString(Object? value, String label) {
  if (value == null) return null;
  if (value is! String) {
    throw VaultBackupException(
      VaultBackupErrorCode.malformedManifest,
      fileName: label,
      stage: VaultBackupStage.checkingBackup,
    );
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _requiredManifestString(Object? value, String label) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: label,
    stage: VaultBackupStage.checkingBackup,
  );
}

DateTime? _manifestDate(
  Object? value,
  String label, {
  required bool strict,
  required bool required,
}) {
  final raw = _optionalManifestString(value, label);
  if (raw == null) {
    if (required) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null && strict) {
    throw VaultBackupException(
      VaultBackupErrorCode.malformedManifest,
      fileName: label,
      stage: VaultBackupStage.checkingBackup,
    );
  }
  return parsed;
}

bool _isSha256Digest(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{43}=?$').hasMatch(value);

void _validateBackupName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains(r'\')) {
    throw VaultBackupException(
      VaultBackupErrorCode.unsafePath,
      fileName: name,
      stage: VaultBackupStage.checkingBackup,
    );
  }
}

String _validatedBackupId(String value, String label) {
  final valid = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
  if (!valid.hasMatch(value)) {
    throw VaultBackupException(
      VaultBackupErrorCode.malformedManifest,
      fileName: label,
      stage: VaultBackupStage.checkingBackup,
    );
  }
  return value;
}

String? _validatedOriginalPath(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = p.normalize(value.trim());
  final inStorage =
      p.isWithin('/storage', normalized) || p.isWithin('/sdcard', normalized);
  if (!p.isAbsolute(normalized) || !inStorage) {
    throw const VaultBackupException(
      VaultBackupErrorCode.unsafePath,
      stage: VaultBackupStage.checkingBackup,
    );
  }
  return normalized;
}
