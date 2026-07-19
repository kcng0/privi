import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../providers.dart';

class VisibleFolderViewPreferencesController extends Notifier<AlbumViewMode> {
  static const storageKey = 'visible_folder_view_mode_v1';

  Future<void> _pendingWrite = Future.value();

  @override
  AlbumViewMode build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final raw = preferences.getString(storageKey);
    if (raw == null) return AlbumViewMode.mosaic;
    try {
      return AlbumViewMode.values.byName(raw);
    } on ArgumentError {
      throw FormatException('Unknown visible folder view mode: $raw');
    }
  }

  Future<void> setViewMode(AlbumViewMode mode) {
    if (state == mode) return _pendingWrite;
    state = mode;
    final preferences = ref.read(sharedPreferencesProvider);
    _pendingWrite = _pendingWrite.then((_) async {
      if (!await preferences.setString(storageKey, mode.name)) {
        throw StateError('Could not persist visible folder view mode');
      }
    });
    return _pendingWrite;
  }
}

final visibleFolderViewPreferencesProvider =
    NotifierProvider<VisibleFolderViewPreferencesController, AlbumViewMode>(
  VisibleFolderViewPreferencesController.new,
);
