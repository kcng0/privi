import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/application/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}
