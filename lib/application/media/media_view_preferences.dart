import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';

enum MediaViewSource { visibleFolder, vaultAlbum }

@immutable
class MediaViewScope {
  const MediaViewScope._(this.source, this.folderId);

  factory MediaViewScope.visibleFolder(String folderId) =>
      MediaViewScope._(MediaViewSource.visibleFolder, folderId);

  factory MediaViewScope.vaultAlbum(String albumId) =>
      MediaViewScope._(MediaViewSource.vaultAlbum, albumId);

  final MediaViewSource source;
  final String folderId;

  String get storageIdentity => '${source.name}:$folderId';

  @override
  bool operator ==(Object other) =>
      other is MediaViewScope &&
      other.source == source &&
      other.folderId == folderId;

  @override
  int get hashCode => Object.hash(source, folderId);
}

@immutable
class MediaViewPreferences {
  MediaViewPreferences({
    required List<MediaSort> sorts,
    required this.multiSortEnabled,
    required this.ratingFilter,
    required Set<int> heartLevels,
    required this.gridColumns,
    required this.gridColumnsOverride,
  })  : sorts = List.unmodifiable(sorts),
        heartLevels = Set.unmodifiable(heartLevels);

  factory MediaViewPreferences.defaults({required int gridColumns}) {
    return MediaViewPreferences(
      sorts: const [MediaSort.dateAddedDesc],
      multiSortEnabled: false,
      ratingFilter: RatingFilter.all,
      heartLevels: const {},
      gridColumns: gridColumns,
      gridColumnsOverride: null,
    );
  }

  final List<MediaSort> sorts;
  final bool multiSortEnabled;
  final RatingFilter ratingFilter;
  final Set<int> heartLevels;
  final int gridColumns;
  final int? gridColumnsOverride;

  MediaViewPreferences copyWith({
    List<MediaSort>? sorts,
    bool? multiSortEnabled,
    RatingFilter? ratingFilter,
    Set<int>? heartLevels,
    int? gridColumns,
    int? gridColumnsOverride,
  }) {
    return MediaViewPreferences(
      sorts: sorts ?? this.sorts,
      multiSortEnabled: multiSortEnabled ?? this.multiSortEnabled,
      ratingFilter: ratingFilter ?? this.ratingFilter,
      heartLevels: heartLevels ?? this.heartLevels,
      gridColumns: gridColumns ?? this.gridColumns,
      gridColumnsOverride: gridColumnsOverride ?? this.gridColumnsOverride,
    );
  }
}

class MediaViewPreferencesController extends Notifier<MediaViewPreferences> {
  MediaViewPreferencesController(this.scope);

  static const _storagePrefix = 'media_view_preferences_v1.';

  final MediaViewScope scope;
  Future<void> _pendingWrite = Future.value();

  String get _storageKey {
    final encoded = base64Url.encode(utf8.encode(scope.storageIdentity));
    return '$_storagePrefix$encoded';
  }

  @override
  MediaViewPreferences build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final defaultColumns = ref.watch(
      settingsControllerProvider.select((settings) => settings.gridColumns),
    );
    final raw = preferences.getString(_storageKey);
    if (raw == null) {
      return MediaViewPreferences.defaults(gridColumns: defaultColumns);
    }
    return _decode(raw, defaultGridColumns: defaultColumns);
  }

  Future<void> setSorting(
    List<MediaSort> sorts, {
    required bool multiSortEnabled,
  }) {
    _validateSorts(sorts, multiSortEnabled: multiSortEnabled);
    return _commit(
      state.copyWith(
        sorts: sorts,
        multiSortEnabled: multiSortEnabled,
      ),
    );
  }

  Future<void> setRatingFilter(RatingFilter filter) {
    final levels = switch (filter) {
      RatingFilter.hearts1 => const {1},
      RatingFilter.hearts2 => const {2},
      RatingFilter.hearts3 => const {3},
      _ => const <int>{},
    };
    return _commit(
      state.copyWith(ratingFilter: filter, heartLevels: levels),
    );
  }

  Future<void> setHeartLevels(Set<int> levels) {
    if (levels.any((level) => level < 1 || level > 3)) {
      throw RangeError('Heart levels must be between 1 and 3: $levels');
    }
    return _commit(
      state.copyWith(
        ratingFilter:
            levels.isEmpty ? RatingFilter.all : RatingFilter.favorites,
        heartLevels: levels,
      ),
    );
  }

  Future<void> setGridColumns(int columns) {
    if (columns < 2 || columns > 5) {
      throw RangeError.range(columns, 2, 5, 'columns');
    }
    return _commit(
      state.copyWith(
        gridColumns: columns,
        gridColumnsOverride: columns,
      ),
    );
  }

  Future<void> _commit(MediaViewPreferences next) {
    state = next;
    final encoded = _encode(next);
    final preferences = ref.read(sharedPreferencesProvider);
    _pendingWrite = _pendingWrite.then((_) async {
      final saved = await preferences.setString(_storageKey, encoded);
      if (!saved) {
        throw StateError('Could not persist media view preferences');
      }
    });
    return _pendingWrite;
  }

  static String _encode(MediaViewPreferences value) {
    return jsonEncode({
      'sorts': value.sorts.map((sort) => sort.name).toList(growable: false),
      'multiSortEnabled': value.multiSortEnabled,
      'ratingFilter': value.ratingFilter.name,
      'heartLevels': value.heartLevels.toList()..sort(),
      'gridColumns': value.gridColumnsOverride,
    });
  }

  static MediaViewPreferences _decode(
    String raw, {
    required int defaultGridColumns,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Media view preferences must be an object');
    }

    final sortsRaw = decoded['sorts'];
    final multiSortEnabled = decoded['multiSortEnabled'];
    final ratingRaw = decoded['ratingFilter'];
    final heartLevelsRaw = decoded['heartLevels'];
    final gridColumnsOverride = decoded['gridColumns'];
    if (sortsRaw is! List<dynamic> ||
        multiSortEnabled is! bool ||
        ratingRaw is! String ||
        heartLevelsRaw is! List<dynamic> ||
        (gridColumnsOverride != null && gridColumnsOverride is! int)) {
      throw const FormatException('Invalid media view preference fields');
    }

    final sorts = sortsRaw.map((value) {
      if (value is! String) {
        throw const FormatException('Sort names must be strings');
      }
      return MediaSort.values.byName(value);
    }).toList(growable: false);
    _validateSorts(sorts, multiSortEnabled: multiSortEnabled);

    final ratingFilter = RatingFilter.values.byName(ratingRaw);
    final heartLevels = heartLevelsRaw.map((value) {
      if (value is! int || value < 1 || value > 3) {
        throw const FormatException('Heart levels must be 1, 2, or 3');
      }
      return value;
    }).toSet();
    if (gridColumnsOverride is int &&
        (gridColumnsOverride < 2 || gridColumnsOverride > 5)) {
      throw const FormatException('Grid columns must be between 2 and 5');
    }

    return MediaViewPreferences(
      sorts: sorts,
      multiSortEnabled: multiSortEnabled,
      ratingFilter: ratingFilter,
      heartLevels: heartLevels,
      gridColumns:
          gridColumnsOverride is int ? gridColumnsOverride : defaultGridColumns,
      gridColumnsOverride:
          gridColumnsOverride is int ? gridColumnsOverride : null,
    );
  }

  static void _validateSorts(
    List<MediaSort> sorts, {
    required bool multiSortEnabled,
  }) {
    if (sorts.isEmpty) {
      throw const FormatException('At least one sort criterion is required');
    }
    if (!multiSortEnabled && sorts.length != 1) {
      throw const FormatException('Single-sort mode requires one criterion');
    }
    final families = sorts.map(_sortFamily).toSet();
    if (families.length != sorts.length) {
      throw const FormatException('Sort families must be unique');
    }
  }

  static int _sortFamily(MediaSort sort) => switch (sort) {
        MediaSort.dateAddedDesc || MediaSort.dateAddedAsc => 0,
        MediaSort.nameAsc || MediaSort.nameDesc => 1,
        MediaSort.ratingDesc || MediaSort.ratingAsc => 2,
      };
}

final mediaViewPreferencesProvider = NotifierProvider.family<
    MediaViewPreferencesController, MediaViewPreferences, MediaViewScope>(
  MediaViewPreferencesController.new,
);
