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
  Future<AppUpdateCheck> checkForUpdate() async {
    if (!_updater.isAvailable) return const AppUpdateCheck.unavailable();

    return switch (await _updater.checkForUpdate()) {
      UpdateStatus.upToDate => const AppUpdateCheck.upToDate(),
      UpdateStatus.outdated => const AppUpdateCheck.hotUpdateAvailable(),
      UpdateStatus.restartRequired => const AppUpdateCheck.restartRequired(),
      UpdateStatus.unavailable => const AppUpdateCheck.unavailable(),
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
