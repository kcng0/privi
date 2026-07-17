import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'app.dart';
import 'application/providers.dart';
import 'application/settings/settings_controller.dart';
import 'core/app_build_info.dart';
import 'data/services/shorebird_app_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final packageInfo = await PackageInfo.fromPlatform();
  final appUpdateService = ShorebirdAppUpdateService(
    updater: ShorebirdUpdater(),
  );
  final appBuildInfo = AppBuildInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
    patchNumber: await appUpdateService.readCurrentPatchNumber(),
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appBuildInfoProvider.overrideWithValue(appBuildInfo),
      appUpdateServiceProvider.overrideWithValue(appUpdateService),
    ],
  );
  container.read(databaseProvider);
  await container.read(vaultStorageProvider).ensureVault();
  final settings = container.read(settingsControllerProvider);

  if (settings.flagSecure) {
    await container.read(secureWindowServiceProvider).setFlagSecure(true);
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      try {
        final summary = await container
            .read(maintenanceServiceProvider)
            .runLaunchMaintenance(
              retentionDays: settings.recycleRetentionDays,
            );
        debugPrint('maintenance: $summary');
      } catch (e, stackTrace) {
        debugPrint('maintenance failed: $e\n$stackTrace');
      }
    }());
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PrivateHeartApp(),
    ),
  );
}
