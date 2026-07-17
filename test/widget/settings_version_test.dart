import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/application/update/app_restart_service.dart';
import 'package:privi/application/update/app_update_service.dart';
import 'package:privi/core/app_build_info.dart';
import 'package:privi/core/constants.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('About reads the package version and build number',
      (tester) async {
    await _pumpSettings(tester, _FakeAppUpdateService());
    await tester.scrollUntilVisible(find.text(AppInfo.name), 500);

    expect(find.text('v1.2.3 (42) · Patch 7 · MIT License'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, AppInfo.name));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.2.3 (42) · Patch 7'), findsOneWidget);
  });

  testWidgets('update is not downloaded before user confirmation',
      (tester) async {
    final service = _FakeAppUpdateService(
      status: AppUpdateStatus.updateAvailable,
    );
    final restart = _FakeAppRestartService();
    await _pumpSettings(tester, service, appRestartService: restart);
    await tester.scrollUntilVisible(find.text('Check updates'), 500);

    await tester.tap(find.text('Check updates'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(service.checkCalls, 1);
    expect(service.downloadCalls, 0);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Download and restart now?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 0);
    expect(restart.restartCalls, 0);
  });

  testWidgets('confirmed update downloads and restarts the app',
      (tester) async {
    final service = _FakeAppUpdateService(
      status: AppUpdateStatus.updateAvailable,
    );
    final restart = _FakeAppRestartService();
    await _pumpSettings(tester, service, appRestartService: restart);
    await tester.scrollUntilVisible(find.text('Check updates'), 500);

    await tester.tap(find.text('Check updates'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(restart.restartCalls, 1);
    expect(find.text('Restart failed. Reopen Privi.'), findsNothing);
  });

  testWidgets('ready update restarts without downloading again',
      (tester) async {
    final service = _FakeAppUpdateService(
      status: AppUpdateStatus.restartRequired,
    );
    final restart = _FakeAppRestartService();
    await _pumpSettings(tester, service, appRestartService: restart);
    await tester.scrollUntilVisible(find.text('Check updates'), 500);

    await tester.tap(find.text('Check updates'));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 0);
    expect(restart.restartCalls, 1);
  });

  testWidgets('up-to-date check does not request download permission',
      (tester) async {
    final service = _FakeAppUpdateService();
    await _pumpSettings(tester, service);
    await tester.scrollUntilVisible(find.text('Check updates'), 500);

    await tester.tap(find.text('Check updates'));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 0);
    expect(find.text('Update available'), findsNothing);
    expect(find.text('Up to date'), findsOneWidget);
  });

  testWidgets('download failure remains visible', (tester) async {
    final service = _FakeAppUpdateService(
      status: AppUpdateStatus.updateAvailable,
      downloadError: Exception('network unavailable'),
    );
    final restart = _FakeAppRestartService();
    await _pumpSettings(tester, service, appRestartService: restart);
    await tester.scrollUntilVisible(find.text('Check updates'), 500);

    await tester.tap(find.text('Check updates'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(restart.restartCalls, 0);
    expect(find.text('Update failed'), findsOneWidget);
  });

  testWidgets('restart failure remains visible after a successful download',
      (tester) async {
    final service = _FakeAppUpdateService(
      status: AppUpdateStatus.updateAvailable,
    );
    final restart = _FakeAppRestartService(
      error: StateError('restart unavailable'),
    );
    await _pumpSettings(tester, service, appRestartService: restart);
    await tester.scrollUntilVisible(find.text('Check updates'), 500);

    await tester.tap(find.text('Check updates'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(restart.restartCalls, 1);
    expect(find.text('Restart failed. Reopen Privi.'), findsOneWidget);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  AppUpdateService appUpdateService, {
  AppRestartService? appRestartService,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appBuildInfoProvider.overrideWithValue(
          AppBuildInfo(
            version: '1.2.3',
            buildNumber: '42',
            patchNumber: 7,
          ),
        ),
        appRestartServiceProvider.overrideWithValue(
          appRestartService ?? _FakeAppRestartService(),
        ),
        appUpdateServiceProvider.overrideWithValue(appUpdateService),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
        vaultSizeBytesProvider.overrideWith((ref) async => 0),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAppUpdateService implements AppUpdateService {
  _FakeAppUpdateService({
    this.status = AppUpdateStatus.upToDate,
    this.downloadError,
  });

  final AppUpdateStatus status;
  final Object? downloadError;
  int checkCalls = 0;
  int downloadCalls = 0;

  @override
  Future<AppUpdateStatus> checkForUpdate() async {
    checkCalls++;
    return status;
  }

  @override
  Future<void> downloadUpdate() async {
    downloadCalls++;
    if (downloadError case final error?) throw error;
  }

  @override
  Future<int?> readCurrentPatchNumber() async => null;
}

class _FakeAppRestartService implements AppRestartService {
  _FakeAppRestartService({this.error});

  final Object? error;
  int restartCalls = 0;

  @override
  Future<void> restart() async {
    restartCalls++;
    if (error case final restartError?) throw restartError;
  }
}

class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}
