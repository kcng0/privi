import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/common/heart_rating_bar.dart';

void main() {
  testWidgets(
      'rating bar has three hearts and tapping current rating clears it',
      (tester) async {
    var rating = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HeartRatingBar(
              rating: rating,
              interactive: true,
              scrim: false,
              onRate: (next) => setState(() => rating = next),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            (widget.icon == Icons.favorite ||
                widget.icon == Icons.favorite_border),
      ),
      findsNWidgets(3),
    );

    await tester.tap(find.byIcon(Icons.favorite).last);
    await tester.pump();

    expect(rating, 0);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNWidgets(3));
  });
}
