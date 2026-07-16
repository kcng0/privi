import 'package:flutter_test/flutter_test.dart';
import 'package:privateheart_vault/core/utils/media_query_utils.dart';
import 'package:privateheart_vault/domain/enums.dart';
import 'package:privateheart_vault/domain/models/media_item.dart';

MediaItem item({
  required String id,
  required String name,
  int rating = 0,
  DateTime? dateAdded,
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
    dateTaken: null,
    sizeBytes: 10,
    thumbnailPath: null,
  );
}

void main() {
  group('MediaQueryUtils', () {
    final a = item(id: 'a', name: 'alpha.jpg', rating: 1, dateAdded: DateTime.utc(2026, 1, 3));
    final b = item(id: 'b', name: 'beta.jpg', rating: 3, dateAdded: DateTime.utc(2026, 1, 1));
    final c = item(id: 'c', name: 'gamma.png', rating: 0, dateAdded: DateTime.utc(2026, 1, 2));
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
  });
}
