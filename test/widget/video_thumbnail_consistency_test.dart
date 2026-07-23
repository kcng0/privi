import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/gallery/gallery_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/media_thumbnail_spec.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/data/services/grid_thumbnail_service.dart';
import 'package:privi/data/services/thumbnail_cache.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/video_duration_badge.dart';
import 'package:privi/presentation/grid/thumbnail_tile.dart';
import 'package:privi/presentation/visible/visible_media_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns fixed bytes for both grids without touching disk or platform.
class _FakeGrid extends GridThumbnailService {
  _FakeGrid(this._bytes)
      : super(
          cache: ThumbnailCache(cacheDir: () async => Directory.systemTemp),
          decodeAsset: (_, __) async => null,
          ensureVaultPoster: (_) async => null,
        );

  final Uint8List _bytes;

  @override
  Future<Uint8List?> forAsset(String assetId, {required int size}) async =>
      _bytes;

  @override
  Future<Uint8List?> forVaultItem(MediaItem item, {required int size}) async =>
      _bytes;
}

class _GalleryWithOneVideo extends GalleryService {
  @override
  Future<Uint8List?> mediaThumbnail(String assetId) async => null;

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
  }) async {
    return const [
      GalleryAsset(
        id: 'visible-video',
        isVideo: true,
        title: 'video.mp4',
        durationMs: 65000,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Visible video uses the shared duration badge', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final gallery = _GalleryWithOneVideo();
    addTearDown(gallery.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          galleryServiceProvider.overrideWithValue(gallery),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const VisibleMediaGrid(pathId: 'videos', title: 'Videos'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(VideoDurationBadge), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
  });

  testWidgets('Visible selection exposes Delete directly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final gallery = _GalleryWithOneVideo();
    addTearDown(gallery.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          galleryServiceProvider.overrideWithValue(gallery),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const VisibleMediaGrid(pathId: 'videos', title: 'Videos'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.longPress(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  test('Visible video preview playlist contains only folder videos', () {
    const items = [
      GalleryAsset(id: 'photo', isVideo: false, title: 'photo.jpg'),
      GalleryAsset(id: 'first', isVideo: true, title: 'first.mp4'),
      GalleryAsset(id: 'second', isVideo: true, title: 'second.mp4'),
    ];

    expect(
      visibleVideoPlaylist(items).map((item) => item.id),
      ['first', 'second'],
    );
  });

  testWidgets('Invisible video uses the shared duration badge', (tester) async {
    final item = MediaItem(
      id: 'invisible-video',
      privatePath: '/missing/video.mp4',
      originalName: 'video.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      rating: 0,
      dateAdded: DateTime.utc(2026),
      sizeBytes: 1,
      durationMs: 65000,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox.square(
            dimension: 120,
            child: ThumbnailTile(item: item),
          ),
        ),
      ),
    );

    expect(find.byType(VideoDurationBadge), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
  });

  testWidgets('Invisible poster decode preserves its source aspect ratio',
      (tester) async {
    final item = MediaItem(
      id: 'invisible-video',
      privatePath: '/missing/video.mp4',
      originalName: 'video.mp4',
      mimeType: 'video/mp4',
      isVideo: true,
      rating: 0,
      dateAdded: DateTime.utc(2026),
      sizeBytes: 1,
      thumbnailPath: '/missing/poster.jpg',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gridThumbnailServiceProvider.overrideWithValue(
            _FakeGrid(Uint8List.fromList([1, 2, 3, 4])),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox.square(
              dimension: 120,
              child: ThumbnailTile(item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect(image.image, isA<ResizeImage>());
    final resizeImage = image.image as ResizeImage;
    // Width-only decode preserves the source aspect ratio; both grids now
    // decode at the shared grid size.
    expect(resizeImage.width, MediaThumbnailSpec.gridDimension);
    expect(resizeImage.height, isNull);
  });
}
