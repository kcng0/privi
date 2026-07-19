import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:privi/application/gallery/gallery_controller.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/app_build_info.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/album.dart';
import 'package:privi/domain/models/album_group.dart';
import 'package:privi/domain/models/album_view.dart';
import 'package:privi/domain/models/group_view.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/domain/models/shelf_entry.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/home/home_shell.dart';
import 'package:privi/presentation/lock/lock_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Generates the README screenshots from synthetic, non-personal data.
///
/// Regenerate with:
/// `flutter test tool/readme_screenshots_test.dart --update-goldens`
/// Verify without changing assets by omitting `--update-goldens`.
const _surfaceKey = ValueKey<String>('readme-screenshot-surface');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadScreenshotFonts);

  testWidgets('capture current home and collection screens', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final covers = await _createCovers();
    final harness = await _createHarness(covers);
    addTearDown(() async {
      harness.container.dispose();
      await harness.database.close();
    });

    await _pumpApp(tester, harness.container);
    await _tap(tester, find.text('Visible'));
    await _capture(tester, '01_visible_mosaic.png');
    await _tap(tester, find.byTooltip('List'));
    await _capture(tester, '02_visible_list.png');

    await _tap(tester, find.text('Invisible'));
    await _capture(tester, '03_invisible_mosaic.png');
    await _tap(tester, find.byTooltip('List'));
    await _capture(tester, '04_invisible_list.png');

    await _tap(tester, find.text('City stories'));
    await _capture(tester, '05_collection_mosaic.png');
    await _tap(tester, find.byTooltip('List'));
    await _capture(tester, '06_collection_list.png');
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('More'),
      ),
    );
    await _capture(tester, '07_collection_management.png');
    Navigator.of(tester.element(find.text('Add albums'))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('City stories').first)).pop();
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('More').first);
    await _tap(tester, find.text('Settings'));
    await _capture(tester, '08_settings.png');
  });

  testWidgets('capture current lock setup screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final covers = await _createCovers();
    final harness = await _createHarness(
      covers,
      lockStatus: LockStatus.needsSetup,
    );
    addTearDown(() async {
      harness.container.dispose();
      await harness.database.close();
    });

    await _pumpApp(tester, harness.container, lockScreen: true);
    await _capture(tester, '09_lock_setup.png');
  });
}

Future<void> _loadScreenshotFonts() async {
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!File(
    p.join(
      flutterRoot.path,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
      'Roboto-Regular.ttf',
    ),
  ).existsSync()) {
    final parent = flutterRoot.parent;
    if (parent.path == flutterRoot.path) {
      throw StateError('Could not locate Flutter material fonts');
    }
    flutterRoot = parent;
  }
  final fontDirectory = p.join(
    flutterRoot.path,
    'bin',
    'cache',
    'artifacts',
    'material_fonts',
  );
  final robotoRegular =
      File('$fontDirectory/Roboto-Regular.ttf').readAsBytesSync();
  final robotoMedium =
      File('$fontDirectory/Roboto-Medium.ttf').readAsBytesSync();
  final robotoBold = File('$fontDirectory/Roboto-Bold.ttf').readAsBytesSync();
  final icons =
      File('$fontDirectory/MaterialIcons-Regular.otf').readAsBytesSync();
  final robotoLoader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.sublistView(robotoRegular)))
    ..addFont(Future.value(ByteData.sublistView(robotoMedium)))
    ..addFont(Future.value(ByteData.sublistView(robotoBold)));
  await robotoLoader.load();
  final iconsLoader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons)));
  await iconsLoader.load();
}

Future<void> _pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  bool lockScreen = false,
}) async {
  final baseTheme = AppTheme.dark;
  final screenshotTheme = baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: baseTheme.appBarTheme.copyWith(
      titleTextStyle:
          baseTheme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
      toolbarTextStyle: baseTheme.appBarTheme.toolbarTextStyle
          ?.copyWith(fontFamily: 'Roboto'),
    ),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _surfaceKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: screenshotTheme,
          darkTheme: screenshotTheme,
          themeMode: ThemeMode.dark,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: lockScreen ? const LockScreen() : const HomeShell(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(_surfaceKey),
    matchesGoldenFile(p.join('..', 'assets', 'screenshots', name)),
  );
  // ignore: avoid_print
  print('Wrote assets/screenshots/$name');
}

Future<_ScreenshotHarness> _createHarness(
  _ScreenshotCovers covers, {
  LockStatus lockStatus = LockStatus.unlocked,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'locale_code': 'en'});
  final preferences = await SharedPreferences.getInstance();
  final database = AppDatabase.memory();
  final group = AlbumGroup(
    id: 'group-city',
    name: 'City stories',
    createdAt: DateTime.utc(2026, 1, 1),
  );
  final memberOne = _albumView(
    id: 'album-berlin',
    name: 'Berlin Vol. 1',
    count: 38,
    rating: 3,
    coverPath: covers.paths['album-berlin'],
    groupId: group.id,
  );
  final memberTwo = _albumView(
    id: 'album-tokyo',
    name: 'Tokyo Vol. 2',
    count: 24,
    rating: 2,
    coverPath: covers.paths['album-tokyo'],
    groupId: group.id,
  );
  final groupView = GroupView(
    group: group,
    members: [memberOne, memberTwo],
    totalCount: memberOne.count + memberTwo.count,
    maxRating: memberOne.album.rating,
    cover: memberOne,
  );
  final shelf = AlbumShelf(
    systemViews: [
      _albumView(
        id: SystemAlbumIds.all,
        name: 'All Media',
        count: 124,
        systemKind: SystemAlbumKind.all,
      ),
      _albumView(
        id: SystemAlbumIds.favorites,
        name: 'Favorites',
        count: 42,
        systemKind: SystemAlbumKind.favorites,
      ),
      _albumView(
        id: SystemAlbumIds.recycle,
        name: 'Recycle Bin',
        count: 3,
        systemKind: SystemAlbumKind.recycle,
      ),
    ],
    entries: [
      GroupEntry(groupView),
      AlbumEntry(memberOne),
      AlbumEntry(memberTwo),
      AlbumEntry(
        _albumView(
          id: 'album-notes',
          name: 'Notes',
          count: 17,
          rating: 1,
          coverPath: covers.paths['album-notes'],
        ),
      ),
    ],
    groups: [groupView],
  );
  final gallery = _ScreenshotGalleryService(covers.folderBytes);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      databaseProvider.overrideWithValue(database),
      appBuildInfoProvider.overrideWithValue(
        AppBuildInfo(version: '1.0.14', buildNumber: '19'),
      ),
      lockControllerProvider.overrideWith(
        () => _ScreenshotLock(status: lockStatus),
      ),
      albumShelfProvider.overrideWithValue(AsyncData(shelf)),
      galleryServiceProvider.overrideWithValue(gallery),
      galleryPermissionProvider.overrideWith(
        (ref) async => PermissionState.authorized,
      ),
      galleryFoldersProvider.overrideWith(
        (ref) async => const [
          GalleryFolder(id: 'camera', name: 'Camera', count: 86),
          GalleryFolder(id: 'screenshots', name: 'Screenshots', count: 31),
          GalleryFolder(id: 'downloads', name: 'Downloads', count: 12),
        ],
      ),
    ],
  );
  return _ScreenshotHarness(container: container, database: database);
}

AlbumView _albumView({
  required String id,
  required String name,
  required int count,
  SystemAlbumKind? systemKind,
  int rating = 0,
  String? coverPath,
  String? groupId,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return AlbumView(
    album: Album(
      id: id,
      name: name,
      isSystem: systemKind != null,
      createdAt: now,
      systemKind: systemKind,
      rating: rating,
      groupId: groupId,
    ),
    count: count,
    cover: coverPath == null
        ? null
        : MediaItem(
            id: '$id-cover',
            privatePath: coverPath,
            thumbnailPath: coverPath,
            originalName: '$name.png',
            mimeType: 'image/png',
            isVideo: false,
            rating: rating,
            dateAdded: now,
            sizeBytes: 1,
          ),
  );
}

Future<_ScreenshotCovers> _createCovers() async {
  final coverPath = p.absolute('assets', 'branding', 'app_icon.png');
  final coverBytes = Uint8List.fromList(File(coverPath).readAsBytesSync());
  final labels = [
    'album-berlin',
    'album-tokyo',
    'album-notes',
    'camera',
    'screenshots',
    'downloads',
  ];
  final paths = <String, String>{};
  final folderBytes = <String, Uint8List>{};
  for (final label in labels) {
    final bytes = Uint8List.fromList(coverBytes);
    paths[label] = coverPath;
    if (label == 'camera' || label == 'screenshots' || label == 'downloads') {
      folderBytes[label] = bytes;
    }
  }
  return _ScreenshotCovers(
    paths: paths,
    folderBytes: folderBytes,
  );
}

class _ScreenshotGalleryService extends GalleryService {
  _ScreenshotGalleryService(this._covers) : super();

  final Map<String, Uint8List> _covers;

  @override
  Future<Uint8List?> folderCover({
    required String pathId,
    required MediaKindFilter filter,
  }) async =>
      _covers[pathId];
}

class _ScreenshotLock extends LockController {
  _ScreenshotLock({required this.status});

  final LockStatus status;

  @override
  VaultLockState build() => VaultLockState(status: status);
}

class _ScreenshotHarness {
  const _ScreenshotHarness({required this.container, required this.database});

  final ProviderContainer container;
  final AppDatabase database;
}

class _ScreenshotCovers {
  const _ScreenshotCovers({
    required this.paths,
    required this.folderBytes,
  });

  final Map<String, String> paths;
  final Map<String, Uint8List> folderBytes;
}
