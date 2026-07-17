import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/app_build_info.dart';
import 'package:privi/core/constants.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('About reads the package version and build number',
      (tester) async {
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
    await tester.scrollUntilVisible(find.text(AppInfo.name), 500);

    expect(find.text('v1.2.3 (42) · Patch 7 · MIT License'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, AppInfo.name));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.2.3 (42) · Patch 7'), findsOneWidget);
  });
}

class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}
