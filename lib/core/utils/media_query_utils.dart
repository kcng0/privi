import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/models/media_item.dart';
import '../../l10n/app_localizations.dart';
import 'media_chronology.dart';

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
      return MediaChronology.compare(
        leftDate: MediaChronology.forVaultItem(a),
        leftName: a.originalName,
        rightDate: MediaChronology.forVaultItem(b),
        rightName: b.originalName,
        ascending: false,
      );
    });
    return list;
  }

  static int _compareOne(MediaItem a, MediaItem b, MediaSort s) {
    switch (s) {
      case MediaSort.dateAddedDesc:
        // Prefer original capture time so hide/unhide doesn't reshuffle.
        return MediaChronology.compare(
          leftDate: MediaChronology.forVaultItem(a),
          leftName: a.originalName,
          rightDate: MediaChronology.forVaultItem(b),
          rightName: b.originalName,
          ascending: false,
        );
      case MediaSort.dateAddedAsc:
        return MediaChronology.compare(
          leftDate: MediaChronology.forVaultItem(a),
          leftName: a.originalName,
          rightDate: MediaChronology.forVaultItem(b),
          rightName: b.originalName,
          ascending: true,
        );
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

  static String sortLabel(MediaSort s) => switch (s) {
        MediaSort.dateAddedDesc => 'Newest first',
        MediaSort.dateAddedAsc => 'Oldest first',
        MediaSort.nameAsc => 'Name A–Z',
        MediaSort.nameDesc => 'Name Z–A',
        MediaSort.ratingDesc => 'Highest rating',
        MediaSort.ratingAsc => 'Lowest rating',
      };

  /// Localized sort label (UI). Prefer this over [sortLabel] in widgets.
  static String sortLabelL10n(AppLocalizations l10n, MediaSort s) {
    switch (s) {
      case MediaSort.dateAddedDesc:
        return l10n.sortNewestFirst;
      case MediaSort.dateAddedAsc:
        return l10n.sortOldestFirst;
      case MediaSort.nameAsc:
        return l10n.sortNameAsc;
      case MediaSort.nameDesc:
        return l10n.sortNameDesc;
      case MediaSort.ratingDesc:
        return l10n.sortHighestRating;
      case MediaSort.ratingAsc:
        return l10n.sortLowestRating;
    }
  }

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

  /// Localized summary for overflow menu subtitles.
  static String sortsSummaryL10n(AppLocalizations l10n, List<MediaSort> sorts) {
    if (sorts.isEmpty) {
      return sortLabelL10n(l10n, MediaSort.dateAddedDesc);
    }
    if (sorts.length == 1) {
      return sortLabelL10n(l10n, sorts.first);
    }
    return l10n.sortsCount(sorts.length);
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
