import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
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
import 'package:privi/core/l10n.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/data/services/grid_thumbnail_service.dart';
import 'package:privi/data/services/thumbnail_cache.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/album.dart';
import 'package:privi/domain/models/album_group.dart';
import 'package:privi/domain/models/album_view.dart';
import 'package:privi/domain/models/group_view.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/domain/models/shelf_entry.dart';
import 'package:privi/domain/models/video_playback_settings.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/floating_action_capsule.dart';
import 'package:privi/presentation/grid/thumbnail_tile.dart';
import 'package:privi/presentation/home/home_shell.dart';
import 'package:privi/presentation/lock/lock_screen.dart';
import 'package:privi/presentation/settings/settings_screen.dart';
import 'package:privi/presentation/player/video_player_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// Generates the README screenshots from synthetic, non-personal data.
///
/// Regenerate with:
/// `flutter test tool/readme_screenshots_test.dart --update-goldens`
/// Verify without changing assets by omitting `--update-goldens`.
const _surfaceKey = ValueKey<String>('readme-screenshot-surface');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadScreenshotFonts);

  testWidgets('capture current home, album, and settings screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final covers = _createCovers();
    final harness = await _createHarness(covers);
    addTearDown(() async {
      harness.container.dispose();
      await harness.database.close();
      await covers.directory.delete(recursive: true);
    });

    await _precacheCovers(tester, covers);
    await _pumpApp(tester, harness.container);
    await _tap(tester, find.text('Visible'));
    await _capture(tester, '01_visible_mosaic.png');
    await _tap(tester, find.byTooltip('List'));
    await _capture(tester, '02_visible_list.png');

    await _tap(tester, find.text('Invisible'));
    await _capture(tester, '03_invisible_mosaic.png');
    await _tap(tester, find.text('Berlin Vol. 1'));
    await _capture(tester, '08_album_mosaic.png');
    await tester.longPress(find.byType(ThumbnailTile).first);
    await _settle(tester);
    await _capture(tester, '09_album_selection.png');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await _settle(tester);

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
    await _settle(tester);
    Navigator.of(tester.element(find.text('City stories').first)).pop();
    await _settle(tester);
    await _tap(tester, find.byTooltip('More').first);
    await _tap(tester, find.text('Settings'));
    await _capture(tester, '12_settings.png');
    await tester.scrollUntilVisible(find.text('STORAGE'), 40);
    final settingsList = find.descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    );
    final storageTop = tester.getTopLeft(find.text('STORAGE')).dy;
    final viewportTop = tester.getTopLeft(settingsList).dy;
    final overlap = storageTop - viewportTop;
    if (overlap > 1) {
      await tester.drag(settingsList, Offset(0, -overlap));
      await tester.pump();
    }
    await _capture(tester, '13_vault_backup.png');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('capture current lock setup screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final covers = _createCovers();
    final harness = await _createHarness(
      covers,
      lockStatus: LockStatus.needsSetup,
    );
    addTearDown(() async {
      harness.container.dispose();
      await harness.database.close();
      await covers.directory.delete(recursive: true);
    });

    await _pumpApp(tester, harness.container, lockScreen: true);
    await _capture(tester, '14_lock_setup.png');
  });

  testWidgets('capture current built-in player controls', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final covers = _createCovers();
    addTearDown(() => covers.directory.delete(recursive: true));
    final frame = await tester.runAsync(
      () => decodeImageFromList(
        File(covers.playerFramePath).readAsBytesSync(),
      ),
    );
    if (frame == null) {
      throw StateError('Could not decode the player frame');
    }
    addTearDown(frame.dispose);

    await _pumpSurface(
      tester,
      home: _ReadmePlayerChrome(frame: frame),
    );
    await _capture(tester, '10_player.png');
    await _tap(tester, find.byTooltip('Player settings'));
    await _capture(tester, '11_player_settings.png');
  }, timeout: const Timeout(Duration(minutes: 1)));
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
  // Shelf subtitles draw U+2665. Roboto has no heart glyph, so the test
  // would otherwise paint a missing-glyph box.
  final symbols = File(
    '/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf',
  ).readAsBytesSync();
  final symbolsLoader = FontLoader('Noto Sans Symbols')
    ..addFont(Future.value(ByteData.sublistView(symbols)));
  await symbolsLoader.load();
}

ThemeData _screenshotTheme() {
  final baseTheme = AppTheme.dark;
  const fallback = ['Noto Sans Symbols'];
  return baseTheme.copyWith(
    textTheme: baseTheme.textTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: baseTheme.primaryTextTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: fallback,
    ),
    appBarTheme: baseTheme.appBarTheme.copyWith(
      titleTextStyle: baseTheme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
        fontFamilyFallback: fallback,
      ),
      toolbarTextStyle: baseTheme.appBarTheme.toolbarTextStyle?.copyWith(
        fontFamily: 'Roboto',
        fontFamilyFallback: fallback,
      ),
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  bool lockScreen = false,
}) {
  return _pumpSurface(
    tester,
    home: lockScreen ? const LockScreen() : const HomeShell(),
    container: container,
  );
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  required Widget home,
  ProviderContainer? container,
}) async {
  final screenshotTheme = _screenshotTheme();
  final app = RepaintBoundary(
    key: _surfaceKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: screenshotTheme,
      darkTheme: screenshotTheme,
      themeMode: ThemeMode.dark,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpWidget(
    container == null
        ? app
        : UncontrolledProviderScope(container: container, child: app),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester);
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
  await _seedAlbumMedia(database, covers);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      databaseProvider.overrideWithValue(database),
      appBuildInfoProvider.overrideWithValue(
        AppBuildInfo(version: '1.1.0', buildNumber: '37'),
      ),
      gridThumbnailServiceProvider.overrideWithValue(
        _ScreenshotThumbnails(covers.coverBytes),
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

Future<void> _seedAlbumMedia(
  AppDatabase database,
  _ScreenshotCovers covers,
) async {
  final createdAt = DateTime.utc(2026, 1, 1);
  await database.insertAlbum(
    AlbumsCompanion.insert(
      id: 'album-berlin',
      name: 'Berlin Vol. 1',
      isSystem: false,
      createdAt: createdAt,
      rating: const Value(3),
      groupId: const Value('group-city'),
    ),
  );
  for (var i = 0; i < covers.media.length; i++) {
    final item = covers.media[i];
    final taken = DateTime.utc(2026, 3, covers.media.length - i, 12);
    await database.insertMedia(
      MediaItemsCompanion.insert(
        id: item.id,
        privatePath: item.path,
        originalName: item.name,
        mimeType: 'image/png',
        isVideo: false,
        rating: Value(item.rating),
        dateAdded: taken,
        dateTaken: Value(taken),
        sizeBytes: item.bytesLength,
        width: const Value(512),
        height: const Value(512),
        thumbnailPath: Value(item.path),
      ),
    );
    await database.addMembership('album-berlin', item.id, taken);
  }
}

_ScreenshotCovers _createCovers() {
  final directory = Directory.systemTemp.createTempSync('privi-readme-');
  final coverBytes = Uint8List.fromList(
    File(p.absolute('assets', 'branding', 'app_icon.png')).readAsBytesSync(),
  );
  const labels = [
    'album-berlin',
    'album-tokyo',
    'album-notes',
    'camera',
    'screenshots',
    'downloads',
    'media-harbor',
    'media-market',
    'media-station',
    'media-bridge',
    'media-arcade',
    'media-roof',
    'media-canal',
    'media-plaza',
    'media-garden',
  ];
  final paths = <String, String>{};
  final folderBytes = <String, Uint8List>{};
  for (final label in labels) {
    final path = p.join(directory.path, '$label.png');
    File(path).writeAsBytesSync(coverBytes, flush: true);
    paths[label] = path;
    if (label == 'camera' || label == 'screenshots' || label == 'downloads') {
      folderBytes[label] = coverBytes;
    }
  }
  final playerFramePath = p.join(directory.path, 'player-frame.png');
  File(playerFramePath).writeAsBytesSync(coverBytes, flush: true);
  const media = <_ScreenshotMedia>[
    _ScreenshotMedia('media-harbor', 'Harbor morning.png', 3),
    _ScreenshotMedia('media-market', 'Night market.png', 2),
    _ScreenshotMedia('media-station', 'Station hall.png', 1),
    _ScreenshotMedia('media-bridge', 'River bridge.png', 0),
    _ScreenshotMedia('media-arcade', 'Arcade lights.png', 3),
    _ScreenshotMedia('media-roof', 'Rooftop dusk.png', 2),
    _ScreenshotMedia('media-canal', 'Canal walk.png', 1),
    _ScreenshotMedia('media-plaza', 'Winter plaza.png', 3),
    _ScreenshotMedia('media-garden', 'Greenhouse.png', 2),
  ];
  return _ScreenshotCovers(
    directory: directory,
    paths: paths,
    folderBytes: folderBytes,
    coverBytes: coverBytes,
    media: [
      for (final item in media)
        _SeededMedia(
          id: item.id,
          name: item.name,
          rating: item.rating,
          path: paths[item.id]!,
          bytesLength: File(paths[item.id]!).lengthSync(),
        ),
    ],
    playerFramePath: playerFramePath,
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
    required this.directory,
    required this.paths,
    required this.folderBytes,
    required this.coverBytes,
    required this.media,
    required this.playerFramePath,
  });

  final Directory directory;
  final Map<String, String> paths;
  final Map<String, Uint8List> folderBytes;
  final Uint8List coverBytes;
  final List<_SeededMedia> media;
  final String playerFramePath;
}

/// Returns the bundled icon without touching the disk cache. Real file reads
/// inside `testWidgets` stay pending under fake async, so album tiles never
/// paint.
class _ScreenshotThumbnails extends GridThumbnailService {
  _ScreenshotThumbnails(this.bytes)
      : super(
          cache: ThumbnailCache(
            cacheDir: () async =>
                Directory.systemTemp.createTempSync('privi-readme-thumbs'),
          ),
          decodeAsset: (_, __) async => bytes,
          ensureVaultPoster: (_) async => null,
        );

  final Uint8List bytes;

  @override
  Future<Uint8List?> forAsset(String assetId, {required int size}) {
    return Future<Uint8List?>.value(bytes);
  }

  @override
  Future<Uint8List?> forVaultItem(MediaItem item, {required int size}) {
    return Future<Uint8List?>.value(bytes);
  }
}

Future<void> _precacheCovers(
  WidgetTester tester,
  _ScreenshotCovers covers,
) async {
  await tester.pumpWidget(
    const MediaQuery(
      data: MediaQueryData(devicePixelRatio: 3),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(key: _surfaceKey),
      ),
    ),
  );
  final context = tester.element(find.byKey(_surfaceKey));
  final paths = covers.paths.values.toSet();
  await tester.runAsync(() async {
    final providers = <ImageProvider<Object>>[
      MemoryImage(covers.coverBytes),
      ResizeImage(MemoryImage(covers.coverBytes), width: 512),
      for (final path in paths) ...<ImageProvider<Object>>[
        FileImage(File(path)),
        ResizeImage(FileImage(File(path)), width: 512),
        ResizeImage(FileImage(File(path)), width: 192),
      ],
    ];
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
}

class _ScreenshotMedia {
  const _ScreenshotMedia(this.id, this.name, this.rating);

  final String id;
  final String name;
  final int rating;
}

class _SeededMedia {
  const _SeededMedia({
    required this.id,
    required this.name,
    required this.rating,
    required this.path,
    required this.bytesLength,
  });

  final String id;
  final String name;
  final int rating;
  final String path;
  final int bytesLength;
}

/// Mirrors the built-in player chrome. Widget tests cannot initialize the
/// Android decoder, so this uses the same public controls as [PlayerScreen].
class _ReadmePlayerChrome extends StatelessWidget {
  const _ReadmePlayerChrome({required this.frame});

  final ui.Image frame;

  static const _value = VideoPlayerValue(
    duration: Duration(minutes: 48, seconds: 12),
    position: Duration(minutes: 12, seconds: 40),
    isInitialized: true,
    isPlaying: true,
    size: Size(1920, 1080),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: RawImage(image: frame, fit: BoxFit.contain),
            ),
          ),
          const VideoTransportRegion(
            child: VideoTransportControls(
              value: _value,
              hasPrevious: true,
              hasNext: true,
              onPrevious: _noop,
              onPlayPause: _noop,
              onNext: _noop,
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Material(
                color: Colors.black54,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _noop,
                      ),
                      const Expanded(
                        child: Text(
                          'Night market.mp4 · 2/6',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.videoLockOrientation,
                        icon: const Icon(Icons.screen_rotation),
                        color: Colors.white,
                        onPressed: _noop,
                      ),
                      IconButton(
                        tooltip: context.l10n.videoLockTouch,
                        icon: const Icon(Icons.lock_outline),
                        color: Colors.white,
                        onPressed: _noop,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: VideoBottomControls(
              value: _value,
              landscape: false,
              fitMode: VideoFitMode.bestFit,
              hasPrevious: true,
              hasNext: true,
              onPrevious: _noop,
              onSeek: (_) async {},
              onPlayPause: _noop,
              onNext: _noop,
              onToggleOrientation: _noop,
              onChooseFit: _noop,
              onOpenSettings: () => showVideoSettingsSheet(
                context,
                seekSeconds: 10,
                onSeekSecondsChanged: (_) {},
                dragSeekSeconds: 600,
                onDragSeekSecondsChanged: (_) {},
                playbackSpeed: 1.5,
                onPlaybackSpeedChanged: (_) async {},
                muted: false,
                onMutedChanged: (_) {},
                looping: true,
                onLoopingChanged: (_) {},
                shuffle: false,
                onShuffleChanged: (_) {},
                rating: 2,
                onRatingChanged: (_) {},
                defaultOrientation: 'auto',
                onDefaultOrientationChanged: (_) {},
                onOpenExternal: _noop,
              ),
              showTransport: false,
              onOpenTracks: _noop,
              onPictureInPicture: _noop,
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}
