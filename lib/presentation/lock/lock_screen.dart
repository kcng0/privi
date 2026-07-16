import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/lock/lock_controller.dart';
import '../../core/constants.dart';
import '../../core/theme/vault_colors.dart';
import '../../domain/enums.dart';
import 'pattern_lock.dart';
import 'pin_pad.dart';

/// Lock / first-run pattern setup + biometric.
/// Default root credential is **pattern**; legacy PIN installs still unlock via pad.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  // Pattern setup
  String? _setupFirst;
  bool _confirming = false;
  bool _busy = false;
  bool _bioPrompted = false;
  bool _bioInFlight = false;
  bool _patternError = false;
  int _patternKey = 0;

  // Legacy PIN path
  String _buffer = '';
  static const int _pinLen = 4;

  @override
  void initState() {
    super.initState();
    // Bootstrap loads biometric flags async — also re-try from [build] listen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBiometric());
  }

  /// Auto-prompt system biometric once per lock session when enabled.
  ///
  /// Must not race [_bootstrap]: early frames often have
  /// `biometricEnabled == false` until secure storage is read.
  Future<void> _maybeBiometric() async {
    if (!mounted || _bioPrompted || _bioInFlight || _busy) return;
    final lock = ref.read(lockControllerProvider);
    if (lock.status != LockStatus.locked) return;
    if (!lock.biometricEnabled || !lock.biometricAvailable) return;

    _bioPrompted = true;
    _bioInFlight = true;
    // Let the pattern UI paint first so cancel fallback looks correct.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    if (ref.read(lockControllerProvider).status != LockStatus.locked) {
      _bioInFlight = false;
      return;
    }
    try {
      setState(() => _busy = true);
      await ref.read(lockControllerProvider.notifier).unlockWithBiometric();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _bioInFlight = false;
        });
      } else {
        _bioInFlight = false;
      }
    }
  }

  void _resetPatternWidget() {
    setState(() {
      _patternKey++;
      _patternError = false;
    });
  }

  Future<void> _onPattern(String pattern) async {
    if (_busy) return;
    final lock = ref.read(lockControllerProvider);
    ref.read(lockControllerProvider.notifier).clearError();

    if (lock.status == LockStatus.needsSetup) {
      await _handleSetupPattern(pattern);
      return;
    }

    setState(() => _busy = true);
    final ok = await ref
        .read(lockControllerProvider.notifier)
        .unlockWithPattern(pattern);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _patternError = true;
      }
    });
    if (!ok) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) _resetPatternWidget();
    }
  }

  Future<void> _handleSetupPattern(String pattern) async {
    if (!_confirming) {
      setState(() {
        _setupFirst = pattern;
        _confirming = true;
        _patternError = false;
      });
      _resetPatternWidget();
      return;
    }
    if (_setupFirst != null && pattern == _setupFirst) {
      setState(() => _busy = true);
      final lockNotifier = ref.read(lockControllerProvider.notifier);
      // Save pattern but stay on LockScreen so the biometric opt-in dialog
      // is not disposed when status would otherwise flip to unlocked.
      await lockNotifier.setupPattern(pattern, unlockNow: false);
      if (!mounted) return;
      setState(() => _busy = false);

      final lock = ref.read(lockControllerProvider);
      if (lock.biometricAvailable) {
        final enable = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Enable biometric unlock?'),
            content: const Text(
              'Use fingerprint or face for faster unlock. '
              'Your pattern remains the backup unlock.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enable'),
              ),
            ],
          ),
        );
        if (enable == true && mounted) {
          setState(() => _busy = true);
          try {
            final ok = await lockNotifier.setBiometricEnabled(true);
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Biometric not enabled — you can try again in Settings',
                  ),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e')),
              );
            }
          }
          if (mounted) setState(() => _busy = false);
        }
      }
      // Always enter the app after setup (with or without biometrics).
      if (mounted) {
        await lockNotifier.enterAppAfterSetup();
      }
    } else {
      setState(() {
        _setupFirst = null;
        _confirming = false;
        _patternError = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patterns did not match — try again')),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) _resetPatternWidget();
    }
  }

  // ── Legacy PIN ──────────────────────────────────────────────

  Future<void> _onDigit(String d) async {
    if (_busy) return;
    if (_buffer.length >= _pinLen) return;
    setState(() => _buffer += d);
    ref.read(lockControllerProvider.notifier).clearError();
    if (_buffer.length < _pinLen) return;
    setState(() => _busy = true);
    final ok = await ref.read(lockControllerProvider.notifier).unlock(_buffer);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _buffer = '';
    });
    if (!ok) {
      // error via lock state
    }
  }

  void _backspace() {
    if (_buffer.isEmpty || _busy) return;
    setState(() => _buffer = _buffer.substring(0, _buffer.length - 1));
  }

  Future<void> _onBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(lockControllerProvider.notifier).unlockWithBiometric();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgotPattern() async {
    if (_busy) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot pattern?'),
        content: const Text(
          'Use your phone’s fingerprint, face, or screen lock to prove it is you. '
          'Then you can draw a new vault pattern.\n\n'
          'Your media stays on the device; only the vault unlock pattern is reset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() {
      _busy = true;
      _bioPrompted = true; // don't auto-fire unlock bio during recovery
    });
    final ok =
        await ref.read(lockControllerProvider.notifier).recoverWithSystemAuth();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _setupFirst = null;
      _confirming = false;
      _patternError = false;
      _buffer = '';
      _patternKey++;
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draw a new pattern to protect the vault'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockControllerProvider);
    // When bootstrap finishes (or lock re-enters), auto-invoke biometric.
    ref.listen<VaultLockState>(lockControllerProvider, (prev, next) {
      final becameReady = next.status == LockStatus.locked &&
          next.biometricEnabled &&
          next.biometricAvailable &&
          (prev == null ||
              prev.status != LockStatus.locked ||
              !prev.biometricEnabled ||
              !prev.biometricAvailable);
      if (becameReady) {
        // ignore: unawaited_futures
        _maybeBiometric();
      }
    });

    final isSetup = lock.status == LockStatus.needsSetup;
    final usePattern = isSetup || lock.usesPattern;
    final theme = Theme.of(context);
    final hasError = lock.errorMessage != null || _patternError;
    final showBio =
        !isSetup && lock.biometricEnabled && lock.biometricAvailable;

    // Cold start: flags may already be ready by first build after bootstrap.
    if (!_bioPrompted &&
        lock.status == LockStatus.locked &&
        lock.biometricEnabled &&
        lock.biometricAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBiometric());
    }

    final String title;
    if (isSetup) {
      title = _confirming ? 'Confirm pattern' : 'Draw a pattern';
    } else if (usePattern) {
      title = 'Draw your pattern';
    } else {
      title = 'Enter your PIN';
    }

    // Size pattern relative to screen so it stays centered on all densities.
    final patternSize =
        (MediaQuery.sizeOf(context).shortestSide * 0.72).clamp(240.0, 320.0);

    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 48,
                        color: context.vaultColors.heart,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (isSetup && !_confirming)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            'Connect at least 4 dots',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (hasError && lock.errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          lock.errorMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      if (usePattern) ...[
                        const SizedBox(height: AppSpacing.xl),
                        // Explicit Center — fixed-size pattern must not hug left.
                        Center(
                          child: PatternLock(
                            key: ValueKey(_patternKey),
                            size: patternSize,
                            onCompleted: _onPattern,
                            enabled: !_busy,
                            error: hasError,
                          ),
                        ),
                        if (showBio) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Center(
                            child: IconButton.filledTonal(
                              tooltip: 'Unlock with biometric',
                              onPressed: _busy ? null : _onBiometric,
                              icon: const Icon(Icons.fingerprint, size: 28),
                            ),
                          ),
                        ],
                        if (!isSetup) ...[
                          const SizedBox(height: AppSpacing.md),
                          TextButton(
                            onPressed: _busy ? null : _forgotPattern,
                            child: const Text('Forgot pattern?'),
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: AppSpacing.xl),
                        PinDots(
                          length: _pinLen,
                          filled: _buffer.length,
                          error: hasError,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!usePattern)
              PinPad(
                onDigit: _onDigit,
                onBackspace: _backspace,
                showBiometric: showBio,
                onBiometric: _onBiometric,
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
