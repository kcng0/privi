import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'app.dart';
import 'application/providers.dart';
import 'application/settings/settings_controller.dart';
import 'application/update/app_release_source.dart';
import 'application/update/app_restart_service.dart';
import 'application/update/app_update_coordinator.dart';
import 'application/update/external_url_launcher.dart';
import 'core/app_build_info.dart';
import 'data/services/android_external_url_launcher.dart';
import 'data/services/github_app_release_source.dart';
import 'data/services/ios_app_release_source.dart';
import 'data/services/ios_app_restart_service.dart';
import 'data/services/ios_external_url_launcher.dart';
import 'data/services/platform_app_restart_service.dart';
import 'data/services/shorebird_app_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final packageInfo = await PackageInfo.fromPlatform();
  final hotUpdateService = ShorebirdAppUpdateService(
    updater: ShorebirdUpdater(),
  );
  final currentVersion = Version.parse(packageInfo.version);
  final AppReleaseSource releaseSource = Platform.isIOS
      ? const IosAppReleaseSource()
      : GithubAppReleaseSource(client: http.Client());
  final appUpdateService = AppUpdateCoordinator(
    currentVersion: currentVersion,
    releaseSource: releaseSource,
    hotUpdates: hotUpdateService,
  );
  final AppRestartService appRestartService = Platform.isIOS
      ? const IosAppRestartService()
      : const PlatformAppRestartService();
  final ExternalUrlLauncher externalUrlLauncher = Platform.isIOS
      ? const IosExternalUrlLauncher()
      : const AndroidExternalUrlLauncher();
  final appBuildInfo = AppBuildInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
    patchNumber: await hotUpdateService.readCurrentPatchNumber(),
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appBuildInfoProvider.overrideWithValue(appBuildInfo),
      appRestartServiceProvider.overrideWithValue(appRestartService),
      externalUrlLauncherProvider.overrideWithValue(externalUrlLauncher),
      appUpdateServiceProvider.overrideWithValue(appUpdateService),
    ],
  );
  container.read(databaseProvider);
  await container.read(vaultStorageProvider).ensureVault();
  final settings = container.read(settingsControllerProvider);

  if (settings.flagSecure) {
    try {
      final capabilities =
          await container.read(privacyShieldProvider).apply(true);
      if (!capabilities.appSwitcherProtected) {
        debugPrint('privacy shield unavailable: ${capabilities.diagnostic}');
      }
    } catch (error, stackTrace) {
      debugPrint('privacy shield startup failed: $error\n$stackTrace');
      rethrow;
    }
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
