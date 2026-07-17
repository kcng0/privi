import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/import/import_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../data/services/import_service.dart';

/// Progress UI for hide/import. Title says “Hiding…” (not stuck-looking silence).
class ImportProgressSheet extends ConsumerWidget {
  const ImportProgressSheet({super.key, this.title});

  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final p = state.progress;
    final theme = Theme.of(context);
    final running = state.running;
    final cancelling = state.cancelling || (p?.cancelled ?? false);

    return PopScope(
      // Allow system back to request cancel while running (does not pop).
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && running) {
          ref.read(importControllerProvider.notifier).cancel();
        }
      },
      // SafeArea keeps Cancel clear of gesture/nav bars (3-button + gesture).
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title ??
                    (cancelling ? context.l10n.cancelled : context.l10n.hiding),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (p != null) ...[
                LinearProgressIndicator(
                  value: p.total == 0 ? null : p.fraction.clamp(0.0, 1.0),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  p.total == 0
                      ? (cancelling
                          ? context.l10n.cancelled
                          : context.l10n.hiding)
                      : '${p.done} / ${p.total}',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _phaseMessage(context, p.phase),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (p.currentName != null && !cancelling) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    p.currentName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (p.failed > 0 || p.skipped > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.l10n
                          .progressOkSkipFail(p.imported, p.skipped, p.failed),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ] else
                const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                // Always enabled while running so cancel works during resolve.
                onPressed: running && !cancelling
                    ? () => ref.read(importControllerProvider.notifier).cancel()
                    : null,
                child: Text(
                  cancelling ? context.l10n.cancelled : context.l10n.cancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showImportProgressSheet(
  BuildContext context, {
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (_) => ImportProgressSheet(title: title),
  );
}

String _phaseMessage(BuildContext context, ImportPhase phase) {
  final l10n = context.l10n;
  return switch (phase) {
    ImportPhase.resolving => l10n.resolvingMedia,
    ImportPhase.hiding => l10n.hiding,
    ImportPhase.unhiding => l10n.unhiding,
    ImportPhase.cancelled => l10n.cancelled,
    ImportPhase.done => l10n.done,
  };
}
