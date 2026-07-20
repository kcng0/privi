import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/player/player_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaItem _item(String id) => MediaItem(
      id: id,
      privatePath: '/tmp/$id.jpg',
      originalName: '$id.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      rating: 0,
      dateAdded: DateTime(2026),
      sizeBytes: 1,
    );

void main() {
  test('completion while paused does not advance the playlist', () async {
    SharedPreferences.setMockInitialValues({'player_external': false});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final controller = container.read(playerControllerProvider.notifier);
    controller.start(items: [_item('one'), _item('two')]);
    controller.togglePlayPause();

    await controller.onItemCompleted();

    final state = container.read(playerControllerProvider);
    expect(state.current?.id, 'one');
    expect(state.playing, isFalse);
  });
}
