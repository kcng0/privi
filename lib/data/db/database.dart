import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [MediaItems, Albums, AlbumMedia])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'privi'));

  /// In-memory DB for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedSystemAlbums();
          await _createPerfIndexes();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _ensureOriginalPathColumn();
          }
          if (from < 3) {
            await _createPerfIndexes();
          }
          if (from < 4) {
            await _ensureAlbumPinnedAtColumn();
          }
        },
        beforeOpen: (details) async {
          // Repair installs where schemaVersion advanced without the column.
          await _ensureOriginalPathColumn();
          await _ensureAlbumPinnedAtColumn();
          // Idempotent: covers installs that skipped onUpgrade edge cases.
          await _createPerfIndexes();
        },
      );

  Future<void> _ensureOriginalPathColumn() async {
    try {
      final rows = await customSelect(
        "PRAGMA table_info('media_items')",
      ).get();
      final names = rows.map((r) => r.data['name'] as String?).toSet();
      if (!names.contains('original_path')) {
        await customStatement(
          'ALTER TABLE media_items ADD COLUMN original_path TEXT NULL',
        );
      }
    } catch (e) {
      // Best-effort; insert may still fail and surface in UI.
      try {
        await customStatement(
          'ALTER TABLE media_items ADD COLUMN original_path TEXT NULL',
        );
      } catch (_) {}
    }
  }

  Future<void> _ensureAlbumPinnedAtColumn() async {
    try {
      final rows = await customSelect("PRAGMA table_info('albums')").get();
      final names = rows.map((r) => r.data['name'] as String?).toSet();
      if (!names.contains('pinned_at')) {
        await customStatement(
          'ALTER TABLE albums ADD COLUMN pinned_at INTEGER NULL',
        );
      }
    } catch (_) {
      try {
        await customStatement(
          'ALTER TABLE albums ADD COLUMN pinned_at INTEGER NULL',
        );
      } catch (_) {}
    }
  }

  /// Secondary indexes for active/favorites/membership/path lookups (v3).
  Future<void> _createPerfIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_items_deleted_date '
      'ON media_items (deleted_at, date_added)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_items_rating_active '
      'ON media_items (rating) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_items_private_path '
      'ON media_items (private_path)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_album_media_album_id '
      'ON album_media (album_id)',
    );
  }

  Future<void> seedSystemAlbums() async {
    final now = DateTime.now().toUtc();
    await into(albums).insert(
      AlbumsCompanion.insert(
        id: SystemAlbumIds.all,
        name: 'All Media',
        isSystem: true,
        createdAt: now,
        systemKind: Value(SystemAlbumKind.all.storageValue),
      ),
    );
    await into(albums).insert(
      AlbumsCompanion.insert(
        id: SystemAlbumIds.favorites,
        name: 'Favorites',
        isSystem: true,
        createdAt: now,
        systemKind: Value(SystemAlbumKind.favorites.storageValue),
      ),
    );
    await into(albums).insert(
      AlbumsCompanion.insert(
        id: SystemAlbumIds.recycle,
        name: 'Recycle Bin',
        isSystem: true,
        createdAt: now,
        systemKind: Value(SystemAlbumKind.recycle.storageValue),
      ),
    );
  }

  // ── Media queries ──────────────────────────────────────────────

  Future<void> insertMedia(MediaItemsCompanion row) =>
      into(mediaItems).insert(row);

  /// Insert many media rows + optional album memberships in one transaction.
  Future<void> insertMediaBatch(
    List<MediaItemsCompanion> rows, {
    Map<String, String>? membershipByMediaId,
  }) async {
    if (rows.isEmpty) return;
    final now = DateTime.now().toUtc();
    await transaction(() async {
      for (final row in rows) {
        await into(mediaItems).insert(row);
        final id = row.id.present ? row.id.value : null;
        if (id == null) continue;
        final albumId = membershipByMediaId?[id];
        if (albumId == null || albumId.isEmpty) continue;
        await into(albumMedia).insert(
          AlbumMediaCompanion.insert(
            albumId: albumId,
            mediaId: id,
            addedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  Future<MediaItemRow?> getMediaById(String id) =>
      (select(mediaItems)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> updateMediaRating(String id, int rating) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(rating: Value(rating.clamp(0, 3))),
    );
  }

  Future<void> updateMediaThumbnail(String id, String? thumbnailPath) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(thumbnailPath: Value(thumbnailPath)),
    );
  }

  /// Repair capture/sort timestamps without touching the media file.
  Future<void> updateMediaDates(
    String id, {
    required DateTime dateTaken,
    required DateTime dateAdded,
  }) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(
        dateTaken: Value(dateTaken),
        dateAdded: Value(dateAdded),
      ),
    );
  }

  Future<List<MediaItemRow>> listActiveMediaRows() {
    return (select(mediaItems)..where((t) => t.deletedAt.isNull())).get();
  }

  Future<void> updateMediaRatings(List<String> ids, int rating) async {
    if (ids.isEmpty) return;
    final r = rating.clamp(0, 3);
    await (update(mediaItems)..where((t) => t.id.isIn(ids))).write(
      MediaItemsCompanion(rating: Value(r)),
    );
  }

  Future<void> softDeleteMedia(String id, DateTime at) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(deletedAt: Value(at)),
    );
  }

  Future<void> softDeleteMediaMany(List<String> ids, DateTime at) async {
    if (ids.isEmpty) return;
    await (update(mediaItems)..where((t) => t.id.isIn(ids))).write(
      MediaItemsCompanion(deletedAt: Value(at)),
    );
  }

  Future<void> restoreMedia(String id) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      const MediaItemsCompanion(deletedAt: Value(null)),
    );
  }

  Future<void> restoreMediaMany(List<String> ids) async {
    if (ids.isEmpty) return;
    await (update(mediaItems)..where((t) => t.id.isIn(ids))).write(
      const MediaItemsCompanion(deletedAt: Value(null)),
    );
  }

  Future<void> hardDeleteMedia(String id) async {
    await (delete(albumMedia)..where((t) => t.mediaId.equals(id))).go();
    await (delete(mediaItems)..where((t) => t.id.equals(id))).go();
  }

  Future<void> hardDeleteMediaMany(List<String> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      await (delete(albumMedia)..where((t) => t.mediaId.isIn(ids))).go();
      await (delete(mediaItems)..where((t) => t.id.isIn(ids))).go();
    });
  }

  Future<List<MediaItemRow>> getMediaByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    return (select(mediaItems)..where((t) => t.id.isIn(ids))).get();
  }

  Stream<List<MediaItemRow>> watchActiveMedia() {
    return (select(mediaItems)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
        .watch();
  }

  Stream<List<MediaItemRow>> watchFavorites() {
    return (select(mediaItems)
          ..where(
            (t) => t.deletedAt.isNull() & t.rating.isBiggerOrEqualValue(1),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
        .watch();
  }

  Stream<List<MediaItemRow>> watchRecycleBin() {
    return (select(mediaItems)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  Stream<List<MediaItemRow>> watchInUserAlbum(String albumId) {
    final query = select(mediaItems).join([
      innerJoin(
        albumMedia,
        albumMedia.mediaId.equalsExp(mediaItems.id),
      ),
    ])
      ..where(
        albumMedia.albumId.equals(albumId) & mediaItems.deletedAt.isNull(),
      )
      ..orderBy([OrderingTerm.desc(mediaItems.dateAdded)]);

    return query.watch().map(
          (rows) => rows.map((r) => r.readTable(mediaItems)).toList(),
        );
  }

  /// [isVideo] null = all kinds; true/false = photos XOR videos (home filter).
  Future<int> countActiveMedia({bool? isVideo}) async {
    final c = countAll();
    var pred = mediaItems.deletedAt.isNull();
    if (isVideo != null) {
      pred = pred & mediaItems.isVideo.equals(isVideo);
    }
    final q = selectOnly(mediaItems)
      ..addColumns([c])
      ..where(pred);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  /// All non-deleted private paths (for Visible count hydration / orphan scan).
  Future<List<String>> listActivePrivatePaths() async {
    final q = selectOnly(mediaItems)
      ..addColumns([mediaItems.privatePath])
      ..where(mediaItems.deletedAt.isNull());
    final rows = await q.get();
    return [
      for (final r in rows) r.read(mediaItems.privatePath)!,
    ];
  }

  /// Sum of sizeBytes for active + recycle (vault storage estimate).
  Future<int> sumMediaBytes() async {
    final total = mediaItems.sizeBytes.sum();
    final q = selectOnly(mediaItems)..addColumns([total]);
    final row = await q.getSingle();
    return row.read(total) ?? 0;
  }

  Future<bool> existsByPrivatePath(String path) async {
    final row = await (select(mediaItems)
          ..where((t) => t.privatePath.equals(path))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<MediaItemRow?> findByPrivatePath(String path) {
    return (select(mediaItems)
          ..where((t) => t.privatePath.equals(path))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> countFavorites({bool? isVideo}) async {
    final c = countAll();
    var pred = mediaItems.deletedAt.isNull() &
        mediaItems.rating.isBiggerOrEqualValue(1);
    if (isVideo != null) {
      pred = pred & mediaItems.isVideo.equals(isVideo);
    }
    final q = selectOnly(mediaItems)
      ..addColumns([c])
      ..where(pred);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<int> countRecycle({bool? isVideo}) async {
    final c = countAll();
    var pred = mediaItems.deletedAt.isNotNull();
    if (isVideo != null) {
      pred = pred & mediaItems.isVideo.equals(isVideo);
    }
    final q = selectOnly(mediaItems)
      ..addColumns([c])
      ..where(pred);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<MediaItemRow?> latestActiveMedia({bool? isVideo}) {
    return (select(mediaItems)
          ..where((t) {
            var p = t.deletedAt.isNull();
            if (isVideo != null) p = p & t.isVideo.equals(isVideo);
            return p;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MediaItemRow?> latestFavorite({bool? isVideo}) {
    return (select(mediaItems)
          ..where((t) {
            var p = t.deletedAt.isNull() & t.rating.isBiggerOrEqualValue(1);
            if (isVideo != null) p = p & t.isVideo.equals(isVideo);
            return p;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MediaItemRow?> latestRecycle({bool? isVideo}) {
    return (select(mediaItems)
          ..where((t) {
            var p = t.deletedAt.isNotNull();
            if (isVideo != null) p = p & t.isVideo.equals(isVideo);
            return p;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  // ── Album queries ──────────────────────────────────────────────

  Future<List<AlbumRow>> getAllAlbums() => select(albums).get();

  Stream<List<AlbumRow>> watchAlbums() => select(albums).watch();

  Future<AlbumRow?> getAlbumById(String id) =>
      (select(albums)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertAlbum(AlbumsCompanion row) => into(albums).insert(row);

  Future<void> addMembership(String albumId, String mediaId, DateTime at) {
    return into(albumMedia).insert(
      AlbumMediaCompanion.insert(
        albumId: albumId,
        mediaId: mediaId,
        addedAt: at,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<int> countMembership(String albumId, {bool? isVideo}) async {
    final c = countAll();
    var pred =
        albumMedia.albumId.equals(albumId) & mediaItems.deletedAt.isNull();
    if (isVideo != null) {
      pred = pred & mediaItems.isVideo.equals(isVideo);
    }
    final q = selectOnly(albumMedia).join([
      innerJoin(
        mediaItems,
        mediaItems.id.equalsExp(albumMedia.mediaId),
      ),
    ])
      ..addColumns([c])
      ..where(pred);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<MediaItemRow?> latestInUserAlbum(
    String albumId, {
    bool? isVideo,
  }) async {
    var pred =
        albumMedia.albumId.equals(albumId) & mediaItems.deletedAt.isNull();
    if (isVideo != null) {
      pred = pred & mediaItems.isVideo.equals(isVideo);
    }
    final query = select(mediaItems).join([
      innerJoin(
        albumMedia,
        albumMedia.mediaId.equalsExp(mediaItems.id),
      ),
    ])
      ..where(pred)
      ..orderBy([OrderingTerm.desc(mediaItems.dateAdded)])
      ..limit(1);
    final rows = await query.get();
    if (rows.isEmpty) return null;
    return rows.first.readTable(mediaItems);
  }

  Future<void> renameAlbum(String id, String name) {
    return (update(albums)..where((t) => t.id.equals(id))).write(
      AlbumsCompanion(name: Value(name)),
    );
  }

  Future<void> setAlbumCover(String albumId, String? mediaId) {
    return (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(coverMediaId: Value(mediaId)),
    );
  }

  /// Pin / unpin user albums. [pinnedAt] null clears the pin.
  Future<void> setAlbumPinnedAt(String albumId, DateTime? pinnedAt) {
    return (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(pinnedAt: Value(pinnedAt)),
    );
  }

  /// One-shot list of active media in a user album (for shuffle / restore).
  Future<List<MediaItemRow>> listInUserAlbum(String albumId) async {
    final query = select(mediaItems).join([
      innerJoin(
        albumMedia,
        albumMedia.mediaId.equalsExp(mediaItems.id),
      ),
    ])
      ..where(
        albumMedia.albumId.equals(albumId) & mediaItems.deletedAt.isNull(),
      )
      ..orderBy([OrderingTerm.desc(mediaItems.dateAdded)]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(mediaItems)).toList(growable: false);
  }

  Future<List<MediaItemRow>> listActiveMedia() {
    return (select(mediaItems)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
        .get();
  }

  Future<List<MediaItemRow>> listFavorites() {
    return (select(mediaItems)
          ..where(
            (t) => t.deletedAt.isNull() & t.rating.isBiggerOrEqualValue(1),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
        .get();
  }

  Future<void> deleteUserAlbum(String id) async {
    await (delete(albumMedia)..where((t) => t.albumId.equals(id))).go();
    await (delete(albums)
          ..where((t) => t.id.equals(id) & t.isSystem.equals(false)))
        .go();
  }

  Future<List<AlbumRow>> getUserAlbums() {
    return (select(albums)..where((t) => t.isSystem.equals(false))).get();
  }
}
