import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/action_confirmation.dart';
import 'package:moms_ai/widgets/action_confirmation_dialog.dart';

void main() {
  const presentation = ActionConfirmationPresentation(
    title: 'Confirmer cette action',
    summary: 'Ajouter cet élément à la liste.',
    consequence: 'La liste sera modifiée après confirmation.',
    allowPostpone: true,
  );

  for (final size in const [Size(390, 844), Size(1024, 768)]) {
    testWidgets('common confirmation stays responsive at $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ActionConfirmationDialog(presentation: presentation),
          ),
        ),
      );
      expect(find.text('Confirmer'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('common confirmation supports text scale 1.6', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: ActionConfirmationDialog(presentation: presentation),
          ),
        ),
      ),
    );
    expect(find.text('Confirmer cette action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
