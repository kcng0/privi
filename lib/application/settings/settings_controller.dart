import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/enums.dart';

/// Non-security prefs (HD Smith-style Display / Playback / Security timeout).
class AppSettings {
  const AppSettings({
    this.gridColumns = 3,
    this.albumColumns = 3,
    this.autoLockSeconds = 30,
    this.playerExternal = true,
    this.slideshowSeconds = 3,
    this.shuffleDefault = false,
    this.recycleRetentionDays = 7,
    this.flagSecure = false,
    this.mediaKindFilter = MediaKindFilter.image,
  });

  final int gridColumns; // 2–5
  final int albumColumns; // 3–4
  final int autoLockSeconds; // 0 = immediately
  final bool playerExternal;
  final int slideshowSeconds;
  final bool shuffleDefault;
  final int recycleRetentionDays;
  final bool flagSecure;

  /// Shared Visible + Invisible photo XOR video mode (persisted).
  final MediaKindFilter mediaKindFilter;

  AppSettings copyWith({
    int? gridColumns,
    int? albumColumns,
    int? autoLockSeconds,
    bool? playerExternal,
    int? slideshowSeconds,
    bool? shuffleDefault,
    int? recycleRetentionDays,
    bool? flagSecure,
    MediaKindFilter? mediaKindFilter,
  }) {
    return AppSettings(
      gridColumns: gridColumns ?? this.gridColumns,
      albumColumns: albumColumns ?? this.albumColumns,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      playerExternal: playerExternal ?? this.playerExternal,
      slideshowSeconds: slideshowSeconds ?? this.slideshowSeconds,
      shuffleDefault: shuffleDefault ?? this.shuffleDefault,
      recycleRetentionDays: recycleRetentionDays ?? this.recycleRetentionDays,
      flagSecure: flagSecure ?? this.flagSecure,
      mediaKindFilter: mediaKindFilter ?? this.mediaKindFilter,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _kGrid = 'grid_columns';
  static const _kAlbum = 'album_columns';
  static const _kAutoLock = 'auto_lock_seconds';
  static const _kPlayer = 'player_external';
  static const _kSlideshow = 'slideshow_seconds';
  static const _kShuffle = 'shuffle_default';
  static const _kRecycle = 'recycle_retention_days';
  static const _kFlagSecure = 'flag_secure';
  static const _kMediaKind = 'media_kind_filter'; // image | video

  SharedPreferences? _prefs;

  @override
  AppSettings build() {
    Future.microtask(_load);
    return const AppSettings();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final p = _prefs!;
    final kindRaw = p.getString(_kMediaKind);
    final kind =
        kindRaw == 'video' ? MediaKindFilter.video : MediaKindFilter.image;
    state = AppSettings(
      gridColumns: p.getInt(_kGrid) ?? 3,
      albumColumns: p.getInt(_kAlbum) ?? 3,
      autoLockSeconds: p.getInt(_kAutoLock) ?? 30,
      playerExternal: p.getBool(_kPlayer) ?? true,
      slideshowSeconds: p.getInt(_kSlideshow) ?? 3,
      shuffleDefault: p.getBool(_kShuffle) ?? false,
      recycleRetentionDays: p.getInt(_kRecycle) ?? 7,
      flagSecure: p.getBool(_kFlagSecure) ?? false,
      mediaKindFilter: kind,
    );
  }

  Future<void> setGridColumns(int n) async {
    state = state.copyWith(gridColumns: n.clamp(2, 5));
    await _prefs?.setInt(_kGrid, state.gridColumns);
  }

  Future<void> setAlbumColumns(int n) async {
    state = state.copyWith(albumColumns: n.clamp(3, 4));
    await _prefs?.setInt(_kAlbum, state.albumColumns);
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    state = state.copyWith(autoLockSeconds: seconds);
    await _prefs?.setInt(_kAutoLock, seconds);
  }

  Future<void> setPlayerExternal(bool v) async {
    state = state.copyWith(playerExternal: v);
    await _prefs?.setBool(_kPlayer, v);
  }

  Future<void> setSlideshowSeconds(int s) async {
    state = state.copyWith(slideshowSeconds: s);
    await _prefs?.setInt(_kSlideshow, s);
  }

  Future<void> setShuffleDefault(bool v) async {
    state = state.copyWith(shuffleDefault: v);
    await _prefs?.setBool(_kShuffle, v);
  }

  Future<void> setRecycleRetentionDays(int d) async {
    state = state.copyWith(recycleRetentionDays: d);
    await _prefs?.setInt(_kRecycle, d);
  }

  Future<void> setFlagSecure(bool v) async {
    state = state.copyWith(flagSecure: v);
    await _prefs?.setBool(_kFlagSecure, v);
  }

  Future<void> setMediaKindFilter(MediaKindFilter kind) async {
    state = state.copyWith(mediaKindFilter: kind);
    await _prefs?.setString(
      _kMediaKind,
      kind == MediaKindFilter.video ? 'video' : 'image',
    );
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
