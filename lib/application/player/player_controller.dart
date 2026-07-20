import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/media_item.dart';
import '../../domain/models/playlist.dart';
import '../settings/settings_controller.dart';
import 'external_player_coordinator.dart';

class PlayerUiState {
  const PlayerUiState({
    this.playlist,
    this.playing = false,
    this.externalHandedOff = false,
  });

  final Playlist? playlist;
  final bool playing;
  final bool externalHandedOff;

  MediaItem? get current => playlist?.current;

  PlayerUiState copyWith({
    Playlist? playlist,
    bool? playing,
    bool? externalHandedOff,
  }) {
    return PlayerUiState(
      playlist: playlist ?? this.playlist,
      playing: playing ?? this.playing,
      externalHandedOff: externalHandedOff ?? this.externalHandedOff,
    );
  }
}

class PlayerController extends Notifier<PlayerUiState> {
  Timer? _slideTimer;

  @override
  PlayerUiState build() {
    ref.onDispose(() => _slideTimer?.cancel());
    return const PlayerUiState();
  }

  void start({
    required List<MediaItem> items,
    bool? shuffle,
    String? startItemId,
  }) {
    if (items.isEmpty) return;
    final useShuffle =
        shuffle ?? ref.read(settingsControllerProvider).shuffleDefault;
    final pl = Playlist(items: items, shuffle: useShuffle);
    if (startItemId != null) pl.jumpToItemId(startItemId);
    state = PlayerUiState(playlist: pl, playing: true);
    unawaited(_onItemEntered());
  }

  void stop() {
    _slideTimer?.cancel();
    state = const PlayerUiState();
  }

  void togglePlayPause() {
    final playing = !state.playing;
    state = state.copyWith(playing: playing);
    if (playing) {
      unawaited(_onItemEntered());
    } else {
      _slideTimer?.cancel();
    }
  }

  void toggleShuffle() {
    final pl = state.playlist;
    if (pl == null) return;
    pl.toggleShuffle();
    // Persist preference.
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setShuffleDefault(pl.shuffle),
    );
    state = state.copyWith(playlist: pl);
  }

  Future<void> next() async {
    final pl = state.playlist;
    if (pl == null || !pl.hasNext) {
      state = state.copyWith(playing: false);
      return;
    }
    pl.next();
    state =
        state.copyWith(playlist: pl, playing: true, externalHandedOff: false);
    await _onItemEntered();
  }

  Future<void> prev() async {
    final pl = state.playlist;
    if (pl == null || !pl.hasPrev) return;
    pl.prev();
    state =
        state.copyWith(playlist: pl, playing: true, externalHandedOff: false);
    await _onItemEntered();
  }

  /// Called when built-in video finishes or slideshow timer fires.
  Future<void> onItemCompleted() async {
    if (!state.playing) return;
    await next();
  }

  Future<void> _onItemEntered() async {
    _slideTimer?.cancel();
    final item = state.current;
    if (item == null || !state.playing) return;

    final settings = ref.read(settingsControllerProvider);

    if (item.isVideo && settings.playerExternal) {
      final external = ref.read(externalPlayerCoordinatorProvider);
      if (external.supported) {
        final ok = await external.open(
          filePath: item.privatePath,
          mimeType: item.mimeType,
        );
        state = state.copyWith(playing: false, externalHandedOff: ok);
        return;
      }
    }

    if (!item.isVideo) {
      // Image slideshow auto-advance.
      final delay = Duration(seconds: settings.slideshowSeconds);
      _slideTimer = Timer(delay, () {
        if (state.playing) unawaited(onItemCompleted());
      });
    }
    // Built-in video: PlayerScreen video widget calls onItemCompleted.
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(PlayerController.new);
