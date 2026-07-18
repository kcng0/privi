import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/utils/media_query_utils.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';

MediaItem item({
  required String id,
  required String name,
  int rating = 0,
  DateTime? dateAdded,
  DateTime? dateTaken,
}) {
  return MediaItem(
    id: id,
    privatePath: '/vault/$name',
    originalName: name,
    mimeType: 'image/jpeg',
    isVideo: false,
    width: 100,
    height: 100,
    durationMs: null,
    rating: rating,
    dateAdded: dateAdded ?? DateTime.utc(2026, 1, 1),
    dateTaken: dateTaken,
    sizeBytes: 10,
    thumbnailPath: null,
  );
}

void main() {
  group('MediaQueryUtils', () {
    final a = item(
      id: 'a',
      name: 'alpha.jpg',
      rating: 1,
      dateAdded: DateTime.utc(2026, 1, 3),
    );
    final b = item(
      id: 'b',
      name: 'beta.jpg',
      rating: 3,
      dateAdded: DateTime.utc(2026, 1, 1),
    );
    final c = item(
      id: 'c',
      name: 'gamma.png',
      rating: 0,
      dateAdded: DateTime.utc(2026, 1, 2),
    );
    final all = [a, b, c];

    test('search filters by original name', () {
      final out = MediaQueryUtils.apply(items: all, search: 'beta');
      expect(out.map((e) => e.id), ['b']);
    });

    test('rating filter favorites', () {
      final out = MediaQueryUtils.apply(
        items: all,
        rating: RatingFilter.favorites,
      );
      expect(out.map((e) => e.id).toSet(), {'a', 'b'});
    });

    test('sort by rating desc', () {
      final out = MediaQueryUtils.apply(
        items: all,
        sorts: const [MediaSort.ratingDesc],
      );
      expect(out.map((e) => e.id).toList(), ['b', 'a', 'c']);
    });

    test('sort by name asc', () {
      final out = MediaQueryUtils.apply(
        items: all,
        sorts: const [MediaSort.nameAsc],
      );
      expect(out.map((e) => e.originalName).toList(), [
        'alpha.jpg',
        'beta.jpg',
        'gamma.png',
      ]);
    });

    test('sort labels non-empty', () {
      for (final s in MediaSort.values) {
        expect(MediaQueryUtils.sortLabel(s), isNotEmpty);
      }
    });

    test('multi criteria rating then newest', () {
      final out = MediaQueryUtils.apply(
        items: all,
        sorts: const [MediaSort.ratingDesc, MediaSort.dateAddedDesc],
      );
      expect(out.map((e) => e.id).toList(), ['b', 'a', 'c']);
    });

    test('single sort replaces the previous criterion', () {
      final out = MediaQueryUtils.updateSortSelection(
        current: const [MediaSort.dateAddedDesc],
        selected: MediaSort.nameAsc,
        multiSortEnabled: false,
      );

      expect(out, const [MediaSort.nameAsc]);
    });

    test('multi sort preserves selection order as priority', () {
      final withRating = MediaQueryUtils.updateSortSelection(
        current: const [MediaSort.dateAddedDesc],
        selected: MediaSort.ratingDesc,
        multiSortEnabled: true,
      );
      final withName = MediaQueryUtils.updateSortSelection(
        current: withRating,
        selected: MediaSort.nameAsc,
        multiSortEnabled: true,
      );

      expect(
        withName,
        const [
          MediaSort.dateAddedDesc,
          MediaSort.ratingDesc,
          MediaSort.nameAsc,
        ],
      );
    });

    test('changing direction keeps the criterion priority', () {
      final out = MediaQueryUtils.updateSortSelection(
        current: const [
          MediaSort.ratingDesc,
          MediaSort.dateAddedDesc,
          MediaSort.nameAsc,
        ],
        selected: MediaSort.dateAddedAsc,
        multiSortEnabled: true,
      );

      expect(
        out,
        const [
          MediaSort.ratingDesc,
          MediaSort.dateAddedAsc,
          MediaSort.nameAsc,
        ],
      );
    });

    test('newest first prefers dateTaken over hide-time dateAdded', () {
      // Simulated hide reshuffle: older capture written with newer dateAdded.
      final olderCapture = item(
        id: 'old',
        name: 'old.jpg',
        dateAdded: DateTime.utc(2026, 6, 1),
        dateTaken: DateTime.utc(2020, 1, 1),
      );
      final newerCapture = item(
        id: 'new',
        name: 'new.jpg',
        dateAdded: DateTime.utc(2026, 1, 1),
        dateTaken: DateTime.utc(2025, 1, 1),
      );
      final out = MediaQueryUtils.apply(
        items: [olderCapture, newerCapture],
        sorts: const [MediaSort.dateAddedDesc],
      );
      expect(out.map((e) => e.id).toList(), ['new', 'old']);
    });

    test('equal capture dates use the original name deterministically', () {
      final sameDate = DateTime.utc(2025, 1, 1);
      final zeta = item(
        id: 'zeta',
        name: 'Zeta.mp4',
        dateTaken: sameDate,
      );
      final alpha = item(
        id: 'alpha',
        name: 'alpha.mp4',
        dateTaken: sameDate,
      );

      final out = MediaQueryUtils.apply(
        items: [zeta, alpha],
        sorts: const [MediaSort.dateAddedDesc],
      );

      expect(out.map((e) => e.id), ['zeta', 'alpha']);
    });
  });
}
