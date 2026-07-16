import 'package:drift/drift.dart';

import '../../domain/models/album.dart';
import '../../domain/models/media_item.dart';
import '../db/database.dart';
import '../services/vault_storage_service.dart';

/// CRUD + streams over [MediaItem]. Maps Drift rows ↔ domain models.
class MediaRepository {
  MediaRepository(this._db, this._storage);

  final AppDatabase _db;
  final VaultStorageService _storage;

  Future<void> insert(MediaItem item, {String? userAlbumId}) async {
    try {
      await _db.insertMedia(
        MediaItemsCompanion.insert(
          id: item.id,
          privatePath: item.privatePath,
          originalPath: Value(item.originalPath),
          originalName: item.originalName,
          mimeType: item.mimeType,
          isVideo: item.isVideo,
          width: Value(item.width),
          height: Value(item.height),
          durationMs: Value(item.durationMs),
          rating: Value(item.rating.clamp(0, 3)),
          dateAdded: item.dateAdded,
          dateTaken: Value(item.dateTaken),
          sizeBytes: item.sizeBytes,
          thumbnailPath: Value(item.thumbnailPath),
          deletedAt: Value(item.deletedAt),
        ),
      );
    } catch (e) {
      // insert fallback if original_path column missing on old DBs mid-upgrade
      await _db.insertMedia(
        MediaItemsCompanion.insert(
          id: item.id,
          privatePath: item.privatePath,
          originalName: item.originalName,
          mimeType: item.mimeType,
          isVideo: item.isVideo,
          width: Value(item.width),
          height: Value(item.height),
          durationMs: Value(item.durationMs),
          rating: Value(item.rating.clamp(0, 3)),
          dateAdded: item.dateAdded,
          dateTaken: Value(item.dateTaken),
          sizeBytes: item.sizeBytes,
          thumbnailPath: Value(item.thumbnailPath),
          deletedAt: Value(item.deletedAt),
        ),
      );
    }
    if (userAlbumId != null &&
        userAlbumId != SystemAlbumIds.all &&
        userAlbumId != SystemAlbumIds.favorites &&
        userAlbumId != SystemAlbumIds.recycle) {
      await _db.addMembership(
        userAlbumId,
        item.id,
        DateTime.now().toUtc(),
      );
    }
  }

  Future<void> updateRating(String id, int rating) =>
      _db.updateMediaRating(id, rating.clamp(0, 3));

  Future<void> softDelete(String id) =>
      _db.softDeleteMedia(id, DateTime.now().toUtc());

  Future<void> restore(String id) => _db.restoreMedia(id);

  Future<void> purge(String id) async {
    final row = await _db.getMediaById(id);
    if (row == null) return;
    await _storage.deleteMediaFiles(
      privatePath: row.privatePath,
      thumbnailPath: row.thumbnailPath,
    );
    await _db.hardDeleteMedia(id);
  }

  /// Drop DB membership/row only (media file already renamed/revealed elsewhere).
  Future<void> hardDeleteRowOnly(String id) => _db.hardDeleteMedia(id);

  Stream<List<MediaItem>> watchForAlbum(String albumId) {
    if (albumId == SystemAlbumIds.all) {
      return _db.watchActiveMedia().map(_mapList);
    }
    if (albumId == SystemAlbumIds.favorites) {
      return _db.watchFavorites().map(_mapList);
    }
    if (albumId == SystemAlbumIds.recycle) {
      return _db.watchRecycleBin().map(_mapList);
    }
    return _db.watchInUserAlbum(albumId).map(_mapList);
  }

  Future<List<String>> listActivePrivatePaths() => _db.listActivePrivatePaths();

  Future<int> totalBytes() => _db.sumMediaBytes();

  Future<bool> existsByPrivatePath(String path) =>
      _db.existsByPrivatePath(path);

  MediaItem _map(MediaItemRow r) => MediaItem(
        id: r.id,
        privatePath: r.privatePath,
        originalPath: r.originalPath,
        originalName: r.originalName,
        mimeType: r.mimeType,
        isVideo: r.isVideo,
        width: r.width,
        height: r.height,
        durationMs: r.durationMs,
        rating: r.rating,
        dateAdded: r.dateAdded,
        dateTaken: r.dateTaken,
        sizeBytes: r.sizeBytes,
        thumbnailPath: r.thumbnailPath,
        deletedAt: r.deletedAt,
      );

  List<MediaItem> _mapList(List<MediaItemRow> rows) =>
      rows.map(_map).toList(growable: false);
}
