import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/application/settings/settings_controller.dart';
import 'package:privi/domain/models/video_playback_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('all fit modes, extended speeds and orientation preferences persist',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(
      container.read(settingsControllerProvider).playerFitMode,
      VideoFitMode.bestFit,
    );
    expect(
      container.read(settingsControllerProvider).playerDefaultOrientation,
      'auto',
    );
    final settings = container.read(settingsControllerProvider.notifier);
    for (final mode in VideoFitMode.values) {
      await settings.setPlayerFitMode(mode);
      expect(prefs.getString('player_fit_mode'), mode.name);
    }
    for (final speed in videoPlaybackSpeedOptions) {
      await settings.setPlayerPlaybackSpeed(speed);
      expect(prefs.getDouble('player_playback_speed'), speed);
    }
    await settings.setPlayerDefaultOrientation('lastLocked');
    await settings.setPlayerLastLockedOrientation('sensorPortrait');
    container.dispose();
    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(
      restored.read(settingsControllerProvider).playerFitMode,
      VideoFitMode.ratio5x4,
    );
    expect(restored.read(settingsControllerProvider).playerPlaybackSpeed, 4);
    expect(
      restored.read(settingsControllerProvider).playerDefaultOrientation,
      'lastLocked',
    );
    expect(
      restored.read(settingsControllerProvider).playerLastLockedOrientation,
      'sensorPortrait',
    );
  });

  test('legacy fit and unknown mode restore as best fit', () async {
    for (final stored in ['fit', 'unknown']) {
      SharedPreferences.setMockInitialValues({'player_fit_mode': stored});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      expect(
        container.read(settingsControllerProvider).playerFitMode,
        VideoFitMode.bestFit,
      );
      container.dispose();
    }
  });

  test('seek interval defaults to three seconds and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );

    expect(first.read(settingsControllerProvider).playerSeekSeconds, 3);
    await first
        .read(settingsControllerProvider.notifier)
        .setPlayerSeekSeconds(10);
    first.dispose();

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);

    expect(restored.read(settingsControllerProvider).playerSeekSeconds, 10);
  });

  test('drag seek defaults to ten minutes and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );

    expect(
      first.read(settingsControllerProvider).playerDragSeekSeconds,
      600,
    );
    await first
        .read(settingsControllerProvider.notifier)
        .setPlayerDragSeekSeconds(120);
    first.dispose();

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);

    expect(
      restored.read(settingsControllerProvider).playerDragSeekSeconds,
      120,
    );
  });

  test('unsupported drag seek intervals fail explicitly', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(settingsControllerProvider.notifier)
          .setPlayerDragSeekSeconds(90),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      container.read(settingsControllerProvider).playerDragSeekSeconds,
      600,
    );
  });

  test('unsupported seek intervals fail explicitly', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(settingsControllerProvider.notifier)
          .setPlayerSeekSeconds(4),
      throwsA(isA<ArgumentError>()),
    );
    expect(container.read(settingsControllerProvider).playerSeekSeconds, 3);
  });

  test('playback speed defaults to one and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );

    expect(first.read(settingsControllerProvider).playerPlaybackSpeed, 1);
    await first
        .read(settingsControllerProvider.notifier)
        .setPlayerPlaybackSpeed(1.5);
    first.dispose();

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);

    expect(restored.read(settingsControllerProvider).playerPlaybackSpeed, 1.5);
  });

  test('unsupported playback speeds fail explicitly', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(settingsControllerProvider.notifier)
          .setPlayerPlaybackSpeed(1.1),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      container.read(settingsControllerProvider).playerPlaybackSpeed,
      1,
    );
    expect(videoPlaybackSpeedOptions, contains(1.5));
  });
}
