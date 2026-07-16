import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/import/import_controller.dart';
import '../../core/constants.dart';

/// Progress UI for hide/import. Title says “Hiding…” (not stuck-looking silence).
class ImportProgressSheet extends ConsumerWidget {
  const ImportProgressSheet({super.key, this.title = 'Hiding…'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final p = state.progress;
    final theme = Theme.of(context);

    return PopScope(
      canPop: !state.running,
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
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              if (p != null) ...[
                LinearProgressIndicator(
                  value: p.total == 0 ? null : p.fraction.clamp(0.0, 1.0),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('${p.done} / ${p.total}'),
                if (p.statusMessage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    p.statusMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (p.currentName != null) ...[
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
                      'ok ${p.imported} · skip ${p.skipped} · fail ${p.failed}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ] else
                const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: state.running
                    ? () =>
                        ref.read(importControllerProvider.notifier).cancel()
                    : null,
                child: const Text('Cancel'),
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
  String title = 'Hiding…',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (_) => ImportProgressSheet(title: title),
  );
}
