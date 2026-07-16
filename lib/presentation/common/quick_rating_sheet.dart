import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme/vault_colors.dart';

/// Big-target rating sheet from long-press. See docs/02-design/components.md.
Future<int?> showQuickRatingSheet(
  BuildContext context, {
  required int currentRating,
}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) {
      final vc = Theme.of(ctx).extension<VaultColors>()!;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.rate,
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (i) {
                  final n = i + 1;
                  final active = currentRating >= n;
                  return Column(
                    children: [
                      IconButton(
                        iconSize: 48,
                        onPressed: () => Navigator.pop(ctx, n),
                        icon: Icon(
                          Icons.favorite,
                          color: active ? vc.heart : vc.heartOutline,
                        ),
                      ),
                      Text('$n'),
                    ],
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 0),
                child: Text(context.l10n.clear),
              ),
            ],
          ),
        ),
      );
    },
  );
}
