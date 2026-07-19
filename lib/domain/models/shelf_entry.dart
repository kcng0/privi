import 'album_view.dart';
import 'group_view.dart';

sealed class ShelfEntry {
  const ShelfEntry();
  String get id;
}

class AlbumEntry extends ShelfEntry {
  const AlbumEntry(this.view);
  final AlbumView view;

  @override
  String get id => view.album.id;
}

class GroupEntry extends ShelfEntry {
  const GroupEntry(this.view);
  final GroupView view;

  @override
  String get id => view.group.id;
}

class AlbumShelf {
  const AlbumShelf({
    required this.systemViews,
    required this.entries,
    this.groups = const [],
  });

  final List<AlbumView> systemViews;
  final List<ShelfEntry> entries;

  /// All persisted groups, including groups hidden by the active media filter.
  final List<GroupView> groups;
}
