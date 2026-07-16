import 'package:drift/drift.dart';

/// See docs/03-architecture/data-model.md.
@DataClassName('MediaItemRow')
class MediaItems extends Table {
  TextColumn get id => text()();
  TextColumn get privatePath => text()();

  /// Absolute path before hide (for unhide restore). Null for legacy rows.
  TextColumn get originalPath => text().nullable()();
  TextColumn get originalName => text()();
  TextColumn get mimeType => text()();
  BoolColumn get isVideo => boolean()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get rating => integer().withDefault(const Constant(0))();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get dateTaken => dateTime().nullable()();
  IntColumn get sizeBytes => integer()();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AlbumRow')
class Albums extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isSystem => boolean()();
  TextColumn get coverMediaId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get systemKind => text().nullable()();

  /// When set, album is pinned to the top of the Invisible mosaic.
  DateTimeColumn get pinnedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Explicit membership for **user albums only**.
@DataClassName('AlbumMediaRow')
class AlbumMedia extends Table {
  TextColumn get albumId => text().references(Albums, #id)();
  TextColumn get mediaId => text().references(MediaItems, #id)();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {albumId, mediaId};
}
