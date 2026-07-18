import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/utils/album_query_utils.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/album.dart';
import 'package:privi/domain/models/album_group.dart';
import 'package:privi/domain/models/album_view.dart';
import 'package:privi/domain/models/group_view.dart';
import 'package:privi/domain/models/shelf_entry.dart';

Album album(
  String id, {
  int rating = 0,
  int? sortIndex,
  DateTime? pinnedAt,
  DateTime? createdAt,
}) =>
    Album(
      id: id,
      name: id,
      isSystem: false,
      createdAt: createdAt ?? DateTime.utc(2026),
      rating: rating,
      sortIndex: sortIndex,
      pinnedAt: pinnedAt,
    );

void main() {
  test('default sort preserves pinned-first then name behavior', () {
    final result = AlbumQueryUtils.apply(
      albums: [
        album('zeta'),
        album('beta', pinnedAt: DateTime.utc(2026, 1, 1)),
        album('alpha', pinnedAt: DateTime.utc(2026, 1, 2)),
      ],
    );

    expect(result.map((item) => item.id), ['alpha', 'beta', 'zeta']);
  });

  test('custom order is complete, ignores pin, and puts null indexes last', () {
    final result = AlbumQueryUtils.apply(
      albums: [
        album('alpha', sortIndex: 2, pinnedAt: DateTime.utc(2026)),
        album('zeta', sortIndex: 0),
        album('beta'),
      ],
      sorts: const [AlbumSort.custom],
    );

    expect(result.map((item) => item.id), ['zeta', 'alpha', 'beta']);
  });

  test('selection keeps one criterion per family and custom is exclusive', () {
    expect(
      AlbumQueryUtils.updateSortSelection(
        current: const [AlbumSort.nameAsc, AlbumSort.ratingDesc],
        selected: AlbumSort.nameDesc,
        multiSortEnabled: true,
      ),
      const [AlbumSort.nameDesc, AlbumSort.ratingDesc],
    );
    expect(
      AlbumQueryUtils.updateSortSelection(
        current: const [AlbumSort.nameAsc, AlbumSort.ratingDesc],
        selected: AlbumSort.custom,
        multiSortEnabled: true,
      ),
      const [AlbumSort.custom],
    );
  });

  test('groups and albums share rating and custom sort keys', () {
    final albumEntry = AlbumEntry(
      AlbumView(album: album('album', rating: 2, sortIndex: 3), count: 1),
    );
    final groupEntry = GroupEntry(
      GroupView(
        group: AlbumGroup(
          id: 'group',
          name: 'group',
          createdAt: DateTime.utc(2026),
          sortIndex: 1,
        ),
        members: const [],
        totalCount: 0,
        maxRating: 3,
      ),
    );

    expect(
      AlbumQueryUtils.compareEntries(
        groupEntry,
        albumEntry,
        sorts: const [AlbumSort.ratingDesc],
      ),
      lessThan(0),
    );
    expect(
      AlbumQueryUtils.compareEntries(
        groupEntry,
        albumEntry,
        sorts: const [AlbumSort.custom],
      ),
      lessThan(0),
    );
  });
}
