import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:privateheart_vault/app.dart';

void main() {
  testWidgets('App boots into the dark-themed placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PrivateHeartApp()));

    // Title and the signature heart accent are present.
    expect(find.text('PrivateHeart'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    // Theme is dark.
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
