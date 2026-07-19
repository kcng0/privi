import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../providers.dart';

class CollectionViewPreferencesController extends Notifier<AlbumViewMode> {
  CollectionViewPreferencesController(this.groupId);

  static const storagePrefix = 'collection_view_preferences_v1.';

  final String groupId;
  Future<void> _pendingWrite = Future.value();

  String get _storageKey {
    final identity = base64Url.encode(utf8.encode(groupId));
    return '$storagePrefix$identity';
  }

  @override
  AlbumViewMode build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final raw = preferences.getString(_storageKey);
    if (raw == null) return AlbumViewMode.mosaic;
    try {
      return AlbumViewMode.values.byName(raw);
    } on StateError {
      throw FormatException('Unknown collection view mode: $raw');
    }
  }

  Future<void> setViewMode(AlbumViewMode mode) {
    if (state == mode) return _pendingWrite;
    state = mode;
    final preferences = ref.read(sharedPreferencesProvider);
    _pendingWrite = _pendingWrite.then((_) async {
      if (!await preferences.setString(_storageKey, mode.name)) {
        throw StateError('Could not persist collection view preferences');
      }
    });
    return _pendingWrite;
  }
}

final collectionViewPreferencesProvider = NotifierProvider.family<
    CollectionViewPreferencesController, AlbumViewMode, String>(
  CollectionViewPreferencesController.new,
);
