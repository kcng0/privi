import 'package:shorebird_code_push/shorebird_code_push.dart';

import '../../application/update/app_update_service.dart';

/// Shorebird adapter kept outside presentation and application logic.
final class ShorebirdAppUpdateService implements AppUpdateService {
  const ShorebirdAppUpdateService({required ShorebirdUpdater updater})
      : _updater = updater;

  final ShorebirdUpdater _updater;

  @override
  Future<int?> readCurrentPatchNumber() async {
    if (!_updater.isAvailable) return null;
    return (await _updater.readCurrentPatch())?.number;
  }

  @override
  Future<AppUpdateStatus> checkForUpdate() async {
    if (!_updater.isAvailable) return AppUpdateStatus.unavailable;

    return switch (await _updater.checkForUpdate()) {
      UpdateStatus.upToDate => AppUpdateStatus.upToDate,
      UpdateStatus.outdated => AppUpdateStatus.updateAvailable,
      UpdateStatus.restartRequired => AppUpdateStatus.restartRequired,
      UpdateStatus.unavailable => AppUpdateStatus.unavailable,
    };
  }

  @override
  Future<void> downloadUpdate() async {
    if (!_updater.isAvailable) {
      throw StateError('Shorebird updater is unavailable');
    }
    await _updater.update();
  }
}
