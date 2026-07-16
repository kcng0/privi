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
  Stream<List<AlbumView>> watchAlbumViewsReactive() {
    return Stream.multi((controller) {
      var closed = false;
      Timer? debounce;

      Future<void> emitNow() async {
        if (closed) return;
        try {
          controller.add(await _buildViews());
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

  Future<List<AlbumView>> _buildViews() async {
    final albums = await _db.getAllAlbums();
    final views = await Future.wait(
      albums.map((row) async {
        final album = _mapAlbum(row);
        final results = await Future.wait<Object?>([
          _countFor(album),
          _coverFor(album, row.coverMediaId),
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
      return 100;
    }

    views.sort((a, b) {
      final ra = rank(a.album);
      final rb = rank(b.album);
      if (ra != rb) return ra.compareTo(rb);
      return a.album.name.toLowerCase().compareTo(b.album.name.toLowerCase());
    });
    return views;
  }

  Future<int> _countFor(Album album) {
    switch (album.systemKind) {
      case SystemAlbumKind.all:
        return _db.countActiveMedia();
      case SystemAlbumKind.favorites:
        return _db.countFavorites();
      case SystemAlbumKind.recycle:
        return _db.countRecycle();
      case null:
        return _db.countMembership(album.id);
    }
  }

  Future<MediaItem?> _coverFor(Album album, String? coverMediaId) async {
    MediaItemRow? row;
    if (coverMediaId != null) {
      row = await _db.getMediaById(coverMediaId);
    }
    row ??= switch (album.systemKind) {
      SystemAlbumKind.all => await _db.latestActiveMedia(),
      SystemAlbumKind.favorites => await _db.latestFavorite(),
      SystemAlbumKind.recycle => await _db.latestRecycle(),
      null => await _db.latestInUserAlbum(album.id),
    };
    return row == null ? null : _mapMedia(row);
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

  Future<void> addMediaToUserAlbum(String albumId, String mediaId) =>
      _db.addMembership(albumId, mediaId, DateTime.now().toUtc());

  Future<List<Album>> listUserAlbums() async {
    final rows = await _db.getUserAlbums();
    return rows.map(_mapAlbum).toList();
  }

  Future<void> deleteUserAlbum(String id) => _db.deleteUserAlbum(id);

  Future<Album?> getById(String id) async {
    final row = await _db.getAlbumById(id);
    return row == null ? null : _mapAlbum(row);
  }

  Album _mapAlbum(AlbumRow r) => Album(
        id: r.id,
        name: r.name,
        isSystem: r.isSystem,
        coverMediaId: r.coverMediaId,
        createdAt: r.createdAt,
        systemKind: SystemAlbumKind.fromStorage(r.systemKind),
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
