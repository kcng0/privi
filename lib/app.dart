import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/gallery/gallery_controller.dart';
import 'application/import/import_controller.dart';
import 'application/import/share_queue_controller.dart';
import 'application/lock/lock_controller.dart';
import 'application/providers.dart';
import 'application/settings/settings_controller.dart';
import 'core/l10n.dart';
import 'core/theme/app_theme.dart';
import 'data/services/import_service.dart';
import 'data/services/share_intent_service.dart';
import 'domain/enums.dart';
import 'presentation/home/home_shell.dart';
import 'presentation/import/import_progress_sheet.dart';
import 'presentation/lock/lock_screen.dart';

/// Root of the app. Dark theme only (docs/02-design/design-system.md).
class PrivateHeartApp extends ConsumerStatefulWidget {
  const PrivateHeartApp({super.key});

  @override
  ConsumerState<PrivateHeartApp> createState() => _PrivateHeartAppState();
}

class _PrivateHeartAppState extends ConsumerState<PrivateHeartApp>
    with WidgetsBindingObserver {
  final _share = ShareIntentService();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Always show Android status bar + navigation buttons.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _share.start(_onShared);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _share.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(lockControllerProvider.notifier).onAppLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      // Gallery permission may have been granted in system Settings while we
      // were backgrounded — refresh Visible without another Grant tap.
      ref.invalidate(galleryPermissionProvider);
      ref.invalidate(galleryFoldersProvider);
      ref.read(galleryServiceProvider).apply(const VisiblePermissionChanged());
    }
  }

  Future<void> _onShared(List<ImportSource> sources) async {
    if (sources.isEmpty) return;
    final lock = ref.read(lockControllerProvider);
    if (lock.status != LockStatus.unlocked) {
      ref.read(shareQueueControllerProvider.notifier).enqueue(sources);
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(ctx.l10n.unlockToHideShared)),
        );
      }
      return;
    }

    // Already importing: queue and let completion / unlock flush handle it.
    if (ref.read(importControllerProvider).running ||
        ref.read(shareQueueControllerProvider).flushing) {
      ref.read(shareQueueControllerProvider.notifier).enqueue(sources);
      return;
    }

    await _runShareImport(sources);
  }

  Future<void> _flushPendingShare() async {
    if (ref.read(lockControllerProvider).status != LockStatus.unlocked) {
      return;
    }
    if (ref.read(importControllerProvider).running) return;

    final queue = ref.read(shareQueueControllerProvider.notifier);
    final pending = queue.beginFlush();
    if (pending == null) return;

    try {
      await _runShareImport(pending);
    } finally {
      queue.finishFlush();
      // More shares may have arrived while we were importing.
      if (ref.read(shareQueueControllerProvider).hasPending &&
          ref.read(lockControllerProvider).status == LockStatus.unlocked) {
        // ignore: unawaited_futures
        _flushPendingShare();
      }
    }
  }

  Future<void> _runShareImport(List<ImportSource> sources) async {
    if (sources.isEmpty) return;
    final ctx = _navKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      // Context not ready — keep pending so unlock/rebuild can retry.
      ref.read(shareQueueControllerProvider.notifier).enqueue(sources);
      return;
    }

    // ignore: unawaited_futures
    showImportProgressSheet(ctx);
    try {
      final summary =
          await ref.read(importControllerProvider.notifier).runImport(sources);
      if (ctx.mounted) Navigator.of(ctx).pop();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(ctx.l10n.hiddenSharedItems(summary.imported)),
          ),
        );
      }
      ref.read(importControllerProvider.notifier).clearSummary();
    } finally {
      // Shares queued while this import was running.
      if (!ref.read(shareQueueControllerProvider).flushing &&
          ref.read(shareQueueControllerProvider).hasPending &&
          ref.read(lockControllerProvider).status == LockStatus.unlocked) {
        // ignore: unawaited_futures
        _flushPendingShare();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VaultLockState>(lockControllerProvider, (prev, next) {
      if (next.status == LockStatus.unlocked &&
          prev?.status != LockStatus.unlocked) {
        // ignore: unawaited_futures
        _flushPendingShare();
      }
    });

    final localeCode = ref.watch(settingsControllerProvider).localeCode;
    final localeOverride = localeFromCode(localeCode);

    return MaterialApp(
      navigatorKey: _navKey,
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: localeOverride,
      localeResolutionCallback: (device, supported) {
        // Manual override wins; otherwise map device language.
        if (localeOverride != null) return localeOverride;
        return resolveAppLocale(device);
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _RootGate(),
    );
  }
}

class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Touch vault + db so streams are live once unlocked.
    ref.watch(databaseProvider);

    final lock = ref.watch(lockControllerProvider);
    switch (lock.status) {
      case LockStatus.unlocked:
        return const HomeShell();
      case LockStatus.locked:
      case LockStatus.needsSetup:
        return const LockScreen();
    }
  }
}
