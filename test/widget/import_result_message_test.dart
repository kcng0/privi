import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/import/import_result_message.dart';

void main() {
  testWidgets('iOS import outcomes have explicit user-visible detail',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      importOutcomeDetail(context, ImportErrorCode.sourceStillPresent),
      'Private copy saved; source remains in Photos',
    );
    expect(
      importOutcomeDetail(context, ImportErrorCode.notLocallyAvailable),
      'Original media is not available offline',
    );
    expect(
      importOutcomeDetail(
        context,
        ImportErrorCode.destinationVerificationFailed,
      ),
      'Private copy could not be verified',
    );
    expect(
      importOutcomeDetail(context, ImportErrorCode.needManageStorage),
      isNull,
    );
    expect(importOutcomeDetail(context, null), isNull);
  });
}
