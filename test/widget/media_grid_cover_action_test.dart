import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/media_repository.dart';
import 'package:privi/data/services/grid_thumbnail_service.dart';
import 'package:privi/data/services/thumbnail_cache.dart';
import 'package:privi/data/services/vault_storage_service.dart';
import 'package:privi/domain/models/album.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/grid/media_grid_screen.dart';
import 'package:privi/presentation/grid/thumbnail_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyGridThumbnailService extends GridThumbnailService {
  _EmptyGridThumbnailService()
      : super(
          cache: ThumbnailCache(cacheDir: () async => Directory.systemTemp),
          decodeAsset: (_, __) async => null,
          ensureVaultPoster: (_) async => null,
        );

  @override
  Future<Uint8List?> forVaultItem(MediaItem item, {required int size}) async =>
      null;
}

class _DelayedDeleteRepository extends MediaRepository {
  _DelayedDeleteRepository(this.database)
      : super(database, VaultStorageService());

  final AppDatabase database;
  final deletion = Completer<void>();

  @override
  Future<void> purgeMany(List<String> ids) => deletion.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final video = MediaItem(
    id: 'video-1',
    privatePath: '/missing/video.mp4',
    originalName: 'video.mp4',
    mimeType: 'video/mp4',
    isVideo: true,
    rating: 0,
    dateAdded: DateTime.utc(2026),
    sizeBytes: 1,
  );

  Future<void> openMoreActions(
    WidgetTester tester, {
    required String albumId,
    MediaRepository? mediaRepository,
  }) async {
    SharedPreferences.setMockInitialValues({
      'media_kind_filter': 'video',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          gridThumbnailServiceProvider.overrideWithValue(
            _EmptyGridThumbnailService(),
          ),
          albumMediaProvider.overrideWith(
            (ref, id) => Stream.value([video]),
          ),
          if (mediaRepository != null)
            mediaRepositoryProvider.overrideWithValue(mediaRepository),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaGridScreen(albumId: albumId, title: 'Album'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(ThumbnailTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('system album does not offer the unsupported cover action',
      (tester) async {
    await openMoreActions(tester, albumId: SystemAlbumIds.all);

    expect(find.text('Set as cover'), findsNothing);
    expect(find.text('Move to album'), findsOneWidget);
  });

  testWidgets('user album offers the cover action for a selected video',
      (tester) async {
    await openMoreActions(tester, albumId: 'user-album');

    expect(find.text('Set as cover'), findsOneWidget);
  });

  testWidgets('favorites offers the cover action for a selected video',
      (tester) async {
    await openMoreActions(tester, albumId: SystemAlbumIds.favorites);

    expect(find.text('Set as cover'), findsOneWidget);
  });

  testWidgets('recycle deletion shows progress until the batch completes',
      (tester) async {
    final repository = _DelayedDeleteRepository(AppDatabase.memory());
    addTearDown(repository.database.close);
    await openMoreActions(
      tester,
      albumId: SystemAlbumIds.recycle,
      mediaRepository: repository,
    );

    await tester.tap(find.text('Delete forever'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete forever'),
      ),
      findsOneWidget,
    );

    repository.deletion.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Deleted 1 forever'), findsOneWidget);
  });
}
