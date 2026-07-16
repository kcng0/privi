import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'application/providers.dart';
import 'application/settings/settings_controller.dart';
import 'data/services/secure_window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  container.read(databaseProvider);
  await container.read(vaultStorageProvider).ensureVault();
  // Kick settings load.
  container.read(settingsControllerProvider);

  // Apply FLAG_SECURE + launch maintenance after prefs load.
  unawaited(() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final s = container.read(settingsControllerProvider);
    if (s.flagSecure) {
      await SecureWindowService().setFlagSecure(true);
    }
    try {
      final summary = await container
          .read(maintenanceServiceProvider)
          .runLaunchMaintenance(
            retentionDays: s.recycleRetentionDays,
          );
      debugPrint('maintenance: $summary');
    } catch (e) {
      debugPrint('maintenance failed: $e');
    }
  }());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PrivateHeartApp(),
    ),
  );
}
