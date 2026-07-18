import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../providers.dart';

class AlbumListPreferences {
  AlbumListPreferences({
    required List<AlbumSort> sorts,
    required this.multiSortEnabled,
    required this.viewMode,
  }) : sorts = List.unmodifiable(sorts);

  factory AlbumListPreferences.defaults() => AlbumListPreferences(
        sorts: const [AlbumSort.nameAsc],
        multiSortEnabled: false,
        viewMode: AlbumViewMode.mosaic,
      );

  final List<AlbumSort> sorts;
  final bool multiSortEnabled;
  final AlbumViewMode viewMode;

  AlbumListPreferences copyWith({
    List<AlbumSort>? sorts,
    bool? multiSortEnabled,
    AlbumViewMode? viewMode,
  }) =>
      AlbumListPreferences(
        sorts: sorts ?? this.sorts,
        multiSortEnabled: multiSortEnabled ?? this.multiSortEnabled,
        viewMode: viewMode ?? this.viewMode,
      );
}

class AlbumListPreferencesController extends Notifier<AlbumListPreferences> {
  static const storageKey = 'album_list_preferences_v1';
  Future<void> _pendingWrite = Future.value();

  @override
  AlbumListPreferences build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final raw = preferences.getString(storageKey);
    return raw == null ? AlbumListPreferences.defaults() : _decode(raw);
  }

  Future<void> setSorting(
    List<AlbumSort> sorts, {
    required bool multiSortEnabled,
  }) {
    _validate(sorts, multiSortEnabled: multiSortEnabled);
    return _commit(
      state.copyWith(
        sorts: sorts,
        multiSortEnabled: multiSortEnabled,
      ),
    );
  }

  Future<void> setViewMode(AlbumViewMode mode) =>
      _commit(state.copyWith(viewMode: mode));

  Future<void> _commit(AlbumListPreferences next) {
    state = next;
    final preferences = ref.read(sharedPreferencesProvider);
    final encoded = _encode(next);
    _pendingWrite = _pendingWrite.then((_) async {
      if (!await preferences.setString(storageKey, encoded)) {
        throw StateError('Could not persist album list preferences');
      }
    });
    return _pendingWrite;
  }

  static String _encode(AlbumListPreferences value) => jsonEncode({
        'sorts': value.sorts.map((sort) => sort.name).toList(growable: false),
        'multiSortEnabled': value.multiSortEnabled,
        'viewMode': value.viewMode.name,
      });

  static AlbumListPreferences _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['sorts'] is! List<dynamic> ||
        decoded['multiSortEnabled'] is! bool ||
        decoded['viewMode'] is! String) {
      throw const FormatException('Invalid album list preference fields');
    }
    final sorts = (decoded['sorts'] as List<dynamic>).map((value) {
      if (value is! String) {
        throw const FormatException('Sort names must be strings');
      }
      try {
        return AlbumSort.values.byName(value);
      } on StateError {
        throw FormatException('Unknown album sort: $value');
      }
    }).toList(growable: false);
    final multi = decoded['multiSortEnabled'] as bool;
    _validate(sorts, multiSortEnabled: multi);
    return AlbumListPreferences(
      sorts: sorts,
      multiSortEnabled: multi,
      viewMode: _viewMode(decoded['viewMode'] as String),
    );
  }

  static void _validate(
    List<AlbumSort> sorts, {
    required bool multiSortEnabled,
  }) {
    if (sorts.isEmpty) throw const FormatException('Sorts cannot be empty');
    if (sorts.contains(AlbumSort.custom) &&
        (sorts.length != 1 || multiSortEnabled)) {
      throw const FormatException('Custom sort is exclusive');
    }
    if (!multiSortEnabled && sorts.length != 1) {
      throw const FormatException('Single-sort mode requires one criterion');
    }
    final families = sorts
        .map(
          (sort) => switch (sort) {
            AlbumSort.createdAtDesc || AlbumSort.createdAtAsc => 0,
            AlbumSort.nameAsc || AlbumSort.nameDesc => 1,
            AlbumSort.ratingDesc || AlbumSort.ratingAsc => 2,
            AlbumSort.custom => 3,
          },
        )
        .toSet();
    if (families.length != sorts.length) {
      throw const FormatException('Sort families must be unique');
    }
  }

  static AlbumViewMode _viewMode(String value) {
    try {
      return AlbumViewMode.values.byName(value);
    } on StateError {
      throw FormatException('Unknown album view mode: $value');
    }
  }
}

final albumListPreferencesProvider =
    NotifierProvider<AlbumListPreferencesController, AlbumListPreferences>(
  AlbumListPreferencesController.new,
);
