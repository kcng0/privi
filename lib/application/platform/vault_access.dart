/// Platform capability required before a Visible-library hide can start.
///
/// Android needs the user-granted all-files capability for the D5 shared-root
/// rename. iOS stores a copy in the app sandbox and therefore has no matching
/// permission or Settings destination.
abstract interface class VaultAccess {
  bool get requiresUserGrant;

  Future<bool> isReady();

  Future<void> openSettings();
}
