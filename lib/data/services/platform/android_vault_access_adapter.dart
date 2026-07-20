import '../../../application/platform/vault_access.dart';
import '../media_rename_service.dart';

/// Preserves the Android all-files gate and Settings hand-off.
final class AndroidVaultAccessAdapter implements VaultAccess {
  const AndroidVaultAccessAdapter(this._renamer);

  final MediaRenameService _renamer;

  @override
  bool get requiresUserGrant => true;

  @override
  Future<bool> isReady() => _renamer.isExternalStorageManager();

  @override
  Future<void> openSettings() => _renamer.openManageAllFilesSettings();
}
