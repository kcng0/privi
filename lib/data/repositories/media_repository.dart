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
    await _db.insertMedia(_toCompanion(item));
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
    await _db.insertMediaBatch(rows, membershipByMediaId: membership);
  }

  static bool _isUserAlbum(String? userAlbumId) =>
      userAlbumId != null &&
      userAlbumId != SystemAlbumIds.all &&
      userAlbumId != SystemAlbumIds.favorites &&
      userAlbumId != SystemAlbumIds.recycle;

  MediaItemsCompanion _toCompanion(MediaItem item) {
    return MediaItemsCompanion.insert(
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
      sourcePlatformId: Value(item.sourcePlatformId),
      sourceRemovalPending: Value(item.sourceRemovalPending),
      contentDigest: Value(item.contentDigest),
    );
  }

  Future<void> updateRating(String id, int rating) =>
      _db.updateMediaRating(id, rating.clamp(0, 3));

  Future<void> updateRatings(List<String> ids, int rating) =>
      _db.updateMediaRatings(ids, rating.clamp(0, 3));

  Future<void> updateThumbnail(String id, String? thumbnailPath) =>
      _db.updateMediaThumbnail(id, thumbnailPath);

  Future<void> updateSourceMetadata(
    String id, {
    String? sourcePlatformId,
    required bool sourceRemovalPending,
    String? contentDigest,
  }) =>
      _db.updateMediaSourceMetadata(
        id,
        sourcePlatformId: sourcePlatformId,
        sourceRemovalPending: sourceRemovalPending,
        contentDigest: contentDigest,
      );

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

  /// Batch drop rows after a successful native unhide batch.
  Future<void> hardDeleteRowsOnly(List<String> ids) =>
      _db.hardDeleteMediaMany(ids);

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

  Future<List<String>> listActiveOriginalPaths() =>
      _db.listActiveOriginalPaths();

  Future<int> totalBytes() => _db.sumMediaBytes();

  Future<bool> existsByPrivatePath(String path) =>
      _db.existsByPrivatePath(path);

  Future<MediaItem?> findBySourcePlatformId(String sourcePlatformId) async {
    final row = await _db.findMediaBySourcePlatformId(sourcePlatformId);
    return row == null ? null : _map(row);
  }

  Future<MediaItem?> findByContentDigest(String contentDigest) async {
    final row = await _db.findMediaByContentDigest(contentDigest);
    return row == null ? null : _map(row);
  }

  Future<MediaItem?> findById(String id) async {
    final row = await _db.getMediaById(id);
    return row == null ? null : _map(row);
  }

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
        sourcePlatformId: r.sourcePlatformId,
        sourceRemovalPending: r.sourceRemovalPending,
        contentDigest: r.contentDigest,
      );

  List<MediaItem> _mapList(List<MediaItemRow> rows) =>
      rows.map(_map).toList(growable: false);
}
