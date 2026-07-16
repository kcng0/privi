import 'package:flutter/material.dart';

import '../../core/l10n.dart';

import '../../core/utils/media_query_utils.dart';
import '../../domain/enums.dart';

/// Shared app-bar overflow actions for media grids (Invisible + Visible).
///
/// Keeps Select / Style / Search / Sort in one ⋮ menu so sort/search are not
/// separate app-bar icons.

String _sortLabel(AppLocalizations l10n, MediaSort s) => switch (s) {
      MediaSort.dateAddedDesc => l10n.sortNewestFirst,
      MediaSort.dateAddedAsc => l10n.sortOldestFirst,
      MediaSort.nameAsc => l10n.sortNameAsc,
      MediaSort.nameDesc => l10n.sortNameDesc,
      MediaSort.ratingDesc => l10n.sortHighestRating,
      MediaSort.ratingAsc => l10n.sortLowestRating,
    };

abstract final class GridAppMenu {
  /// Column choices for media thumb grids (Visible + Invisible albums).
  static const mediaColumnOptions = [2, 3, 4, 5];

  /// Column choices for home album mosaic.
  static const albumColumnOptions = [3, 4];

  static Future<void> showSortPicker(
    BuildContext context, {
    required List<MediaSort> selected,
    required ValueChanged<List<MediaSort>> onChanged,
    List<MediaSort>? options,
  }) async {
    final opts = options ?? MediaSort.values;
    final working = List<MediaSort>.of(selected);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B3A36),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              void toggle(MediaSort s) {
                setLocal(() {
                  MediaQueryUtils.toggleSort(working, s);
                  if (working.isEmpty) {
                    working.add(MediaSort.dateAddedDesc);
                  }
                });
                onChanged(List<MediaSort>.of(working));
              }

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          ctx.l10n.sort,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: opts.length,
                        itemBuilder: (ctx, i) {
                          final s = opts[i];
                          final on = working.contains(s);
                          final primary = Theme.of(ctx).colorScheme.primary;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              MediaQueryUtils.sortIcon(s),
                              color: on ? primary : Colors.white70,
                            ),
                            title: Text(
                              _sortLabel(ctx.l10n, s),
                              style: TextStyle(
                                color: on ? primary : Colors.white,
                              ),
                            ),
                            trailing:
                                on ? Icon(Icons.check, color: primary) : null,
                            onTap: () => toggle(s),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Future<int?> showStylePicker(
    BuildContext context, {
    required int current,
    List<int> options = mediaColumnOptions,
    String? title,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B3A36),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.45;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title ?? ctx.l10n.layoutStyle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final n in options)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            Icons.grid_view,
                            color: n == current
                                ? Theme.of(ctx).colorScheme.primary
                                : Colors.white70,
                          ),
                          title: Text(
                            ctx.l10n.columnsCount(n),
                            style: TextStyle(
                              color: n == current
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Colors.white,
                            ),
                          ),
                          trailing: n == current
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(ctx).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, n),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }
}
