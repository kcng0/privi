import '../../../application/platform/vault_access.dart';

/// iOS has no Android-style all-files grant for the app-private vault.
final class IosVaultAccessAdapter implements VaultAccess {
  const IosVaultAccessAdapter();

  @override
  bool get requiresUserGrant => false;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<void> openSettings() async {
    // There is no equivalent system setting for the app-private vault.
  }
}
