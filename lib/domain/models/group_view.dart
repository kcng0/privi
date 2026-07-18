import 'album_group.dart';
import 'album_view.dart';

class GroupView {
  const GroupView({
    required this.group,
    required this.members,
    required this.totalCount,
    required this.maxRating,
    this.cover,
  });

  final AlbumGroup group;
  final List<AlbumView> members;
  final int totalCount;
  final int maxRating;
  final AlbumView? cover;
}
