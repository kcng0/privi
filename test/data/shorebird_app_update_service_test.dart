import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/update/app_update_service.dart';
import 'package:privi/data/services/shorebird_app_update_service.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

void main() {
  test('maps Shorebird status and delegates patch download', () async {
    final updater = _FakeShorebirdUpdater(
      status: UpdateStatus.outdated,
      currentPatch: const Patch(number: 3),
    );
    final service = ShorebirdAppUpdateService(updater: updater);

    expect(await service.readCurrentPatchNumber(), 3);
    expect(
      (await service.checkForUpdate()).status,
      AppUpdateStatus.hotUpdateAvailable,
    );

    await service.downloadUpdate();

    expect(updater.updateCalls, 1);
  });

  test('maps every non-download Shorebird status', () async {
    final cases = {
      UpdateStatus.upToDate: AppUpdateStatus.upToDate,
      UpdateStatus.restartRequired: AppUpdateStatus.restartRequired,
      UpdateStatus.unavailable: AppUpdateStatus.unavailable,
    };

    for (final entry in cases.entries) {
      final service = ShorebirdAppUpdateService(
        updater: _FakeShorebirdUpdater(status: entry.key),
      );
      expect((await service.checkForUpdate()).status, entry.value);
    }
  });

  test('does not read patch metadata when Shorebird is unavailable', () async {
    final updater = _FakeShorebirdUpdater(
      status: UpdateStatus.unavailable,
      isAvailable: false,
    );
    final service = ShorebirdAppUpdateService(updater: updater);

    expect(await service.readCurrentPatchNumber(), isNull);
    expect(updater.readPatchCalls, 0);
  });
}

class _FakeShorebirdUpdater implements ShorebirdUpdater {
  _FakeShorebirdUpdater({
    required this.status,
    this.currentPatch,
    this.isAvailable = true,
  });

  final UpdateStatus status;
  final Patch? currentPatch;

  @override
  final bool isAvailable;

  int readPatchCalls = 0;
  int updateCalls = 0;

  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async => status;

  @override
  Future<Patch?> readCurrentPatch() async {
    readPatchCalls++;
    return currentPatch;
  }

  @override
  Future<Patch?> readNextPatch() async => currentPatch;

  @override
  Future<void> update({UpdateTrack? track}) async {
    updateCalls++;
  }
}
