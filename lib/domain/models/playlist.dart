import 'dart:math';

import 'media_item.dart';

/// In-memory playlist for album/Favorites playback.
/// See docs/03-architecture/playback.md.
class Playlist {
  Playlist({
    required List<MediaItem> items,
    this.shuffle = false,
    int cursor = 0,
  })  : items = List.unmodifiable(items),
        _order = List.generate(items.length, (i) => i),
        cursor = cursor.clamp(0, items.isEmpty ? 0 : items.length - 1) {
    if (shuffle) _reshuffle(keepCurrent: false);
  }

  final List<MediaItem> items;
  final List<int> _order;
  bool shuffle;
  int cursor;

  bool get isEmpty => items.isEmpty;
  int get length => items.length;

  MediaItem? get current {
    if (items.isEmpty) return null;
    return items[_order[cursor.clamp(0, _order.length - 1)]];
  }

  int get positionDisplay => items.isEmpty ? 0 : cursor + 1;

  bool get hasNext => cursor < _order.length - 1;
  bool get hasPrev => cursor > 0;

  void toggleShuffle() {
    shuffle = !shuffle;
    if (shuffle) {
      _reshuffle(keepCurrent: true);
    } else {
      // Restore natural order, keep current item under cursor if possible.
      final curId = current?.id;
      _order
        ..clear()
        ..addAll(List.generate(items.length, (i) => i));
      if (curId != null) {
        final idx = items.indexWhere((e) => e.id == curId);
        if (idx >= 0) cursor = idx;
      }
    }
  }

  void next() {
    if (hasNext) cursor++;
  }

  /// Next item without moving the cursor (for video preload).
  MediaItem? peekNext() {
    if (!hasNext) return null;
    return items[_order[cursor + 1]];
  }

  void prev() {
    if (hasPrev) cursor--;
  }

  void jumpToItemId(String id) {
    final itemIndex = items.indexWhere((e) => e.id == id);
    if (itemIndex < 0) return;
    final orderIndex = _order.indexOf(itemIndex);
    if (orderIndex >= 0) cursor = orderIndex;
  }

  void _reshuffle({required bool keepCurrent}) {
    final curId = keepCurrent ? current?.id : null;
    _order.shuffle(Random());
    if (curId != null) {
      final itemIndex = items.indexWhere((e) => e.id == curId);
      final orderIndex = _order.indexOf(itemIndex);
      if (orderIndex > 0) {
        _order.removeAt(orderIndex);
        _order.insert(0, itemIndex);
      }
      cursor = 0;
    } else {
      cursor = 0;
    }
  }
}
