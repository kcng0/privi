import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/update/app_release_source.dart';
import 'package:privi/application/update/app_update_coordinator.dart';
import 'package:privi/application/update/app_update_service.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  test('new GitHub release takes priority over a hot update', () async {
    final hotUpdates = _FakeHotUpdateService(
      const AppUpdateCheck.hotUpdateAvailable(),
    );
    final coordinator = AppUpdateCoordinator(
      currentVersion: Version.parse('1.0.7'),
      releaseSource: _FakeReleaseSource(
        AppRelease(
          version: Version.parse('1.0.8'),
          uri: Uri.parse('https://github.com/kcng0/privi/releases/tag/v1.0.8'),
        ),
      ),
      hotUpdates: hotUpdates,
    );

    final result = await coordinator.checkForUpdate();

    expect(result.status, AppUpdateStatus.appReleaseAvailable);
    expect(result.releaseVersion, '1.0.8');
    expect(
      result.releaseUri,
      Uri.parse('https://github.com/kcng0/privi/releases/tag/v1.0.8'),
    );
    expect(hotUpdates.checkCalls, 0);
  });

  test('current GitHub release continues with the hot update check', () async {
    final hotUpdates = _FakeHotUpdateService(
      const AppUpdateCheck.hotUpdateAvailable(),
    );
    final coordinator = AppUpdateCoordinator(
      currentVersion: Version.parse('1.0.7'),
      releaseSource: _FakeReleaseSource(
        AppRelease(
          version: Version.parse('1.0.7'),
          uri: Uri.parse('https://github.com/kcng0/privi/releases/tag/v1.0.7'),
        ),
      ),
      hotUpdates: hotUpdates,
    );

    final result = await coordinator.checkForUpdate();

    expect(result.status, AppUpdateStatus.hotUpdateAvailable);
    expect(hotUpdates.checkCalls, 1);
  });

  test('GitHub errors are exposed instead of silently skipping the check',
      () async {
    final hotUpdates = _FakeHotUpdateService(
      const AppUpdateCheck.upToDate(),
    );
    final coordinator = AppUpdateCoordinator(
      currentVersion: Version.parse('1.0.7'),
      releaseSource: _ThrowingReleaseSource(StateError('GitHub unavailable')),
      hotUpdates: hotUpdates,
    );

    await expectLater(coordinator.checkForUpdate(), throwsStateError);
    expect(hotUpdates.checkCalls, 0);
  });

  test('patch metadata and downloads remain delegated to Shorebird', () async {
    final hotUpdates = _FakeHotUpdateService(
      const AppUpdateCheck.upToDate(),
      patchNumber: 4,
    );
    final coordinator = AppUpdateCoordinator(
      currentVersion: Version.parse('1.0.7'),
      releaseSource: _FakeReleaseSource(
        AppRelease(
          version: Version.parse('1.0.7'),
          uri: Uri.parse('https://github.com/kcng0/privi/releases/tag/v1.0.7'),
        ),
      ),
      hotUpdates: hotUpdates,
    );

    expect(await coordinator.readCurrentPatchNumber(), 4);
    await coordinator.downloadUpdate();

    expect(hotUpdates.downloadCalls, 1);
  });
}

final class _FakeReleaseSource implements AppReleaseSource {
  const _FakeReleaseSource(this.release);

  final AppRelease release;

  @override
  Future<AppRelease> readLatestRelease() async => release;
}

final class _ThrowingReleaseSource implements AppReleaseSource {
  const _ThrowingReleaseSource(this.error);

  final Object error;

  @override
  Future<AppRelease> readLatestRelease() async => throw error;
}

final class _FakeHotUpdateService implements AppUpdateService {
  _FakeHotUpdateService(this.result, {this.patchNumber});

  final AppUpdateCheck result;
  final int? patchNumber;
  int checkCalls = 0;
  int downloadCalls = 0;

  @override
  Future<AppUpdateCheck> checkForUpdate() async {
    checkCalls++;
    return result;
  }

  @override
  Future<void> downloadUpdate() async {
    downloadCalls++;
  }

  @override
  Future<int?> readCurrentPatchNumber() async => patchNumber;
}
