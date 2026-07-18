import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import '../../domain/models/shelf_entry.dart';
import '../../l10n/app_localizations.dart';

/// Single source of truth for user-album sorting and sort-picker semantics.
abstract final class AlbumQueryUtils {
  static int compare(
    Album a,
    Album b, {
    required List<AlbumSort> sorts,
  }) {
    final effective = sorts.isEmpty ? const [AlbumSort.nameAsc] : sorts;
    if (!effective.contains(AlbumSort.custom)) {
      final pin = _comparePinned(a, b);
      if (pin != 0) return pin;
    }
    for (final sort in effective) {
      final value = _compareOne(a, b, sort);
      if (value != 0) return value;
    }
    return _compareName(a, b);
  }

  static int compareEntries(
    ShelfEntry left,
    ShelfEntry right, {
    required List<AlbumSort> sorts,
  }) {
    final effective = sorts.isEmpty ? const [AlbumSort.nameAsc] : sorts;
    final leftAlbum = left is AlbumEntry ? left.view.album : null;
    final rightAlbum = right is AlbumEntry ? right.view.album : null;
    if (!effective.contains(AlbumSort.custom) &&
        leftAlbum != null &&
        rightAlbum != null) {
      final pinned = _comparePinned(leftAlbum, rightAlbum);
      if (pinned != 0) return pinned;
    }
    if (!effective.contains(AlbumSort.custom)) {
      if (leftAlbum != null && right is GroupEntry && leftAlbum.isPinned) {
        return -1;
      }
      if (left is GroupEntry && rightAlbum != null && rightAlbum.isPinned) {
        return 1;
      }
    }
    for (final sort in effective) {
      final value = _compareEntryOne(left, right, sort);
      if (value != 0) return value;
    }
    return _entryName(left).compareTo(_entryName(right));
  }

  static int _compareEntryOne(
    ShelfEntry left,
    ShelfEntry right,
    AlbumSort sort,
  ) {
    final leftAlbum = left is AlbumEntry ? left.view.album : null;
    final rightAlbum = right is AlbumEntry ? right.view.album : null;
    if (left is AlbumEntry && right is AlbumEntry) {
      return _compareOne(left.view.album, right.view.album, sort);
    }
    final leftGroup = left is GroupEntry ? left.view : null;
    final rightGroup = right is GroupEntry ? right.view : null;
    if (leftGroup != null && rightGroup != null) {
      return switch (sort) {
        AlbumSort.createdAtDesc =>
          rightGroup.group.createdAt.compareTo(leftGroup.group.createdAt),
        AlbumSort.createdAtAsc =>
          leftGroup.group.createdAt.compareTo(rightGroup.group.createdAt),
        AlbumSort.nameAsc || AlbumSort.nameDesc => sort == AlbumSort.nameAsc
            ? leftGroup.group.name.toLowerCase().compareTo(
                  rightGroup.group.name.toLowerCase(),
                )
            : rightGroup.group.name.toLowerCase().compareTo(
                  leftGroup.group.name.toLowerCase(),
                ),
        AlbumSort.ratingDesc =>
          rightGroup.maxRating.compareTo(leftGroup.maxRating),
        AlbumSort.ratingAsc =>
          leftGroup.maxRating.compareTo(rightGroup.maxRating),
        AlbumSort.custom => _compareNullableIndex(
            leftGroup.group.sortIndex,
            rightGroup.group.sortIndex,
            leftGroup.group.name,
            rightGroup.group.name,
          ),
      };
    }
    if (leftAlbum != null || leftGroup != null) {
      final leftName = _entryName(left);
      final rightName = _entryName(right);
      final leftDate = leftAlbum?.createdAt ?? leftGroup!.group.createdAt;
      final rightDate = rightAlbum?.createdAt ?? rightGroup!.group.createdAt;
      final leftRating = leftAlbum?.rating ?? leftGroup!.maxRating;
      final rightRating = rightAlbum?.rating ?? rightGroup!.maxRating;
      return switch (sort) {
        AlbumSort.createdAtDesc => rightDate.compareTo(leftDate),
        AlbumSort.createdAtAsc => leftDate.compareTo(rightDate),
        AlbumSort.nameAsc => leftName.compareTo(rightName),
        AlbumSort.nameDesc => rightName.compareTo(leftName),
        AlbumSort.ratingDesc => rightRating.compareTo(leftRating),
        AlbumSort.ratingAsc => leftRating.compareTo(rightRating),
        AlbumSort.custom => _compareNullableIndex(
            leftAlbum?.sortIndex ?? leftGroup?.group.sortIndex,
            rightAlbum?.sortIndex ?? rightGroup?.group.sortIndex,
            leftName,
            rightName,
          ),
      };
    }
    return _entryName(left).compareTo(_entryName(right));
  }

  static int _compareNullableIndex(
    int? left,
    int? right,
    String leftName,
    String rightName,
  ) {
    if (left == null && right == null) return leftName.compareTo(rightName);
    if (left == null) return 1;
    if (right == null) return -1;
    return left == right
        ? leftName.compareTo(rightName)
        : left.compareTo(right);
  }

  static String _entryName(ShelfEntry entry) => switch (entry) {
        AlbumEntry(:final view) => view.album.name.toLowerCase(),
        GroupEntry(:final view) => view.group.name.toLowerCase(),
      };

  static List<Album> apply({
    required List<Album> albums,
    List<AlbumSort> sorts = const [AlbumSort.nameAsc],
  }) {
    final list = List<Album>.of(albums);
    list.sort((a, b) => compare(a, b, sorts: sorts));
    return list;
  }

  static int _comparePinned(Album a, Album b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    if (a.isPinned && b.isPinned) {
      final value = b.pinnedAt!.compareTo(a.pinnedAt!);
      if (value != 0) return value;
    }
    return 0;
  }

  static int _compareOne(Album a, Album b, AlbumSort sort) => switch (sort) {
        AlbumSort.createdAtDesc => b.createdAt.compareTo(a.createdAt),
        AlbumSort.createdAtAsc => a.createdAt.compareTo(b.createdAt),
        AlbumSort.nameAsc => _compareName(a, b),
        AlbumSort.nameDesc => _compareName(b, a),
        AlbumSort.ratingDesc => b.rating.compareTo(a.rating),
        AlbumSort.ratingAsc => a.rating.compareTo(b.rating),
        AlbumSort.custom => _compareCustom(a, b),
      };

  static int _compareCustom(Album a, Album b) {
    if (a.sortIndex == null && b.sortIndex == null) return _compareName(a, b);
    if (a.sortIndex == null) return 1;
    if (b.sortIndex == null) return -1;
    final value = a.sortIndex!.compareTo(b.sortIndex!);
    return value == 0 ? _compareName(a, b) : value;
  }

  static int _compareName(Album a, Album b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  static int familyRank(AlbumSort sort) => switch (sort) {
        AlbumSort.createdAtDesc || AlbumSort.createdAtAsc => 0,
        AlbumSort.nameAsc || AlbumSort.nameDesc => 1,
        AlbumSort.ratingDesc || AlbumSort.ratingAsc => 2,
        AlbumSort.custom => 3,
      };

  static List<AlbumSort> updateSortSelection({
    required List<AlbumSort> current,
    required AlbumSort selected,
    required bool multiSortEnabled,
  }) {
    if (selected == AlbumSort.custom) return const [AlbumSort.custom];
    if (!multiSortEnabled) return [selected];
    final next = List<AlbumSort>.of(current)
      ..removeWhere((sort) => sort == AlbumSort.custom);
    final selectedIndex = next.indexOf(selected);
    if (selectedIndex >= 0) {
      if (next.length > 1) next.removeAt(selectedIndex);
      return next.isEmpty ? [AlbumSort.nameAsc] : next;
    }
    final familyIndex = next.indexWhere(
      (sort) => familyRank(sort) == familyRank(selected),
    );
    if (familyIndex >= 0) {
      next[familyIndex] = selected;
    } else {
      next.add(selected);
    }
    return next;
  }

  static void validateSorts(
    List<AlbumSort> sorts, {
    required bool multiSortEnabled,
  }) {
    if (sorts.isEmpty) {
      throw const FormatException('At least one album sort is required');
    }
    if (sorts.contains(AlbumSort.custom)) {
      if (sorts.length != 1 || multiSortEnabled) {
        throw const FormatException('Custom album sort is exclusive');
      }
      return;
    }
    if (!multiSortEnabled && sorts.length != 1) {
      throw const FormatException('Single-sort mode requires one criterion');
    }
    final families = sorts.map(familyRank).toSet();
    if (families.length != sorts.length) {
      throw const FormatException('Album sort families must be unique');
    }
  }

  static String sortLabel(AlbumSort sort) => switch (sort) {
        AlbumSort.createdAtDesc => 'Newest albums',
        AlbumSort.createdAtAsc => 'Oldest albums',
        AlbumSort.nameAsc => 'Name A-Z',
        AlbumSort.nameDesc => 'Name Z-A',
        AlbumSort.ratingDesc => 'Highest rating',
        AlbumSort.ratingAsc => 'Lowest rating',
        AlbumSort.custom => 'Custom order',
      };

  static String sortLabelL10n(AppLocalizations l10n, AlbumSort sort) =>
      switch (sort) {
        AlbumSort.createdAtDesc => l10n.albumSortNewest,
        AlbumSort.createdAtAsc => l10n.albumSortOldest,
        AlbumSort.nameAsc => l10n.sortNameAsc,
        AlbumSort.nameDesc => l10n.sortNameDesc,
        AlbumSort.ratingDesc => l10n.sortHighestRating,
        AlbumSort.ratingAsc => l10n.sortLowestRating,
        AlbumSort.custom => l10n.albumSortCustom,
      };

  static IconData sortIcon(AlbumSort sort) => switch (sort) {
        AlbumSort.createdAtDesc => Icons.arrow_downward,
        AlbumSort.createdAtAsc => Icons.arrow_upward,
        AlbumSort.nameAsc || AlbumSort.nameDesc => Icons.sort_by_alpha,
        AlbumSort.ratingDesc => Icons.favorite,
        AlbumSort.ratingAsc => Icons.favorite_border,
        AlbumSort.custom => Icons.drag_handle,
      };

  static String sortsSummary(List<AlbumSort> sorts) {
    if (sorts.isEmpty) return sortLabel(AlbumSort.nameAsc);
    if (sorts.length == 1) return sortLabel(sorts.first);
    return '${sorts.length} sorts';
  }

  static String sortsSummaryL10n(AppLocalizations l10n, List<AlbumSort> sorts) {
    if (sorts.isEmpty) return sortLabelL10n(l10n, AlbumSort.nameAsc);
    if (sorts.length == 1) return sortLabelL10n(l10n, sorts.first);
    return l10n.sortsCount(sorts.length);
  }
}
