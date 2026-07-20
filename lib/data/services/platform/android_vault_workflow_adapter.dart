import '../../../application/platform/vault_workflow.dart';
import '../../../domain/models/media_item.dart';
import '../import_service.dart';

/// Adapter preserving the existing Android D5 workflow behind the new seam.
final class AndroidVaultWorkflowAdapter implements VaultWorkflow {
  const AndroidVaultWorkflowAdapter(this._delegate);

  final ImportService _delegate;

  @override
  Future<int> repairOutdatedVideoThumbnails() =>
      _delegate.repairOutdatedVideoThumbnails();

  @override
  Future<String?> ensureThumbnail(MediaItem item) =>
      _delegate.ensureThumbnail(item);

  @override
  Future<ImportProgress> importAll(
    List<ImportSource> sources, {
    void Function(ImportProgress progress)? onProgress,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
    ImportSession? session,
  }) =>
      _delegate.importAll(
        sources,
        onProgress: onProgress,
        targetUserAlbumId: targetUserAlbumId,
        defaultSourceFolderName: defaultSourceFolderName,
        session: session,
      );

  @override
  Future<bool> reveal(
    MediaItem item, {
    bool clearGalleryCache = true,
    ImportSession? session,
  }) =>
      _delegate.reveal(
        item,
        clearGalleryCache: clearGalleryCache,
        session: session,
      );

  @override
  Future<ImportProgress> revealAll(
    List<MediaItem> items, {
    void Function(ImportProgress progress)? onProgress,
    ImportSession? session,
  }) =>
      _delegate.revealAll(
        items,
        onProgress: onProgress,
        session: session,
      );
}
