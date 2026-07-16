import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privateheart_vault/presentation/common/floating_action_capsule.dart';

void main() {
  testWidgets('Invisible selection capsule order is Unhide | Rate | More',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingActionCapsule(
            actions: [
              FloatingActionItem(
                icon: Icons.visibility,
                label: 'Unhide',
                onTap: () {},
              ),
              FloatingActionItem(
                icon: Icons.favorite,
                label: 'Rate',
                onTap: () {},
              ),
              FloatingActionItem(
                icon: Icons.more_horiz,
                label: 'More',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(labels.indexOf('Unhide'), lessThan(labels.indexOf('Rate')));
    expect(labels.indexOf('Rate'), lessThan(labels.indexOf('More')));
  });
}
