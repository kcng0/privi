import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privi/application/import/import_controller.dart';
import 'package:privi/core/theme/app_theme.dart';
import 'package:privi/data/services/import/import_models.dart';
import 'package:privi/l10n/app_localizations.dart';
import 'package:privi/presentation/import/import_progress_sheet.dart';

class _ResolvingImportController extends ImportController {
  @override
  ImportUiState build() {
    return const ImportUiState(
      running: true,
      progress: ImportProgress(
        done: 0,
        total: 2,
        phase: ImportPhase.resolving,
      ),
    );
  }
}

void main() {
  testWidgets('progress sheet renders typed phase in Chinese', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importControllerProvider.overrideWith(
            _ResolvingImportController.new,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark,
          home: const Scaffold(body: ImportProgressSheet()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('正在准备媒体…'), findsOneWidget);
    expect(find.text('Resolving media…'), findsNothing);
  });
}
