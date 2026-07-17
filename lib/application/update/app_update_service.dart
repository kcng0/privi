/// User-visible state of the signed application update channel.
enum AppUpdateStatus {
  upToDate,
  updateAvailable,
  restartRequired,
  unavailable,
}

/// Application boundary for checking and downloading signed code updates.
abstract interface class AppUpdateService {
  Future<int?> readCurrentPatchNumber();

  Future<AppUpdateStatus> checkForUpdate();

  Future<void> downloadUpdate();
}
