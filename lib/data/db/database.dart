import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [MediaItems, Albums, AlbumMedia, AlbumGroups])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'privi'));

  /// In-memory DB for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 7;

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
          if (from < 5) {
            // v5 turns the legacy open-time repairs into an explicit migration.
            await _ensureOriginalPathColumn();
            await _ensureAlbumPinnedAtColumn();
          }
          if (from < 6) {
            await _ensureAlbumOrganizerSchema();
          }
          if (from < 7) {
            await _ensureSourceMetadataSchema();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');

          // One-release safety net for installs whose schema version was
          // advanced by an older build without applying the ALTER TABLE.
          final repairedOriginalPath = await _ensureOriginalPathColumn();
          final repairedPinnedAt = await _ensureAlbumPinnedAtColumn();
          final repairedOrganizer = await _ensureAlbumOrganizerSchema();
          final repairedSourceMetadata = await _ensureSourceMetadataSchema();
          if (repairedOriginalPath ||
              repairedPinnedAt ||
              repairedOrganizer ||
              repairedSourceMetadata) {
            debugPrint(
              'Database v7 safety repair applied: '
              'original_path=$repairedOriginalPath, pinned_at=$repairedPinnedAt, '
              'organizer=$repairedOrganizer, source_metadata=$repairedSourceMetadata',
            );
          }
          await _createPerfIndexes();
        },
      );

  Future<bool> _ensureOriginalPathColumn() async {
    final names = await _columnNames('media_items');
    if (names.contains('original_path')) return false;
    await customStatement(
      'ALTER TABLE media_items ADD COLUMN original_path TEXT NULL',
    );
    return true;
  }

  Future<bool> _ensureAlbumPinnedAtColumn() async {
    final names = await _columnNames('albums');
    if (names.contains('pinned_at')) return false;
    await customStatement(
      'ALTER TABLE albums ADD COLUMN pinned_at INTEGER NULL',
    );
    return true;
  }

  Future<bool> _ensureAlbumOrganizerSchema() async {
    var changed = false;
    final names = await _columnNames('albums');
    if (!names.contains('rating')) {
      await customStatement(
        'ALTER TABLE albums ADD COLUMN rating INTEGER NOT NULL DEFAULT 0',
      );
      changed = true;
    }
    if (!names.contains('sort_index')) {
      await customStatement(
        'ALTER TABLE albums ADD COLUMN sort_index INTEGER NULL',
      );
      changed = true;
    }
    if (!names.contains('group_id')) {
      await customStatement(
        'ALTER TABLE albums ADD COLUMN group_id TEXT NULL',
      );
      changed = true;
    }
    await customStatement(
      'CREATE TABLE IF NOT EXISTS album_groups ('
      'id TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'sort_index INTEGER NULL, '
      'PRIMARY KEY(id))',
    );
    return changed;
  }

  Future<bool> _ensureSourceMetadataSchema() async {
    var changed = false;
    final names = await _columnNames('media_items');
    if (!names.contains('source_platform_id')) {
      await customStatement(
        'ALTER TABLE media_items ADD COLUMN source_platform_id TEXT NULL',
      );
      changed = true;
    }
    if (!names.contains('source_removal_pending')) {
      await customStatement(
        'ALTER TABLE media_items '
        'ADD COLUMN source_removal_pending INTEGER NOT NULL DEFAULT 0 '
        'CHECK (source_removal_pending IN (0, 1))',
      );
      changed = true;
    }
    if (!names.contains('content_digest')) {
      await customStatement(
        'ALTER TABLE media_items ADD COLUMN content_digest TEXT NULL',
      );
      changed = true;
    }
    return changed;
  }

  Future<Set<String>> _columnNames(String table) async {
    final rows = await customSelect("PRAGMA table_info('$table')").get();
    return rows.map((row) => row.data['name']).whereType<String>().toSet();
  }

  /// Secondary indexes for active/favorites/membership/path lookups (v3).
  Future<void> _createPerfIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_items_deleted_date '
      'ON media_items (deleted_at, date_added)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_items_original_date '
      'ON media_items '
      '(deleted_at, COALESCE(date_taken, date_added) DESC, original_name ASC)',
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

  OrderingTerm get _originalMediaDateDesc => OrderingTerm.desc(
        coalesce<DateTime>([mediaItems.dateTaken, mediaItems.dateAdded]),
      );

  OrderingTerm get _originalMediaNameAsc =>
      OrderingTerm.asc(mediaItems.originalName);

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

  Future<MediaItemRow?> findMediaBySourcePlatformId(String sourcePlatformId) {
    return (select(mediaItems)
          ..where((t) => t.sourcePlatformId.equals(sourcePlatformId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MediaItemRow?> findMediaByContentDigest(String contentDigest) {
    return (select(mediaItems)
          ..where((t) => t.contentDigest.equals(contentDigest))
          ..limit(1))
        .getSingleOrNull();
  }

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

  Future<void> updateMediaSourceMetadata(
    String id, {
    String? sourcePlatformId,
    required bool sourceRemovalPending,
    String? contentDigest,
  }) {
    return (update(mediaItems)..where((t) => t.id.equals(id))).write(
      MediaItemsCompanion(
        sourcePlatformId: Value(sourcePlatformId),
        sourceRemovalPending: Value(sourceRemovalPending),
        contentDigest: Value(contentDigest),
      ),
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

  Future<List<MediaItemRow>> listRecycleBinRows() {
    return (select(mediaItems)..where((t) => t.deletedAt.isNotNull())).get();
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
          ..orderBy([
            (_) => _originalMediaDateDesc,
            (_) => _originalMediaNameAsc,
          ]))
        .watch();
  }

  Stream<List<MediaItemRow>> watchFavorites() {
    return (select(mediaItems)
          ..where(
            (t) => t.deletedAt.isNull() & t.rating.isBiggerOrEqualValue(1),
          )
          ..orderBy([
            (_) => _originalMediaDateDesc,
            (_) => _originalMediaNameAsc,
          ]))
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
      ..orderBy([
        _originalMediaDateDesc,
        _originalMediaNameAsc,
      ]);

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

  Future<List<String>> listActiveOriginalPaths() async {
    final query = selectOnly(mediaItems)
      ..addColumns([mediaItems.originalPath])
      ..where(
        mediaItems.deletedAt.isNull() & mediaItems.originalPath.isNotNull(),
      );
    final rows = await query.get();
    return [
      for (final row in rows)
        if (row.read(mediaItems.originalPath) case final path?) path,
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
          ..orderBy([
            (_) => _originalMediaDateDesc,
            (_) => _originalMediaNameAsc,
          ])
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
          ..orderBy([
            (_) => _originalMediaDateDesc,
            (_) => _originalMediaNameAsc,
          ])
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

  Future<void> moveMemberships({
    required String sourceAlbumId,
    required String targetAlbumId,
    required List<String> mediaIds,
    required DateTime movedAt,
  }) async {
    if (mediaIds.isEmpty || sourceAlbumId == targetAlbumId) return;
    await transaction(() async {
      for (final mediaId in mediaIds) {
        await into(albumMedia).insert(
          AlbumMediaCompanion.insert(
            albumId: targetAlbumId,
            mediaId: mediaId,
            addedAt: movedAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
      await (delete(albumMedia)
            ..where(
              (membership) =>
                  membership.albumId.equals(sourceAlbumId) &
                  membership.mediaId.isIn(mediaIds),
            ))
          .go();
      await (update(albums)
            ..where(
              (album) =>
                  album.id.equals(sourceAlbumId) &
                  album.coverMediaId.isIn(mediaIds),
            ))
          .write(const AlbumsCompanion(coverMediaId: Value(null)));
    });
  }

  Future<List<AlbumMediaRow>> getAllMemberships() => select(albumMedia).get();

  Future<bool> hasMembership(String albumId, String mediaId) async {
    final row = await (select(albumMedia)
          ..where(
            (membership) =>
                membership.albumId.equals(albumId) &
                membership.mediaId.equals(mediaId),
          )
          ..limit(1))
        .getSingleOrNull();
    return row != null;
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
      ..orderBy([
        _originalMediaDateDesc,
        _originalMediaNameAsc,
      ])
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

  Future<void> updateAlbumRating(String albumId, int rating) async {
    final row = await getAlbumById(albumId);
    if (row == null || row.isSystem) return;
    await (update(albums)..where((t) => t.id.equals(albumId))).write(
      AlbumsCompanion(rating: Value(rating.clamp(0, 3))),
    );
  }

  Future<void> setAlbumSortIndexes(Map<String, int> indexes) async {
    if (indexes.isEmpty) return;
    await transaction(() async {
      for (final entry in indexes.entries) {
        await (update(albums)
              ..where(
                (t) => t.id.equals(entry.key) & t.isSystem.equals(false),
              ))
            .write(AlbumsCompanion(sortIndex: Value(entry.value)));
      }
    });
  }

  Future<void> setShelfSortIndexes({
    required Map<String, int> albumIndexes,
    required Map<String, int> groupIndexes,
  }) async {
    if (albumIndexes.isEmpty && groupIndexes.isEmpty) return;
    await transaction(() async {
      for (final entry in albumIndexes.entries) {
        await (update(albums)
              ..where(
                (t) => t.id.equals(entry.key) & t.isSystem.equals(false),
              ))
            .write(AlbumsCompanion(sortIndex: Value(entry.value)));
      }
      for (final entry in groupIndexes.entries) {
        await (update(albumGroups)..where((t) => t.id.equals(entry.key))).write(
          AlbumGroupsCompanion(sortIndex: Value(entry.value)),
        );
      }
    });
  }

  Future<void> setAlbumsGroup(
    List<String> albumIds,
    String? groupId, {
    int startSortIndex = 0,
  }) async {
    if (albumIds.isEmpty) return;
    await transaction(() async {
      if (groupId != null) {
        final group = await (select(albumGroups)
              ..where((table) => table.id.equals(groupId)))
            .getSingleOrNull();
        if (group == null) {
          throw StateError('Album group does not exist: $groupId');
        }
      }
      for (var i = 0; i < albumIds.length; i++) {
        await (update(albums)
              ..where(
                (t) => t.id.equals(albumIds[i]) & t.isSystem.equals(false),
              ))
            .write(
          AlbumsCompanion(
            groupId: Value(groupId),
            sortIndex: Value(groupId == null ? null : startSortIndex + i),
          ),
        );
      }
    });
  }

  Future<void> addAlbumToGroup(String albumId, String groupId) =>
      addAlbumsToGroup([albumId], groupId);

  Future<void> addAlbumsToGroup(List<String> albumIds, String groupId) async {
    if (albumIds.isEmpty) return;
    await transaction(() async {
      final group = await (select(albumGroups)
            ..where((table) => table.id.equals(groupId)))
          .getSingleOrNull();
      if (group == null) {
        throw StateError('Album group does not exist: $groupId');
      }

      final maxIndex = albums.sortIndex.max();
      final query = selectOnly(albums)
        ..addColumns([maxIndex])
        ..where(albums.groupId.equals(groupId));
      final row = await query.getSingle();
      final startIndex = (row.read(maxIndex) ?? -1) + 1;
      for (var index = 0; index < albumIds.length; index++) {
        final albumId = albumIds[index];
        final updated = await (update(albums)
              ..where(
                (table) =>
                    table.id.equals(albumId) & table.isSystem.equals(false),
              ))
            .write(
          AlbumsCompanion(
            groupId: Value(groupId),
            sortIndex: Value(startIndex + index),
          ),
        );
        if (updated != 1) {
          throw StateError('User album does not exist: $albumId');
        }
      }
    });
  }

  Future<List<AlbumGroupRow>> getAllAlbumGroups() => (select(albumGroups)
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortIndex),
          (t) => OrderingTerm.asc(t.name),
        ]))
      .get();

  Future<void> insertAlbumGroup(AlbumGroupsCompanion row) =>
      into(albumGroups).insert(row);

  Future<void> renameAlbumGroup(String id, String name) =>
      (update(albumGroups)..where((t) => t.id.equals(id))).write(
        AlbumGroupsCompanion(name: Value(name)),
      );

  Future<void> setGroupSortIndexes(Map<String, int> indexes) async {
    if (indexes.isEmpty) return;
    await transaction(() async {
      for (final entry in indexes.entries) {
        await (update(albumGroups)..where((t) => t.id.equals(entry.key))).write(
          AlbumGroupsCompanion(sortIndex: Value(entry.value)),
        );
      }
    });
  }

  Future<void> dissolveAlbumGroup(String id) async {
    await transaction(() async {
      await (update(albums)..where((t) => t.groupId.equals(id))).write(
        const AlbumsCompanion(groupId: Value(null), sortIndex: Value(null)),
      );
      await (delete(albumGroups)..where((t) => t.id.equals(id))).go();
    });
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
      ..orderBy([
        _originalMediaDateDesc,
        _originalMediaNameAsc,
      ]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(mediaItems)).toList(growable: false);
  }

  Future<List<MediaItemRow>> listActiveMedia() {
    return (select(mediaItems)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (_) => _originalMediaDateDesc,
            (_) => _originalMediaNameAsc,
          ]))
        .get();
  }

  Future<List<MediaItemRow>> listFavorites() {
    return (select(mediaItems)
          ..where(
            (t) => t.deletedAt.isNull() & t.rating.isBiggerOrEqualValue(1),
          )
          ..orderBy([
            (_) => _originalMediaDateDesc,
            (_) => _originalMediaNameAsc,
          ]))
        .get();
  }

  Future<void> deleteUserAlbum(String id) async {
    await transaction(() async {
      await (delete(albumMedia)..where((t) => t.albumId.equals(id))).go();
      await (delete(albums)
            ..where((t) => t.id.equals(id) & t.isSystem.equals(false)))
          .go();
    });
  }

  Future<List<AlbumRow>> getUserAlbums() {
    return (select(albums)..where((t) => t.isSystem.equals(false))).get();
  }
}
