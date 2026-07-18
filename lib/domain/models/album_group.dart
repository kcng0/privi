/// User-defined, non-nested collection of albums.
class AlbumGroup {
  const AlbumGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortIndex,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int? sortIndex;
}
