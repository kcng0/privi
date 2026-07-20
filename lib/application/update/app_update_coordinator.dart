import 'package:pub_semver/pub_semver.dart';

import 'app_release_source.dart';
import 'app_update_service.dart';

/// Checks full application releases before checking the current hot-update base.
final class AppUpdateCoordinator implements AppUpdateService {
  const AppUpdateCoordinator({
    required Version currentVersion,
    required AppReleaseSource releaseSource,
    required AppUpdateService hotUpdates,
  })  : _currentVersion = currentVersion,
        _releaseSource = releaseSource,
        _hotUpdates = hotUpdates;

  final Version _currentVersion;
  final AppReleaseSource _releaseSource;
  final AppUpdateService _hotUpdates;

  @override
  Future<AppUpdateCheck> checkForUpdate() async {
    if (_releaseSource.supported) {
      final release = await _releaseSource.readLatestRelease();
      if (release.version > _currentVersion) {
        return AppUpdateCheck.appReleaseAvailable(
          version: release.version.toString(),
          uri: release.uri,
        );
      }
    }
    return _hotUpdates.checkForUpdate();
  }

  @override
  Future<void> downloadUpdate() => _hotUpdates.downloadUpdate();

  @override
  Future<int?> readCurrentPatchNumber() => _hotUpdates.readCurrentPatchNumber();
}
