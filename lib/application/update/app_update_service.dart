/// User-visible state of the signed application update channel.
enum AppUpdateStatus {
  upToDate,
  hotUpdateAvailable,
  appReleaseAvailable,
  restartRequired,
  unavailable,
}

/// Immutable result of checking both full releases and hot updates.
final class AppUpdateCheck {
  const AppUpdateCheck._({
    required this.status,
    this.releaseVersion,
    this.releaseUri,
  });

  const AppUpdateCheck.upToDate() : this._(status: AppUpdateStatus.upToDate);

  const AppUpdateCheck.hotUpdateAvailable()
      : this._(status: AppUpdateStatus.hotUpdateAvailable);

  const AppUpdateCheck.restartRequired()
      : this._(status: AppUpdateStatus.restartRequired);

  const AppUpdateCheck.unavailable()
      : this._(status: AppUpdateStatus.unavailable);

  const AppUpdateCheck.appReleaseAvailable({
    required String version,
    required Uri uri,
  }) : this._(
          status: AppUpdateStatus.appReleaseAvailable,
          releaseVersion: version,
          releaseUri: uri,
        );

  final AppUpdateStatus status;
  final String? releaseVersion;
  final Uri? releaseUri;
}

/// Application boundary for checking and downloading signed code updates.
abstract interface class AppUpdateService {
  Future<int?> readCurrentPatchNumber();

  Future<AppUpdateCheck> checkForUpdate();

  Future<void> downloadUpdate();
}
