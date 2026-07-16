import '../enums.dart';

/// Domain album (system or user). See docs/03-architecture/data-model.md.
class Album {
  const Album({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.createdAt,
    this.coverMediaId,
    this.systemKind,
    this.pinnedAt,
  });

  final String id;
  final String name;
  final bool isSystem;
  final String? coverMediaId;
  final DateTime createdAt;
  final SystemAlbumKind? systemKind;

  /// Non-null when pinned to the top of the Invisible mosaic.
  final DateTime? pinnedAt;

  bool get isPinned => pinnedAt != null;
}

/// Stable IDs for the three system albums (seeded once).
abstract final class SystemAlbumIds {
  static const all = 'sys-all-media';
  static const favorites = 'sys-favorites';
  static const recycle = 'sys-recycle-bin';
}
