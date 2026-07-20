import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/gallery/gallery_controller.dart';
import 'application/import/import_controller.dart';
import 'application/import/share_queue_controller.dart';
import 'application/lock/lock_controller.dart';
import 'application/player/external_player_coordinator.dart';
import 'application/providers.dart';
import 'application/settings/settings_controller.dart';
import 'core/l10n.dart';
import 'core/theme/app_theme.dart';
import 'data/services/import_service.dart';
import 'data/services/share_intent_service.dart';
import 'domain/enums.dart';
import 'presentation/home/home_shell.dart';
import 'presentation/import/import_progress_sheet.dart';
import 'presentation/import/import_result_message.dart';
import 'presentation/lock/lock_screen.dart';

/// Root of the app. Dark theme only (docs/02-design/design-system.md).
class PrivateHeartApp extends ConsumerStatefulWidget {
  const PrivateHeartApp({super.key});

  @override
  ConsumerState<PrivateHeartApp> createState() => _PrivateHeartAppState();
}

class _PrivateHeartAppState extends ConsumerState<PrivateHeartApp> {
  late final ShareIntentService _share;
  final _navKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _share = ShareIntentService(stager: ref.read(shareSourceStagerProvider));
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
    _lifecycleListener = AppLifecycleListener(onStateChange: _onLifecycleState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _share.start(_onShared).catchError(
          (Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'share intent',
                context: ErrorDescription('while starting share intake'),
              ),
            );
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(_share.dispose());
    super.dispose();
  }

  void _onLifecycleState(AppLifecycleState state) {
    ref.read(externalPlayerCoordinatorProvider).onAppLifecycle(state);
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
        final detail = importOutcomeDetail(ctx, summary.errorCode);
        final originalMessage = ctx.l10n.hiddenSharedItems(summary.imported);
        final message = detail == null
            ? originalMessage
            : summary.imported > 0
                ? '$originalMessage · $detail'
                : detail;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(message)),
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
      builder: (context, child) => _RootGate(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeShell(),
    );
  }
}

class _RootGate extends ConsumerWidget {
  const _RootGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Touch vault + db so streams are live once unlocked.
    ref.watch(databaseProvider);

    final lock = ref.watch(lockControllerProvider);
    final requiresUnlock = lock.status != LockStatus.unlocked;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: requiresUnlock,
          child: ExcludeSemantics(
            excluding: requiresUnlock,
            child: IgnorePointer(
              key: const ValueKey('vault-content-interaction'),
              ignoring: requiresUnlock,
              child: child,
            ),
          ),
        ),
        if (requiresUnlock)
          HeroControllerScope.none(
            child: Navigator(
              key: const ValueKey('vault-lock-overlay'),
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'vault-lock'),
                builder: (_) => const LockScreen(),
              ),
            ),
          ),
      ],
    );
  }
}
