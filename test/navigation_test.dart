import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/screens/main_navigation.dart';

void main() {
  testWidgets('Main navigation opens its principal sections', (
    WidgetTester tester,
  ) async {
    final profile = UserProfile(
      firstName: 'Test',
      familyStatus: 'Je vis en couple 🤍',
      workStatus: 'Je travaille à temps plein 💼',
      partnerName: '',
      wantsNotifications: true,
      children: [],
    );

    const screenLabels = [
      'Écran Accueil',
      'Écran Zelia',
      'Écran Agenda',
      'Écran Tâches',
      'Écran Courses',
      'Écran Profil',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigation(
          profile: profile,
          testScreens: screenLabels
              .map(
                (label) => Center(
                  child: Text(label),
                ),
              )
              .toList(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Écran Accueil'), findsOneWidget);

    final destinations = find.byType(NavigationDestination);
    expect(destinations, findsNWidgets(6));

    await tester.tap(destinations.at(3));
    await tester.pump();
    expect(find.text('Écran Tâches'), findsOneWidget);

    await tester.tap(destinations.at(1));
    await tester.pump();
    expect(find.text('Écran Zelia'), findsOneWidget);

    await tester.tap(destinations.at(4));
    await tester.pump();
    expect(find.text('Écran Courses'), findsOneWidget);

    await tester.tap(destinations.at(5));
    await tester.pump();
    expect(find.text('Écran Profil'), findsOneWidget);
  });
}
