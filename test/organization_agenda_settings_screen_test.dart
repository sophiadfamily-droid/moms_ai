import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/screens/organization_agenda_settings_screen.dart';
import 'package:moms_ai/services/route_travel_time_service.dart';

void main() {
  testWidgets('regroupe les réglages utiles sans vocabulaire technique',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var saved = _profile();
    final consent = _FakeTravelConsentGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationAgendaSettingsScreen(
          profile: saved,
          travelConsentGateway: consent,
          onSave: (profile) async => saved = profile,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Organisation et agenda'), findsOneWidget);
    expect(find.text('Calcul automatique des trajets'), findsOneWidget);
    expect(find.text('Mes activités'), findsOneWidget);
    expect(find.text('Activités de mes enfants'), findsOneWidget);
    expect(find.text('Mes horaires de travail'), findsOneWidget);
    expect(find.text('Horaires d’école'), findsOneWidget);
    expect(find.text('Mes routines'), findsOneWidget);

    await tester.tap(find.text('15 min'));
    await tester.pumpAndSettle();
    expect(saved.agendaSafetyMarginMinutes, 15);

    final workSwitch = find.descendant(
      of: find.widgetWithText(ListTile, 'Mes horaires de travail'),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(
      workSwitch,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(workSwitch);
    await tester.pumpAndSettle();
    expect(saved.showWorkScheduleInAgenda, isTrue);
  });

  testWidgets('demande une autorisation claire avant les trajets automatiques',
      (tester) async {
    var saved = _profile();
    final consent = _FakeTravelConsentGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationAgendaSettingsScreen(
          profile: saved,
          travelConsentGateway: consent,
          onSave: (profile) async => saved = profile,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Autoriser les calculs'), findsOneWidget);
    expect(saved.automaticTravelCalculationEnabled, isFalse);

    await tester.tap(find.text('Autoriser les calculs'));
    await tester.pumpAndSettle();
    expect(consent.authorized, isTrue);
    expect(saved.automaticTravelCalculationEnabled, isTrue);
  });
}

UserProfile _profile() => UserProfile(
      firstName: 'Sophia',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );

final class _FakeTravelConsentGateway implements RouteTravelConsentGateway {
  bool authorized = false;

  @override
  Future<bool> isAuthorized() async => authorized;

  @override
  Future<void> setAuthorized(bool value) async => authorized = value;
}
