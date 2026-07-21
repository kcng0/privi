import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/enums.dart';
import '../../domain/models/video_playback_settings.dart';
import '../providers.dart';

/// Non-security prefs (Display / Playback / Security timeout).
class AppSettings {
  const AppSettings({
    this.gridColumns = 3,
    this.albumColumns = 3,
    this.autoLockSeconds = 30,
    this.playerExternal = true,
    this.playerSeekSeconds = 3,
    this.playerPlaybackSpeed = 1,
    this.slideshowSeconds = 3,
    this.shuffleDefault = false,
    this.recycleRetentionDays = 7,
    this.flagSecure = true,
    this.mediaKindFilter = MediaKindFilter.image,
    this.localeCode = '',
  });

  final int gridColumns; // 2–5
  final int albumColumns; // 3–4
  final int autoLockSeconds; // 0 = immediately
  final bool playerExternal;
  final int playerSeekSeconds;
  final double playerPlaybackSpeed;
  final int slideshowSeconds;
  final bool shuffleDefault;
  final int recycleRetentionDays;
  final bool flagSecure;

  /// Shared Visible + Invisible photo XOR video mode (persisted).
  final MediaKindFilter mediaKindFilter;

  /// UI language override. Empty = follow device. Values: en, zh_CN, zh_HK.
  final String localeCode;

  AppSettings copyWith({
    int? gridColumns,
    int? albumColumns,
    int? autoLockSeconds,
    bool? playerExternal,
    int? playerSeekSeconds,
    double? playerPlaybackSpeed,
    int? slideshowSeconds,
    bool? shuffleDefault,
    int? recycleRetentionDays,
    bool? flagSecure,
    MediaKindFilter? mediaKindFilter,
    String? localeCode,
  }) {
    return AppSettings(
      gridColumns: gridColumns ?? this.gridColumns,
      albumColumns: albumColumns ?? this.albumColumns,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      playerExternal: playerExternal ?? this.playerExternal,
      playerSeekSeconds: playerSeekSeconds ?? this.playerSeekSeconds,
      playerPlaybackSpeed: playerPlaybackSpeed ?? this.playerPlaybackSpeed,
      slideshowSeconds: slideshowSeconds ?? this.slideshowSeconds,
      shuffleDefault: shuffleDefault ?? this.shuffleDefault,
      recycleRetentionDays: recycleRetentionDays ?? this.recycleRetentionDays,
      flagSecure: flagSecure ?? this.flagSecure,
      mediaKindFilter: mediaKindFilter ?? this.mediaKindFilter,
      localeCode: localeCode ?? this.localeCode,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _kGrid = 'grid_columns';
  static const _kAlbum = 'album_columns';
  static const _kAutoLock = 'auto_lock_seconds';
  static const _kPlayer = 'player_external';
  static const _kPlayerSeek = 'player_seek_seconds';
  static const _kPlayerSpeed = 'player_playback_speed';
  static const _kSlideshow = 'slideshow_seconds';
  static const _kShuffle = 'shuffle_default';
  static const _kRecycle = 'recycle_retention_days';
  static const _kFlagSecure = 'flag_secure';
  static const _kMediaKind = 'media_kind_filter'; // image | video
  static const _kLocale = 'locale_code'; // '' | en | zh_CN | zh_HK

  late final SharedPreferences _prefs;

  @override
  AppSettings build() {
    final p = _prefs = ref.watch(sharedPreferencesProvider);
    final kindRaw = p.getString(_kMediaKind);
    final kind =
        kindRaw == 'video' ? MediaKindFilter.video : MediaKindFilter.image;
    return AppSettings(
      gridColumns: p.getInt(_kGrid) ?? 3,
      albumColumns: p.getInt(_kAlbum) ?? 3,
      autoLockSeconds: p.getInt(_kAutoLock) ?? 30,
      playerExternal: p.getBool(_kPlayer) ?? true,
      playerSeekSeconds: p.getInt(_kPlayerSeek) ?? 3,
      playerPlaybackSpeed: p.getDouble(_kPlayerSpeed) ?? 1,
      slideshowSeconds: p.getInt(_kSlideshow) ?? 3,
      shuffleDefault: p.getBool(_kShuffle) ?? false,
      recycleRetentionDays: p.getInt(_kRecycle) ?? 7,
      flagSecure: p.getBool(_kFlagSecure) ?? true,
      mediaKindFilter: kind,
      localeCode: p.getString(_kLocale) ?? '',
    );
  }

  Future<void> setGridColumns(int n) async {
    state = state.copyWith(gridColumns: n.clamp(2, 5));
    await _prefs.setInt(_kGrid, state.gridColumns);
  }

  Future<void> setAlbumColumns(int n) async {
    state = state.copyWith(albumColumns: n.clamp(3, 4));
    await _prefs.setInt(_kAlbum, state.albumColumns);
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    state = state.copyWith(autoLockSeconds: seconds);
    await _prefs.setInt(_kAutoLock, seconds);
  }

  Future<void> setPlayerExternal(bool v) async {
    state = state.copyWith(playerExternal: v);
    await _prefs.setBool(_kPlayer, v);
  }

  Future<void> setPlayerSeekSeconds(int seconds) async {
    if (!videoSeekSecondOptions.contains(seconds)) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    state = state.copyWith(playerSeekSeconds: seconds);
    await _prefs.setInt(_kPlayerSeek, seconds);
  }

  Future<void> setPlayerPlaybackSpeed(double speed) async {
    final matches = videoPlaybackSpeedOptions.where(
      (option) => (option - speed).abs() < 0.0001,
    );
    if (matches.isEmpty) throw ArgumentError.value(speed, 'speed');
    final normalized = matches.single;
    state = state.copyWith(playerPlaybackSpeed: normalized);
    await _prefs.setDouble(_kPlayerSpeed, normalized);
  }

  Future<void> setSlideshowSeconds(int s) async {
    state = state.copyWith(slideshowSeconds: s);
    await _prefs.setInt(_kSlideshow, s);
  }

  Future<void> setShuffleDefault(bool v) async {
    state = state.copyWith(shuffleDefault: v);
    await _prefs.setBool(_kShuffle, v);
  }

  Future<void> setRecycleRetentionDays(int d) async {
    state = state.copyWith(recycleRetentionDays: d);
    await _prefs.setInt(_kRecycle, d);
  }

  Future<void> setFlagSecure(bool v) async {
    state = state.copyWith(flagSecure: v);
    await _prefs.setBool(_kFlagSecure, v);
  }

  Future<void> setMediaKindFilter(MediaKindFilter kind) async {
    state = state.copyWith(mediaKindFilter: kind);
    await _prefs.setString(
      _kMediaKind,
      kind == MediaKindFilter.video ? 'video' : 'image',
    );
  }

  /// Empty [code] follows the device language.
  Future<void> setLocaleCode(String code) async {
    final normalized = switch (code) {
      'en' || 'zh_CN' || 'zh_HK' => code,
      _ => '',
    };
    state = state.copyWith(localeCode: normalized);
    await _prefs.setString(_kLocale, normalized);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
