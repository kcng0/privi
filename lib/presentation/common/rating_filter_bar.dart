import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../domain/enums.dart';

class RatingFilterBar extends StatelessWidget {
  const RatingFilterBar({
    super.key,
    required this.value,
    required this.heartLevels,
    required this.onChanged,
    required this.onHeartsPressed,
    this.heartsKey,
  });

  final RatingFilter value;
  final Set<int> heartLevels;
  final ValueChanged<RatingFilter> onChanged;
  final VoidCallback onHeartsPressed;
  final Key? heartsKey;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final heartsSelected = heartLevels.isNotEmpty;
    final heartsLabel = heartsSelected
        ? '♥ ${([1, 2, 3].where(heartLevels.contains).join(','))}'
        : context.l10n.hearts;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          _chip(
            context,
            label: context.l10n.all,
            selected: value == RatingFilter.all && !heartsSelected,
            onTap: () => onChanged(RatingFilter.all),
          ),
          _chip(
            context,
            key: heartsKey,
            label: heartsLabel,
            selected: heartsSelected,
            avatar: Icon(
              Icons.favorite,
              size: 16,
              color: heartsSelected ? primary : Colors.white54,
            ),
            onTap: onHeartsPressed,
          ),
          _chip(
            context,
            label: context.l10n.favorites,
            selected: value == RatingFilter.favorites && !heartsSelected,
            onTap: () => onChanged(RatingFilter.favorites),
          ),
          _chip(
            context,
            label: context.l10n.unrated,
            selected: value == RatingFilter.unrated && !heartsSelected,
            onTap: () => onChanged(RatingFilter.unrated),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Key? key,
    Widget? avatar,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        key: key,
        avatar: avatar,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: primary.withValues(alpha: 0.35),
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 12,
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
