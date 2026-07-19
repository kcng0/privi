import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/media/collection_view_preferences.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('collection view modes persist and remain isolated by group', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
        );

    final first = container();
    expect(
      first.read(collectionViewPreferencesProvider('series-a')),
      AlbumViewMode.mosaic,
    );
    await first
        .read(collectionViewPreferencesProvider('series-a').notifier)
        .setViewMode(AlbumViewMode.list);
    expect(
      first.read(collectionViewPreferencesProvider('series-b')),
      AlbumViewMode.mosaic,
    );
    first.dispose();

    final restored = container();
    addTearDown(restored.dispose);
    expect(
      restored.read(collectionViewPreferencesProvider('series-a')),
      AlbumViewMode.list,
    );
    expect(
      restored.read(collectionViewPreferencesProvider('series-b')),
      AlbumViewMode.mosaic,
    );
  });
}
