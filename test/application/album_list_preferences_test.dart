import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/media/album_list_preferences.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('album list preferences persist sort and view mode', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
        );

    final first = container();
    expect(
      first.read(albumListPreferencesProvider).sorts,
      const [AlbumSort.nameAsc],
    );
    await first.read(albumListPreferencesProvider.notifier).setSorting(
      const [AlbumSort.ratingDesc, AlbumSort.nameAsc],
      multiSortEnabled: true,
    );
    await first
        .read(albumListPreferencesProvider.notifier)
        .setViewMode(AlbumViewMode.list);
    first.dispose();

    final restored = container();
    addTearDown(restored.dispose);
    expect(
      restored.read(albumListPreferencesProvider).sorts,
      const [AlbumSort.ratingDesc, AlbumSort.nameAsc],
    );
    expect(
      restored.read(albumListPreferencesProvider).multiSortEnabled,
      isTrue,
    );
    expect(
      restored.read(albumListPreferencesProvider).viewMode,
      AlbumViewMode.list,
    );
  });

  test('custom sort rejects multi-sort combinations', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(
      () => container.read(albumListPreferencesProvider.notifier).setSorting(
        const [AlbumSort.custom, AlbumSort.nameAsc],
        multiSortEnabled: true,
      ),
      throwsFormatException,
    );
  });
}
