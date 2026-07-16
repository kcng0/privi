import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/lock/lock_controller.dart';

/// Marks an in-app media route as active.
///
/// System Back from viewer/player does **not** re-auth by itself (status stays
/// unlocked). Backgrounding the app still arms the auto-lock timer (default
/// 30s) via [LockController.onAppLifecycle].
class KeepVaultUnlocked extends ConsumerStatefulWidget {
  const KeepVaultUnlocked({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeepVaultUnlocked> createState() => _KeepVaultUnlockedState();
}

class _KeepVaultUnlockedState extends ConsumerState<KeepVaultUnlocked> {
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    // ref.read is OK in initState; keep vault open for the whole route lifetime.
    ref.read(lockControllerProvider.notifier).suppressAutoLock();
    _holding = true;
  }

  @override
  void dispose() {
    if (_holding) {
      ref.read(lockControllerProvider.notifier).releaseAutoLockSuppress();
      _holding = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
