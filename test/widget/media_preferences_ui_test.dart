import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/domain/enums.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/grid_app_menu.dart';
import 'package:privi/presentation/common/rating_filter_bar.dart';

Widget localizedApp({
  required Widget home,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

void main() {
  testWidgets('Hearts filter label uses the active locale', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: RatingFilterBar(
            value: RatingFilter.all,
            heartLevels: const {},
            onChanged: (_) {},
            onHeartsPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('爱心'), findsOneWidget);
    expect(find.text('Hearts'), findsNothing);
  });

  testWidgets('sort picker toggles single and ordered multi-sort',
      (tester) async {
    var sorts = <MediaSort>[MediaSort.dateAddedDesc];
    var multiSortEnabled = false;

    await tester.pumpWidget(
      localizedApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.sort),
              onPressed: () {
                GridAppMenu.showSortPicker(
                  context,
                  selected: sorts,
                  multiSortEnabled: multiSortEnabled,
                  onChanged: (nextSorts, nextMultiSortEnabled) {
                    sorts = nextSorts;
                    multiSortEnabled = nextMultiSortEnabled;
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    expect(find.text('Multi-sort'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.text('Name A–Z'));
    await tester.pumpAndSettle();
    expect(sorts, const [MediaSort.nameAsc]);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(multiSortEnabled, isTrue);

    await tester.tap(find.text('Highest rating'));
    await tester.pumpAndSettle();
    expect(
      sorts,
      const [MediaSort.nameAsc, MediaSort.ratingDesc],
    );
    expect(find.byType(Badge), findsNWidgets(2));

    await tester.tap(find.text('Newest first'));
    await tester.pumpAndSettle();
    expect(
      sorts,
      const [
        MediaSort.nameAsc,
        MediaSort.ratingDesc,
        MediaSort.dateAddedDesc,
      ],
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(multiSortEnabled, isFalse);
    expect(sorts, const [MediaSort.nameAsc]);
  });
}
