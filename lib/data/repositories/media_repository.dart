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
      await _db.insertMedia(_toCompanion(item));
    } catch (e) {
      // insert fallback if original_path column missing on old DBs mid-upgrade
      await _db.insertMedia(_toCompanion(item, includeOriginalPath: false));
    }
    if (_isUserAlbum(userAlbumId)) {
      await _db.addMembership(
        userAlbumId!,
        item.id,
        DateTime.now().toUtc(),
      );
    }
  }

  /// Batch insert media (+ memberships) in a single SQLite transaction.
  Future<void> insertMany(
    List<({MediaItem item, String? userAlbumId})> entries,
  ) async {
    if (entries.isEmpty) return;
    final rows = <MediaItemsCompanion>[];
    final membership = <String, String>{};
    for (final e in entries) {
      rows.add(_toCompanion(e.item));
      final albumId = e.userAlbumId;
      if (_isUserAlbum(albumId)) {
        membership[e.item.id] = albumId!;
      }
    }
    try {
      await _db.insertMediaBatch(rows, membershipByMediaId: membership);
    } catch (e) {
      // Fallback: insert one-by-one so a single bad row doesn't drop the batch.
      for (final e in entries) {
        try {
          await insert(e.item, userAlbumId: e.userAlbumId);
        } catch (e2) {
          // Caller already moved files; keep going.
          // ignore: avoid_print
          assert(() {
            // ignore: avoid_print
            print('insertMany fallback failed ${e.item.id}: $e2');
            return true;
          }());
        }
      }
    }
  }

  static bool _isUserAlbum(String? userAlbumId) =>
      userAlbumId != null &&
      userAlbumId != SystemAlbumIds.all &&
      userAlbumId != SystemAlbumIds.favorites &&
      userAlbumId != SystemAlbumIds.recycle;

  MediaItemsCompanion _toCompanion(
    MediaItem item, {
    bool includeOriginalPath = true,
  }) {
    return MediaItemsCompanion.insert(
      id: item.id,
      privatePath: item.privatePath,
      originalPath:
          includeOriginalPath ? Value(item.originalPath) : const Value.absent(),
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
    );
  }

  Future<void> updateRating(String id, int rating) =>
      _db.updateMediaRating(id, rating.clamp(0, 3));

  Future<void> updateRatings(List<String> ids, int rating) =>
      _db.updateMediaRatings(ids, rating.clamp(0, 3));

  Future<void> updateThumbnail(String id, String? thumbnailPath) =>
      _db.updateMediaThumbnail(id, thumbnailPath);

  Future<void> updateDates(
    String id, {
    required DateTime dateTaken,
    required DateTime dateAdded,
  }) =>
      _db.updateMediaDates(id, dateTaken: dateTaken, dateAdded: dateAdded);

  Future<List<MediaItem>> listActive() async {
    final rows = await _db.listActiveMediaRows();
    return rows.map(_map).toList(growable: false);
  }

  Future<void> softDelete(String id) =>
      _db.softDeleteMedia(id, DateTime.now().toUtc());

  Future<void> softDeleteMany(List<String> ids) =>
      _db.softDeleteMediaMany(ids, DateTime.now().toUtc());

  Future<void> restore(String id) => _db.restoreMedia(id);

  Future<void> restoreMany(List<String> ids) => _db.restoreMediaMany(ids);

  Future<void> purge(String id) async {
    final row = await _db.getMediaById(id);
    if (row == null) return;
    await _storage.deleteMediaFiles(
      privatePath: row.privatePath,
      thumbnailPath: row.thumbnailPath,
    );
    await _db.hardDeleteMedia(id);
  }

  /// Delete files then drop rows in one DB transaction for the set.
  Future<void> purgeMany(List<String> ids) async {
    if (ids.isEmpty) return;
    final rows = await _db.getMediaByIds(ids);
    for (final row in rows) {
      await _storage.deleteMediaFiles(
        privatePath: row.privatePath,
        thumbnailPath: row.thumbnailPath,
      );
    }
    await _db.hardDeleteMediaMany(ids);
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
