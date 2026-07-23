import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/screens/name_screen.dart';

void main() {
  testWidgets('onboarding minimal accepte une personne seule sans nom',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: NameScreen(onNext: (value) => result = value),
      ),
    );
    await tester.tap(find.text('Je préfère compléter plus tard'));
    await tester.pump();
    expect(result, '');
    expect(find.textContaining('conjoint'), findsNothing);
    expect(find.textContaining('enfant'), findsNothing);
  });

  testWidgets('nom d’affichage reste facultatif et saisissable',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: NameScreen(onNext: (value) => result = value),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.tap(find.text('Commencer'));
    await tester.pump();
    expect(result, 'Alex');
  });
}
