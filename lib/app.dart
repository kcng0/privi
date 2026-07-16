import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/import/import_controller.dart';
import 'application/lock/lock_controller.dart';
import 'application/providers.dart';
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

  /// Shared media received while locked; flushed on unlock.
  List<ImportSource>? _pendingShare;
  bool _flushingPendingShare = false;

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
  }

  Future<void> _onShared(List<ImportSource> sources) async {
    if (sources.isEmpty) return;
    final lock = ref.read(lockControllerProvider);
    if (lock.status != LockStatus.unlocked) {
      _pendingShare = [...?_pendingShare, ...sources];
      final ctx = _navKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Unlock to hide shared media')),
        );
      }
      return;
    }

    // Already importing: queue and let completion / unlock flush handle it.
    if (ref.read(importControllerProvider).running || _flushingPendingShare) {
      _pendingShare = [...?_pendingShare, ...sources];
      return;
    }

    await _runShareImport(sources);
  }

  Future<void> _flushPendingShare() async {
    if (_flushingPendingShare) return;
    if (ref.read(lockControllerProvider).status != LockStatus.unlocked) {
      return;
    }
    if (ref.read(importControllerProvider).running) return;

    final pending = _pendingShare;
    if (pending == null || pending.isEmpty) return;

    _flushingPendingShare = true;
    _pendingShare = null;
    try {
      await _runShareImport(pending);
    } finally {
      _flushingPendingShare = false;
      // More shares may have arrived while we were importing.
      if (_pendingShare != null &&
          _pendingShare!.isNotEmpty &&
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
      _pendingShare = [...sources, ...?_pendingShare];
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
          SnackBar(content: Text('Hidden ${summary.imported} shared items')),
        );
      }
      ref.read(importControllerProvider.notifier).clearSummary();
    } finally {
      // Shares queued while this import was running.
      if (!_flushingPendingShare &&
          _pendingShare != null &&
          _pendingShare!.isNotEmpty &&
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

    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Privi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
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
