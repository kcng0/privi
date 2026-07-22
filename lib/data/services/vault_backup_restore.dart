part of 'vault_backup_service.dart';

final class _VaultBackupRestorer {
  _VaultBackupRestorer({
    required AppDatabase db,
    required MediaRepository media,
    required AlbumRepository albums,
    required VaultStorageService storage,
    required Uuid uuid,
    required String platformName,
    required bool usePrivateMediaStorage,
  })  : manifests = const _VaultBackupManifestCodec(),
        preflight = _VaultBackupRestorePreflight(
          db: db,
          albums: albums,
          uuid: uuid,
          files: const _VaultBackupFileOps(),
          manifests: const _VaultBackupManifestCodec(),
        ),
        installer = _VaultBackupRestoreInstaller(
          db: db,
          media: media,
          albums: albums,
          storage: storage,
          uuid: uuid,
          platformName: platformName,
          usePrivateMediaStorage: usePrivateMediaStorage,
          files: const _VaultBackupFileOps(),
        );

  final _VaultBackupManifestCodec manifests;
  final _VaultBackupRestorePreflight preflight;
  final _VaultBackupRestoreInstaller installer;

  Future<VaultBackupResult> run(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) async {
    final activeSession = session ?? VaultBackupSession();
    try {
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.preparing,
        0,
        0,
      );
      final manifest = await manifests.read(sourceDirectory);
      final plans = await preflight.run(
        sourceDirectory,
        manifest,
        activeSession,
        onProgress,
      );
      return await installer.run(
        manifest,
        plans,
        activeSession,
        onProgress,
      );
    } on _VaultBackupCancelled {
      return const VaultBackupResult(
        itemCount: 0,
        totalBytes: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      );
    } on VaultBackupException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('vault restore failed: $error\n$stackTrace');
      throw VaultBackupException(
        VaultBackupErrorCode.databaseWriteFailed,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }
}

String _restoreSourceFolder(String? originalPath) {
  if (originalPath == null || originalPath.trim().isEmpty) return 'Imported';
  return HideNaming.sanitizeFolder(p.basename(p.dirname(originalPath)));
}

Never _missingRestoreField(String field) {
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: field,
    stage: VaultBackupStage.checkingBackup,
  );
}
