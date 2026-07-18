import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../../domain/models/album.dart';
import '../../domain/models/album_view.dart';
import '../../domain/models/media_item.dart';
import '../db/database.dart';

/// User albums + Home [AlbumView] streams.
class AlbumRepository {
  AlbumRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  /// Re-emit when albums OR media (counts/covers) change.
  ///
  /// Uses lightweight table-update notifications (not full media row streams)
  /// and debounces rapid multi-select writes.
  ///
  /// [isVideo] filters home mosaic counts/covers to match the shared
  /// photo XOR video mode (same as Visible). Null = all kinds.
  Stream<List<AlbumView>> watchAlbumViewsReactive({bool? isVideo}) {
    return Stream.multi((controller) {
      var closed = false;
      Timer? debounce;

      Future<void> emitNow() async {
        if (closed) return;
        try {
          final views = await _buildViews(isVideo: isVideo);
          if (closed) return;
          controller.add(views);
        } catch (e, st) {
          if (!closed) controller.addError(e, st);
        }
      }

      void schedule() {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 75), emitNow);
      }

      final sub = _db
          .tableUpdates(
            TableUpdateQuery.onAllTables([
              _db.mediaItems,
              _db.albumMedia,
              _db.albums,
            ]),
          )
          .listen((_) => schedule());

      controller.onCancel = () async {
        closed = true;
        debounce?.cancel();
        await sub.cancel();
      };

      emitNow();
    });
  }

  Future<List<AlbumView>> _buildViews({bool? isVideo}) async {
    final albums = await _db.getAllAlbums();
    final views = await Future.wait(
      albums.map((row) async {
        final album = _mapAlbum(row);
        final results = await Future.wait<Object?>([
          _countFor(album, isVideo: isVideo),
          _coverFor(album, row.coverMediaId, isVideo: isVideo),
        ]);
        return AlbumView(
          album: album,
          count: results[0] as int,
          cover: results[1] as MediaItem?,
        );
      }),
    );

    int rank(Album a) {
      if (a.systemKind == SystemAlbumKind.all) return 0;
      if (a.systemKind == SystemAlbumKind.favorites) return 1;
      if (a.systemKind == SystemAlbumKind.recycle) return 1000;
      // Pinned user albums sit above other user albums.
      if (a.isPinned) return 50;
      return 100;
    }

    views.sort((a, b) {
      final ra = rank(a.album);
      final rb = rank(b.album);
      if (ra != rb) return ra.compareTo(rb);
      // Among pinned: most recently pinned first.
      if (a.album.isPinned && b.album.isPinned) {
        final pa = a.album.pinnedAt!;
        final pb = b.album.pinnedAt!;
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      }
      return a.album.name.toLowerCase().compareTo(b.album.name.toLowerCase());
    });
    return views;
  }

  Future<int> _countFor(Album album, {bool? isVideo}) {
    switch (album.systemKind) {
      case SystemAlbumKind.all:
        return _db.countActiveMedia(isVideo: isVideo);
      case SystemAlbumKind.favorites:
        return _db.countFavorites(isVideo: isVideo);
      case SystemAlbumKind.recycle:
        return _db.countRecycle(isVideo: isVideo);
      case null:
        return _db.countMembership(album.id, isVideo: isVideo);
    }
  }

  Future<MediaItem?> _coverFor(
    Album album,
    String? coverMediaId, {
    bool? isVideo,
  }) async {
    MediaItemRow? row;
    if (coverMediaId != null) {
      final pinned = await _db.getMediaById(coverMediaId);
      final valid = pinned != null && await _isAlbumMember(album, pinned);
      if (!valid) {
        await _db.setAlbumCover(album.id, null);
      } else if (isVideo == null || pinned.isVideo == isVideo) {
        row = pinned;
      }
    }
    row ??= switch (album.systemKind) {
      SystemAlbumKind.all => await _db.latestActiveMedia(isVideo: isVideo),
      SystemAlbumKind.favorites => await _db.latestFavorite(isVideo: isVideo),
      SystemAlbumKind.recycle => await _db.latestRecycle(isVideo: isVideo),
      null => await _db.latestInUserAlbum(album.id, isVideo: isVideo),
    };
    return row == null ? null : _mapMedia(row);
  }

  Future<bool> _isAlbumMember(Album album, MediaItemRow media) {
    return switch (album.systemKind) {
      SystemAlbumKind.all => Future.value(media.deletedAt == null),
      SystemAlbumKind.favorites =>
        Future.value(media.deletedAt == null && media.rating >= 1),
      SystemAlbumKind.recycle => Future.value(media.deletedAt != null),
      null => media.deletedAt != null
          ? Future.value(false)
          : _db.hasMembership(album.id, media.id),
    };
  }

  Future<Album> createUserAlbum(String name) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.insertAlbum(
      AlbumsCompanion.insert(
        id: id,
        name: name.trim(),
        isSystem: false,
        createdAt: now,
      ),
    );
    return Album(id: id, name: name.trim(), isSystem: false, createdAt: now);
  }

  Future<Album> insertWithId({
    required String id,
    required String name,
    required DateTime createdAt,
    DateTime? pinnedAt,
    String? coverMediaId,
  }) async {
    final trimmed = name.trim();
    await _db.insertAlbum(
      AlbumsCompanion.insert(
        id: id,
        name: trimmed,
        isSystem: false,
        createdAt: createdAt,
        pinnedAt: Value(pinnedAt),
        coverMediaId: Value(coverMediaId),
      ),
    );
    return Album(
      id: id,
      name: trimmed,
      isSystem: false,
      createdAt: createdAt,
      pinnedAt: pinnedAt,
      coverMediaId: coverMediaId,
    );
  }

  /// Mirror Visible folder structure: reuse album named [name] or create it.
  /// Case-insensitive match on existing user albums.
  Future<Album> getOrCreateUserAlbumByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return getOrCreateUserAlbumByName('Imported');
    }
    final existing = await listUserAlbums();
    for (final a in existing) {
      if (a.name.toLowerCase() == trimmed.toLowerCase()) return a;
    }
    return createUserAlbum(trimmed);
  }

  Future<void> rename(String id, String name) =>
      _db.renameAlbum(id, name.trim());

  Future<void> setCover(String albumId, String mediaId) =>
      _db.setAlbumCover(albumId, mediaId);

  Future<void> setPinned(String albumId, {required bool pinned}) =>
      _db.setAlbumPinnedAt(
        albumId,
        pinned ? DateTime.now().toUtc() : null,
      );

  Future<void> addMediaToUserAlbum(String albumId, String mediaId) =>
      _db.addMembership(albumId, mediaId, DateTime.now().toUtc());

  Future<void> moveMediaToUserAlbum({
    required String sourceAlbumId,
    required String targetAlbumId,
    required List<String> mediaIds,
  }) {
    return _db.moveMemberships(
      sourceAlbumId: sourceAlbumId,
      targetAlbumId: targetAlbumId,
      mediaIds: mediaIds,
      movedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> restoreMembership(
    String albumId,
    String mediaId,
    DateTime addedAt,
  ) =>
      _db.addMembership(albumId, mediaId, addedAt);

  Future<List<Album>> listUserAlbums() async {
    final rows = await _db.getUserAlbums();
    return rows.map(_mapAlbum).toList();
  }

  Future<void> deleteUserAlbum(String id) => _db.deleteUserAlbum(id);

  Future<Album?> getById(String id) async {
    final row = await _db.getAlbumById(id);
    return row == null ? null : _mapAlbum(row);
  }

  /// Snapshot of media currently in [albumId] (active only).
  Future<List<MediaItem>> listMediaForAlbum(String albumId) async {
    final rows = switch (albumId) {
      SystemAlbumIds.all => await _db.listActiveMedia(),
      SystemAlbumIds.favorites => await _db.listFavorites(),
      SystemAlbumIds.recycle => const <MediaItemRow>[],
      _ => await _db.listInUserAlbum(albumId),
    };
    return rows.map(_mapMedia).toList(growable: false);
  }

  Album _mapAlbum(AlbumRow r) => Album(
        id: r.id,
        name: r.name,
        isSystem: r.isSystem,
        coverMediaId: r.coverMediaId,
        createdAt: r.createdAt,
        systemKind: SystemAlbumKind.fromStorage(r.systemKind),
        pinnedAt: r.pinnedAt,
      );

  MediaItem _mapMedia(MediaItemRow r) => MediaItem(
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
}
