import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/screens/help_information_screen.dart';
import 'package:moms_ai/screens/privacy_data_screen.dart';
import 'package:moms_ai/services/route_travel_time_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('confidentialité reste distincte de la mémoire', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyDataScreen(
          travelConsentGateway: _FakeTravelConsentGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confidentialité'), findsOneWidget);
    expect(find.text('AUTORISATIONS'), findsOneWidget);
    expect(find.text('Gérer les autorisations'), findsOneWidget);
    expect(find.textContaining('Zelia te montre'), findsNothing);
    expect(find.textContaining('souvenirs de conversation'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('MES DONNÉES'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('MES DONNÉES'), findsOneWidget);
    expect(find.text('Souvenirs actifs'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'le calcul des trajets reste désactivé avant une autorisation claire',
      (tester) async {
    var enabled = false;
    final consent = _FakeTravelConsentGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyDataScreen(
          onAutomaticTravelSettingChanged: (value) async => enabled = value,
          travelConsentGateway: consent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Calcul automatique des trajets'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(enabled, isFalse);
    expect(find.text('Autoriser les calculs'), findsOneWidget);
    expect(find.textContaining('Apple Plans'), findsOneWidget);

    await tester.ensureVisible(find.text('Pas maintenant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pas maintenant'));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);

    await tester.scrollUntilVisible(
      find.text('Calcul automatique des trajets'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Autoriser les calculs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autoriser les calculs'));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
  });

  testWidgets('aide affiche la FAQ et permet une recherche', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Zelia',
      packageName: 'com.test.zelia',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      const MaterialApp(home: HelpInformationScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aide'), findsOneWidget);
    expect(find.text('Comment puis-je t’aider ?'), findsOneWidget);
    expect(find.text('FOIRE AUX QUESTIONS'), findsOneWidget);
    expect(find.text('Rechercher une question…'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'notification concentration',
    );
    await tester.pumpAndSettle();
    expect(find.text('Pourquoi je ne reçois pas une notification ?'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Contacter l’équipe Zelia'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Contacter l’équipe Zelia'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Version de Zelia'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Version de Zelia'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _FakeTravelConsentGateway implements RouteTravelConsentGateway {
  bool authorized = false;

  @override
  Future<bool> isAuthorized() async => authorized;

  @override
  Future<void> setAuthorized(bool value) async => authorized = value;
}
