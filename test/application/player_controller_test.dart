import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/player/external_player_gateway.dart';
import 'package:privi/application/player/player_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}

final class _ExternalPlayerGateway implements ExternalPlayerGateway {
  int openCount = 0;

  @override
  bool get supported => true;

  @override
  Future<bool> open({
    required String filePath,
    required String mimeType,
  }) async {
    openCount++;
    return true;
  }

  @override
  ExternalPlayerReturn? takeReturn() => null;
}

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

MediaItem _video(String id) => MediaItem(
      id: id,
      privatePath: '/tmp/$id.mp4',
      originalName: '$id.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      rating: 0,
      dateAdded: DateTime(2026),
      sizeBytes: 1,
    );

void main() {
  test('built-in completion advances while playback is active', () async {
    SharedPreferences.setMockInitialValues({'player_external': false});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final controller = container.read(playerControllerProvider.notifier);
    controller.start(items: [_video('one'), _video('two')]);

    await controller.onItemCompleted();

    final state = container.read(playerControllerProvider);
    expect(state.current?.id, 'two');
    expect(state.playing, isTrue);
  });

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

  test('completed external video advances and launches the next item',
      () async {
    SharedPreferences.setMockInitialValues({'player_external': true});
    final preferences = await SharedPreferences.getInstance();
    final external = _ExternalPlayerGateway();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        externalPlayerGatewayProvider.overrideWithValue(external),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(playerControllerProvider.notifier);
    controller.start(items: [_video('one'), _video('two')]);
    await pumpEventQueue();

    expect(external.openCount, 1);
    expect(container.read(playerControllerProvider).externalHandedOff, isTrue);

    await controller.onExternalPlayerReturned(ExternalPlayerReturn.completed);

    final state = container.read(playerControllerProvider);
    expect(state.current?.id, 'two');
    expect(state.externalHandedOff, isTrue);
    expect(external.openCount, 2);
  });

  test('interrupted external video stays on the current item', () async {
    SharedPreferences.setMockInitialValues({'player_external': true});
    final preferences = await SharedPreferences.getInstance();
    final external = _ExternalPlayerGateway();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        externalPlayerGatewayProvider.overrideWithValue(external),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(playerControllerProvider.notifier);
    controller.start(items: [_video('one'), _video('two')]);
    await pumpEventQueue();

    await controller.onExternalPlayerReturned(
      ExternalPlayerReturn.interrupted,
    );

    final state = container.read(playerControllerProvider);
    expect(state.current?.id, 'one');
    expect(state.externalHandedOff, isTrue);
    expect(external.openCount, 1);
  });

  test('external return cannot advance a playlist without an active hand-off',
      () async {
    SharedPreferences.setMockInitialValues({'player_external': false});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final controller = container.read(playerControllerProvider.notifier);
    controller.start(items: [_item('one'), _item('two')]);

    await controller.onExternalPlayerReturned(ExternalPlayerReturn.completed);

    expect(container.read(playerControllerProvider).current?.id, 'one');
  });
}
