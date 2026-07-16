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
      : super(executor ?? driftDatabase(name: 'privateheart'));

  /// In-memory DB for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedSystemAlbums();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _ensureOriginalPathColumn();
          }
        },
        beforeOpen: (details) async {
          // Repair installs where schemaVersion advanced without the column.
          await _ensureOriginalPathColumn();
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

  Future<MediaItemRow?> getMediaById(String id) =>
      (select(mediaItems)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> updateMediaRating(String id, int rating) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(rating: Value(rating.clamp(0, 3))),
    );
  }

  Future<void> softDeleteMedia(String id, DateTime at) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(deletedAt: Value(at)),
    );
  }

  Future<void> restoreMedia(String id) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      const MediaItemsCompanion(deletedAt: Value(null)),
    );
  }

  Future<void> hardDeleteMedia(String id) async {
    await (delete(albumMedia)..where((t) => t.mediaId.equals(id))).go();
    await (delete(mediaItems)..where((t) => t.id.equals(id))).go();
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

  Future<int> countActiveMedia() async {
    final c = countAll();
    final q = selectOnly(mediaItems)
      ..addColumns([c])
      ..where(mediaItems.deletedAt.isNull());
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  /// All non-deleted private paths (for Visible count hydration / orphan scan).
  Future<List<String>> listActivePrivatePaths() async {
    final rows =
        await (select(mediaItems)..where((t) => t.deletedAt.isNull())).get();
    return rows.map((r) => r.privatePath).toList(growable: false);
  }

  /// Sum of sizeBytes for active + recycle (vault storage estimate).
  Future<int> sumMediaBytes() async {
    final rows = await select(mediaItems).get();
    var total = 0;
    for (final r in rows) {
      total += r.sizeBytes;
    }
    return total;
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

  Future<int> countFavorites() async {
    final c = countAll();
    final q = selectOnly(mediaItems)
      ..addColumns([c])
      ..where(
        mediaItems.deletedAt.isNull() &
            mediaItems.rating.isBiggerOrEqualValue(1),
      );
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<int> countRecycle() async {
    final c = countAll();
    final q = selectOnly(mediaItems)
      ..addColumns([c])
      ..where(mediaItems.deletedAt.isNotNull());
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<MediaItemRow?> latestActiveMedia() {
    return (select(mediaItems)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MediaItemRow?> latestFavorite() {
    return (select(mediaItems)
          ..where(
            (t) => t.deletedAt.isNull() & t.rating.isBiggerOrEqualValue(1),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MediaItemRow?> latestRecycle() {
    return (select(mediaItems)
          ..where((t) => t.deletedAt.isNotNull())
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

  Future<int> countMembership(String albumId) async {
    final rows = await (select(albumMedia).join([
      innerJoin(
        mediaItems,
        mediaItems.id.equalsExp(albumMedia.mediaId),
      ),
    ])
          ..where(
            albumMedia.albumId.equals(albumId) & mediaItems.deletedAt.isNull(),
          ))
        .get();
    return rows.length;
  }

  Future<MediaItemRow?> latestInUserAlbum(String albumId) async {
    final query = select(mediaItems).join([
      innerJoin(
        albumMedia,
        albumMedia.mediaId.equalsExp(mediaItems.id),
      ),
    ])
      ..where(
        albumMedia.albumId.equals(albumId) & mediaItems.deletedAt.isNull(),
      )
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
