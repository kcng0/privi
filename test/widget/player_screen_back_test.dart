import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/lock/lock_controller.dart';
import 'package:privi/application/player/player_controller.dart';
import 'package:privi/application/providers.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/domain/models/media_item.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/player/player_screen.dart';
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

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerScreen(
                      items: [_image('one'), _image('two')],
                      title: 'Folder',
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('system Back hides controls before exiting the player',
      (tester) async {
    SharedPreferences.setMockInitialValues({'player_external': false});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(PlayerScreen), findsNothing);
    expect(container.read(playerControllerProvider).playlist, isNull);
  });

  testWidgets('visible top-bar Back exits without requiring a second press',
      (tester) async {
    SharedPreferences.setMockInitialValues({'player_external': false});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        lockControllerProvider.overrideWith(_UnlockedLock.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PlayerScreen), findsNothing);
    expect(container.read(playerControllerProvider).playlist, isNull);
  });
}
