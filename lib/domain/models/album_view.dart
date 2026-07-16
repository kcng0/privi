import 'album.dart';
import 'media_item.dart';

/// Album row for the Home screen: album + live count + optional cover.
class AlbumView {
  const AlbumView({
    required this.album,
    required this.count,
    this.cover,
  });

  final Album album;
  final int count;
  final MediaItem? cover;
}
