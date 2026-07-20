import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/lock/lock_controller.dart';

/// Marks an in-app media route as active.
///
/// System Back from viewer/player does **not** re-auth by itself (status stays
/// unlocked). Backgrounding the app still arms auto-lock: a wall-clock stamp
/// is checked on [AppLifecycleState.resumed] (Dart timers alone are unreliable
/// while Android suspends the isolate).
class KeepVaultUnlocked extends ConsumerStatefulWidget {
  const KeepVaultUnlocked({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeepVaultUnlocked> createState() => _KeepVaultUnlockedState();
}

class _KeepVaultUnlockedState extends ConsumerState<KeepVaultUnlocked> {
  late final LockController _lock;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    // ref.read is OK in initState; keep vault open for the whole route lifetime.
    _lock = ref.read(lockControllerProvider.notifier);
    _lock.suppressAutoLock();
    _holding = true;
  }

  @override
  void dispose() {
    if (_holding) {
      _lock.releaseAutoLockSuppress();
      _holding = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
