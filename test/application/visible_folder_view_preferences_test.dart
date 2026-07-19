import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/media/album_list_preferences.dart';
import 'package:privi/application/media/visible_folder_view_preferences.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('visible folder view mode persists independently from Invisible',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
        );

    final first = container();
    expect(
      first.read(visibleFolderViewPreferencesProvider),
      AlbumViewMode.mosaic,
    );
    expect(
      first.read(albumListPreferencesProvider).viewMode,
      AlbumViewMode.mosaic,
    );
    await first
        .read(visibleFolderViewPreferencesProvider.notifier)
        .setViewMode(AlbumViewMode.list);
    expect(
      first.read(albumListPreferencesProvider).viewMode,
      AlbumViewMode.mosaic,
    );
    first.dispose();

    final restored = container();
    addTearDown(restored.dispose);
    expect(
      restored.read(visibleFolderViewPreferencesProvider),
      AlbumViewMode.list,
    );
    expect(
      restored.read(albumListPreferencesProvider).viewMode,
      AlbumViewMode.mosaic,
    );
  });

  test('unknown visible folder view mode fails explicitly', () async {
    SharedPreferences.setMockInitialValues({
      VisibleFolderViewPreferencesController.storageKey: 'unsupported',
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(
      () => container.read(visibleFolderViewPreferencesProvider),
      throwsA(
        predicate<Object>(
          (error) => error
              .toString()
              .contains('FormatException: Unknown visible folder view mode'),
        ),
      ),
    );
  });
}
