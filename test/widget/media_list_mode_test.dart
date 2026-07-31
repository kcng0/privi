import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/gallery/gallery_controller.dart';
import 'package:privi/application/media/album_list_preferences.dart';
import 'package:privi/application/media/visible_folder_view_preferences.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/data/services/grid_thumbnail_service.dart';
import 'package:privi/data/services/thumbnail_cache.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/floating_action_capsule.dart';
import 'package:privi/presentation/grid/media_grid_screen.dart';
import 'package:privi/presentation/visible/visible_media_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopGridThumbnailService extends GridThumbnailService {
  _NoopGridThumbnailService()
      : super(
          cache: ThumbnailCache(cacheDir: () async => Directory.systemTemp),
          decodeAsset: (_, __) async => null,
          ensureVaultPoster: (_) async => null,
        );

  @override
  Future<Uint8List?> forAsset(String assetId, {required int size}) async =>
      null;

  @override
  Future<Uint8List?> forVaultItem(
    MediaItem item, {
    required int size,
  }) async =>
      null;
}

class _FakeGalleryService extends GalleryService {
  _FakeGalleryService(this.items);

  final List<GalleryAsset> items;

  @override
  Future<void> ensureVaultHydrated(
    Future<List<String>> Function() loadPaths,
  ) async {}

  @override
  Future<List<GalleryAsset>> listAssets({
    required String pathId,
    required MediaKindFilter filter,
    int page = 0,
    int size = 120,
  }) async =>
      items;
}

MediaItem _video(String id) => MediaItem(
      id: id,
      privatePath: '/tmp/$id.mp4',
      originalName: '$id.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      rating: 2,
      dateAdded: DateTime(2026),
      sizeBytes: 1,
      durationMs: 65000,
    );

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Invisible list mode reaches album media and Delete follows Rate',
      (tester) async {
    SharedPreferences.setMockInitialValues({'media_kind_filter': 'video'});
    final preferences = await SharedPreferences.getInstance();
    final item = _video('private-video');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        gridThumbnailServiceProvider.overrideWithValue(
          _NoopGridThumbnailService(),
        ),
        albumMediaProvider.overrideWith(
          (ref, albumId) => Stream.value([item]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(albumListPreferencesProvider.notifier)
        .setViewMode(AlbumViewMode.list);

    await tester.pumpWidget(
      _app(
        container,
        const MediaGridScreen(albumId: 'album', title: 'Album'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invisible-media-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('invisible-media-grid')), findsNothing);
    expect(find.text('private-video.mp4'), findsOneWidget);

    await tester.longPress(
      find.byKey(const ValueKey('invisible-media-private-video')),
    );
    await tester.pumpAndSettle();

    final capsule = tester.widget<FloatingActionCapsule>(
      find.byType(FloatingActionCapsule),
    );
    expect(
      capsule.actions.map((action) => action.label),
      ['Unhide', 'Rate', 'Delete', 'More'],
    );
    expect(capsule.actions[2].destructive, isTrue);
  });

  testWidgets('Visible list mode reaches folder media', (tester) async {
    SharedPreferences.setMockInitialValues({'media_kind_filter': 'video'});
    final preferences = await SharedPreferences.getInstance();
    const item = GalleryAsset(
      id: 'visible-video',
      isVideo: true,
      title: 'visible-video.mp4',
      durationMs: 65000,
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        galleryServiceProvider.overrideWithValue(_FakeGalleryService([item])),
        gridThumbnailServiceProvider.overrideWithValue(
          _NoopGridThumbnailService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(visibleFolderViewPreferencesProvider.notifier)
        .setViewMode(AlbumViewMode.list);

    await tester.pumpWidget(
      _app(
        container,
        const VisibleMediaGrid(pathId: 'camera', title: 'Camera'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('visible-media-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('visible-media-grid')), findsNothing);
    expect(find.text('visible-video.mp4'), findsOneWidget);
  });
}
