import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/models/media_item.dart';

/// Client-side search / multi-criteria sort / rating filter for album grids.
abstract final class MediaQueryUtils {
  static List<MediaItem> apply({
    required List<MediaItem> items,
    String search = '',

    /// Ordered sort keys (first = primary). Empty → newest first.
    List<MediaSort> sorts = const [MediaSort.dateAddedDesc],

    /// Back-compat single sort used by older tests.
    MediaSort? sort,
    RatingFilter rating = RatingFilter.all,

    /// When non-empty, keep items whose rating is in this set (♥ multi-select).
    /// Takes precedence over single [RatingFilter.hearts1/2/3].
    Set<int>? heartLevels,
  }) {
    Iterable<MediaItem> out = items;

    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((m) {
        final name = m.originalName.toLowerCase();
        final path = m.privatePath.toLowerCase();
        return name.contains(q) || path.contains(q);
      });
    }

    if (heartLevels != null && heartLevels.isNotEmpty) {
      out = out.where((m) => heartLevels.contains(m.rating));
    } else {
      out = out.where((m) {
        switch (rating) {
          case RatingFilter.all:
            return true;
          case RatingFilter.unrated:
            return m.rating == 0;
          case RatingFilter.favorites:
            return m.rating >= 1;
          case RatingFilter.hearts1:
            return m.rating == 1;
          case RatingFilter.hearts2:
            return m.rating == 2;
          case RatingFilter.hearts3:
            return m.rating == 3;
        }
      });
    }

    final List<MediaSort> effective;
    if (sort != null &&
        (sorts.isEmpty ||
            (sorts.length == 1 && sorts.first == MediaSort.dateAddedDesc))) {
      effective = [sort];
    } else if (sorts.isNotEmpty) {
      effective = sorts;
    } else {
      effective = const [MediaSort.dateAddedDesc];
    }

    final list = out.toList();
    list.sort((a, b) {
      for (final s in effective) {
        final c = _compareOne(a, b, s);
        if (c != 0) return c;
      }
      return _sortDate(b).compareTo(_sortDate(a));
    });
    return list;
  }

  static int _compareOne(MediaItem a, MediaItem b, MediaSort s) {
    switch (s) {
      case MediaSort.dateAddedDesc:
        // Prefer original capture time so hide/unhide doesn't reshuffle.
        return _sortDate(b).compareTo(_sortDate(a));
      case MediaSort.dateAddedAsc:
        return _sortDate(a).compareTo(_sortDate(b));
      case MediaSort.nameAsc:
        return a.originalName
            .toLowerCase()
            .compareTo(b.originalName.toLowerCase());
      case MediaSort.nameDesc:
        return b.originalName
            .toLowerCase()
            .compareTo(a.originalName.toLowerCase());
      case MediaSort.ratingDesc:
        return b.rating.compareTo(a.rating);
      case MediaSort.ratingAsc:
        return a.rating.compareTo(b.rating);
    }
  }

  /// Capture/create time when known; otherwise vault insert time.
  static DateTime _sortDate(MediaItem m) => m.dateTaken ?? m.dateAdded;

  static String sortLabel(MediaSort s) => switch (s) {
        MediaSort.dateAddedDesc => 'Newest first',
        MediaSort.dateAddedAsc => 'Oldest first',
        MediaSort.nameAsc => 'Name A–Z',
        MediaSort.nameDesc => 'Name Z–A',
        MediaSort.ratingDesc => 'Highest rating',
        MediaSort.ratingAsc => 'Lowest rating',
      };

  static IconData sortIcon(MediaSort s) => switch (s) {
        MediaSort.dateAddedDesc => Icons.arrow_downward,
        MediaSort.dateAddedAsc => Icons.arrow_upward,
        MediaSort.nameAsc => Icons.sort_by_alpha,
        MediaSort.nameDesc => Icons.sort_by_alpha,
        MediaSort.ratingDesc => Icons.favorite,
        MediaSort.ratingAsc => Icons.favorite_border,
      };

  static String sortsSummary(List<MediaSort> sorts) {
    if (sorts.isEmpty) return sortLabel(MediaSort.dateAddedDesc);
    if (sorts.length == 1) return sortLabel(sorts.first);
    return '${sorts.length} sorts';
  }

  static int sortFamilyRank(MediaSort s) => switch (s) {
        MediaSort.dateAddedDesc || MediaSort.dateAddedAsc => 0,
        MediaSort.nameAsc || MediaSort.nameDesc => 1,
        MediaSort.ratingDesc || MediaSort.ratingAsc => 2,
      };

  static void toggleSort(List<MediaSort> selected, MediaSort s) {
    if (selected.contains(s)) {
      if (selected.length > 1) selected.remove(s);
      return;
    }
    selected.removeWhere((x) => sortFamilyRank(x) == sortFamilyRank(s));
    selected.add(s);
    selected.sort((a, b) => sortFamilyRank(a).compareTo(sortFamilyRank(b)));
  }
}
