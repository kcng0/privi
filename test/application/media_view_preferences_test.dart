import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/media/media_view_preferences.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/application/settings/settings_controller.dart';
import 'package:privi/domain/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer createContainer(SharedPreferences preferences) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
    ],
  );
}

void main() {
  test('folder preferences persist independently by source and folder id',
      () async {
    SharedPreferences.setMockInitialValues({'grid_columns': 4});
    final preferences = await SharedPreferences.getInstance();
    final visibleScope = MediaViewScope.visibleFolder('Camera/shared');
    final vaultScope = MediaViewScope.vaultAlbum('Camera/shared');
    final inheritedScope = MediaViewScope.vaultAlbum('inherits-columns');
    final first = createContainer(preferences);

    expect(
      first.read(mediaViewPreferencesProvider(visibleScope)).gridColumns,
      4,
    );
    expect(
      first.read(mediaViewPreferencesProvider(vaultScope)).sorts,
      const [MediaSort.dateAddedDesc],
    );

    final visible =
        first.read(mediaViewPreferencesProvider(visibleScope).notifier);
    await visible.setSorting(
      const [MediaSort.ratingDesc, MediaSort.dateAddedDesc],
      multiSortEnabled: true,
    );
    await visible.setHeartLevels(const {1, 3});
    await visible.setGridColumns(5);
    await first
        .read(mediaViewPreferencesProvider(inheritedScope).notifier)
        .setSorting(
      const [MediaSort.nameAsc],
      multiSortEnabled: false,
    );
    await first.read(settingsControllerProvider.notifier).setGridColumns(2);

    expect(
      first.read(mediaViewPreferencesProvider(inheritedScope)).gridColumns,
      2,
    );
    expect(
      first
          .read(mediaViewPreferencesProvider(inheritedScope))
          .gridColumnsOverride,
      isNull,
    );

    expect(
      first.read(mediaViewPreferencesProvider(vaultScope)),
      isNot(
        predicate<MediaViewPreferences>(
          (value) => value.multiSortEnabled || value.gridColumns == 5,
        ),
      ),
    );

    first.dispose();
    final restored = createContainer(preferences);
    addTearDown(restored.dispose);
    final restoredVisible =
        restored.read(mediaViewPreferencesProvider(visibleScope));
    final restoredVault =
        restored.read(mediaViewPreferencesProvider(vaultScope));

    expect(restoredVisible.multiSortEnabled, isTrue);
    expect(
      restoredVisible.sorts,
      const [MediaSort.ratingDesc, MediaSort.dateAddedDesc],
    );
    expect(restoredVisible.heartLevels, const {1, 3});
    expect(restoredVisible.ratingFilter, RatingFilter.favorites);
    expect(restoredVisible.gridColumns, 5);
    expect(restoredVault.multiSortEnabled, isFalse);
    expect(restoredVault.sorts, const [MediaSort.dateAddedDesc]);
    expect(restoredVault.heartLevels, isEmpty);
    expect(restoredVault.gridColumns, 2);
  });
}
