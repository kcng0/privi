import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/db/database.dart';
import 'package:privi/data/repositories/album_repository.dart';
import 'package:privi/domain/models/album.dart';
import 'package:privi/domain/models/album_group.dart';
import 'package:privi/domain/models/album_view.dart';
import 'package:privi/domain/models/group_view.dart';
import 'package:privi/domain/models/shelf_entry.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/home/group_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('collection detail exposes list toggle and CRUD menu',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.utc(2026, 1, 1);
    final member = AlbumView(
      album: Album(
        id: 'album-1',
        name: 'Chapter 1',
        isSystem: false,
        createdAt: now,
        groupId: 'group-1',
      ),
      count: 3,
    );
    final group = GroupView(
      group: AlbumGroup(id: 'group-1', name: 'Series', createdAt: now),
      members: [member],
      totalCount: 3,
      maxRating: 0,
    );

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.memory();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(database),
        albumRepositoryProvider.overrideWithValue(AlbumRepository(database)),
        albumShelfProvider.overrideWithValue(
          AsyncData(
            AlbumShelf(
              systemViews: const [],
              entries: [GroupEntry(group)],
            ),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupScreen(groupId: 'group-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('collection-member-grid')),
      findsOneWidget,
    );
    expect(find.byTooltip('List'), findsOneWidget);
    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('collection-member-list')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add albums'), findsOneWidget);
    expect(find.text('Rename collection'), findsOneWidget);
    expect(find.text('Dissolve collection'), findsOneWidget);

    Navigator.of(tester.element(find.text('Add albums'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mosaic'));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      const Offset(419, 420),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('collection-member-list')),
      findsOneWidget,
    );
  });
}
