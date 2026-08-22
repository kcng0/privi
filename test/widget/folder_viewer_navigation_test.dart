import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/gallery_service.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/viewer/viewer_screen.dart';
import 'package:privi/presentation/visible/gallery_preview_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnlockedLock extends LockController {
  @override
  VaultLockState build() => const VaultLockState(status: LockStatus.unlocked);
}

MediaItem _image(String id) => MediaItem(
      id: id,
      privatePath: '/tmp/$id.jpg',
      originalName: '$id.jpg',
      mimeType: 'image/jpeg',
      isVideo: false,
      rating: 0,
      dateAdded: DateTime(2026),
      sizeBytes: 1,
    );

GalleryAsset _galleryImage(String id) => GalleryAsset(
      id: id,
      isVideo: false,
      title: '$id.jpg',
    );

Widget _scopedApp({
  required ProviderContainer container,
  required Widget home,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({'player_external': false});
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      lockControllerProvider.overrideWith(_UnlockedLock.new),
    ],
  );
}

Future<void> _swipeToNext(WidgetTester tester) async {
  await tester.fling(
    find.byKey(const Key('folder-media-page-view')),
    const Offset(-500, 0),
    2000,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('folder image viewer swipes to the next sorted image',
      (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _scopedApp(
        container: container,
        home: ViewerScreen(
          items: [_image('alpha'), _image('beta')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('alpha.jpg'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await _swipeToNext(tester);

    expect(find.text('beta.jpg'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('Visible image preview swipes through the folder sort order',
      (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _scopedApp(
        container: container,
        home: GalleryPreviewScreen(
          items: [_galleryImage('alpha'), _galleryImage('beta')],
          initialIndex: 0,
          resolveFile: (asset) async => File('/missing/${asset.id}.jpg'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('alpha.jpg'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await _swipeToNext(tester);

    expect(find.text('beta.jpg'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
  });
}
