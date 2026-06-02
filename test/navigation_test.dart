import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/screens/main_navigation.dart';
import 'package:moms_ai/models/user_profile.dart';

void main() {
  testWidgets('Main navigation basic flows', (WidgetTester tester) async {
    final profile = UserProfile(
      firstName: 'Test',
      familyStatus: 'Je vis en couple 🤍',
      workStatus: 'Je travaille à temps plein 💼',
      partnerName: '',
      wantsNotifications: true,
      children: [],
    );

    await tester.pumpWidget(MaterialApp(
      home: MainNavigation(profile: profile),
    ));

    await tester.pumpAndSettle();

    // Home screen should show quick access
    expect(find.text('Accès rapides'), findsOneWidget);

    // Tap bottom nav Tâches (use icon to avoid ambiguous text matches)
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('Mes tâches ✨'), findsOneWidget);

    // Add a task
    await tester.enterText(find.byType(TextField).first, 'Tester tâche');
    await tester.tap(find.text('Ajouter une tâche 💕'));
    await tester.pumpAndSettle();
    expect(find.text('Tester tâche'), findsOneWidget);

    // Tap center icon to go to Chat
    await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Zelia 💕'), findsOneWidget);

    // Send a message
    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsOneWidget);

    // Tap bottom nav Courses
    await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Mes courses 🛍️'), findsOneWidget);

    // Add shopping item
    await tester.enterText(find.byType(TextField).first, 'lait');
    await tester.tap(find.text('Ajouter aux courses 💕'));
    await tester.pumpAndSettle();
    expect(find.text('lait'), findsOneWidget);

    // Tap bottom nav Profil
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Mon profil 👤'), findsOneWidget);

    // Save profile (embedded): tap save and ensure still on profile screen
    await tester.tap(find.text('Sauvegarder 💕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mon profil 👤'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
