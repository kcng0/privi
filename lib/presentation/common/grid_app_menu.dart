import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/utils/album_query_utils.dart';
import '../../core/utils/media_query_utils.dart';
import '../../domain/enums.dart';
import 'vault_sheet.dart';

typedef SortPickerChanged = void Function(
  List<MediaSort> sorts,
  bool multiSortEnabled,
);

typedef AlbumSortPickerChanged = void Function(
  List<AlbumSort> sorts,
  bool multiSortEnabled,
);

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
    required bool multiSortEnabled,
    required SortPickerChanged onChanged,
    List<MediaSort>? options,
  }) async {
    await _showSortPickerCore<MediaSort>(
      context,
      selected: selected,
      multiSortEnabled: multiSortEnabled,
      options: options ?? MediaSort.values,
      label: (l10n, sort) => _sortLabel(l10n, sort),
      icon: MediaQueryUtils.sortIcon,
      update: MediaQueryUtils.updateSortSelection,
      onChanged: onChanged,
    );
  }

  static Future<void> showAlbumSortPicker(
    BuildContext context, {
    required List<AlbumSort> selected,
    required bool multiSortEnabled,
    required AlbumSortPickerChanged onChanged,
    List<AlbumSort>? options,
  }) async {
    await _showSortPickerCore<AlbumSort>(
      context,
      selected: selected,
      multiSortEnabled: multiSortEnabled,
      options: options ?? AlbumSort.values,
      label: AlbumQueryUtils.sortLabelL10n,
      icon: AlbumQueryUtils.sortIcon,
      update: ({
        required current,
        required selected,
        required multiSortEnabled,
      }) =>
          AlbumQueryUtils.updateSortSelection(
        current: current,
        selected: selected,
        multiSortEnabled: multiSortEnabled,
      ),
      onChanged: onChanged,
    );
  }

  static Future<void> _showSortPickerCore<T>(
    BuildContext context, {
    required List<T> selected,
    required bool multiSortEnabled,
    required List<T> options,
    required String Function(AppLocalizations, T) label,
    required IconData Function(T) icon,
    required List<T> Function({
      required List<T> current,
      required T selected,
      required bool multiSortEnabled,
    }) update,
    required void Function(List<T>, bool) onChanged,
  }) async {
    var working = List<T>.of(selected);
    var multiSort = multiSortEnabled;

    await showVaultSheet<void>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              void select(T sort) {
                setLocal(() {
                  working = update(
                    current: working,
                    selected: sort,
                    multiSortEnabled: multiSort,
                  );
                  if (sort is AlbumSort && sort == AlbumSort.custom) {
                    multiSort = false;
                  }
                });
                onChanged(List.unmodifiable(working), multiSort);
              }

              void setMultiSort(bool enabled) {
                setLocal(() {
                  multiSort = enabled;
                  if (!enabled && working.length > 1) {
                    working = [working.first];
                  }
                });
                onChanged(List.unmodifiable(working), multiSort);
              }

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              ctx.l10n.sort,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            ctx.l10n.multiSort,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Switch(
                            value: multiSort,
                            onChanged: working.any(
                              (value) =>
                                  value is AlbumSort &&
                                  value == AlbumSort.custom,
                            )
                                ? null
                                : setMultiSort,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (ctx, i) {
                          final s = options[i];
                          final on = working.contains(s);
                          final priority = working.indexOf(s) + 1;
                          final primary = Theme.of(ctx).colorScheme.primary;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              icon(s),
                              color: on ? primary : Colors.white70,
                            ),
                            title: Text(
                              label(ctx.l10n, s),
                              style: TextStyle(
                                color: on ? primary : Colors.white,
                              ),
                            ),
                            trailing: !on
                                ? null
                                : multiSort
                                    ? SizedBox.square(
                                        dimension: 24,
                                        child: Center(
                                          child: Badge(
                                            label: Text('$priority'),
                                            backgroundColor: primary,
                                          ),
                                        ),
                                      )
                                    : Icon(Icons.check, color: primary),
                            onTap: () => select(s),
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
    return showVaultSheet<int>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
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
