import '../../data/services/import/import_models.dart';
import '../../domain/models/media_item.dart';

/// The application-facing hide and restore seam.
///
/// Implementations own platform transfer details and must not report a
/// successful hide or restore before the destination and source state are
/// verified.
abstract interface class VaultWorkflow {
  Future<int> repairOutdatedVideoThumbnails();

  Future<String?> ensureThumbnail(MediaItem item);

  Future<ImportProgress> importAll(
    List<ImportSource> sources, {
    void Function(ImportProgress progress)? onProgress,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
    ImportSession? session,
  });

  Future<bool> reveal(
    MediaItem item, {
    bool clearGalleryCache = true,
    ImportSession? session,
  });

  Future<ImportProgress> revealAll(
    List<MediaItem> items, {
    void Function(ImportProgress progress)? onProgress,
    ImportSession? session,
  });
}
