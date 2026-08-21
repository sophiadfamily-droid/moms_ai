import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/screens/help_information_screen.dart';
import 'package:moms_ai/screens/privacy_data_screen.dart';
import 'package:moms_ai/services/account_data_lifecycle_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('confidentialité reste distincte de la mémoire', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const PrivacyDataScreen(),
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

  testWidgets('exporter prépare et présente les données du compte',
      (tester) async {
    final gateway = _FakeAccountDataLifecycleGateway();
    final presenter = _FakeAccountDataExportPresenter();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyDataScreen(
          accountDataLifecycleGateway: gateway,
          accountDataExportPresenter: presenter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Exporter mes données'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Exporter mes données'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exporter mes données'));
    await tester.pumpAndSettle();

    expect(gateway.exportCalls, 1);
    expect(presenter.presented?.fileName, 'export-test.pdf');
    expect(find.text('Ton export est prêt.'), findsOneWidget);
  });

  testWidgets('un export lent reste visible et explique le blocage temporaire',
      (tester) async {
    final gateway = _DelayedAccountDataLifecycleGateway();
    final presenter = _FakeAccountDataExportPresenter();
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyDataScreen(
          accountDataLifecycleGateway: gateway,
          accountDataExportPresenter: presenter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Exporter mes données'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Exporter mes données'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exporter mes données'));
    await tester.pump();

    expect(find.text('Préparation en cours…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.ensureVisible(find.text('Supprimer mes données'));
    await tester.pump();
    await tester.tap(find.text('Supprimer mes données'));
    await tester.pump();
    expect(
      find.text(
        'Je prépare déjà ton export. La fenêtre de partage va s’ouvrir.',
      ),
      findsOneWidget,
    );

    gateway.completeExport();
    await tester.pump();
    expect(presenter.presented?.fileName, 'export-test.pdf');
    expect(find.text('Préparation en cours…'), findsNothing);
  });

  testWidgets('suppression exige le mot complet avant toute action',
      (tester) async {
    final gateway = _FakeAccountDataLifecycleGateway();
    var deletedCallbackCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyDataScreen(
          accountDataLifecycleGateway: gateway,
          accountDataExportPresenter: _FakeAccountDataExportPresenter(),
          onAccountDataDeleted: () async => deletedCallbackCalls += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Supprimer mes données'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Supprimer mes données'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer mes données'));
    await tester.pumpAndSettle();

    expect(find.text('Écris SUPPRIMER pour confirmer.'), findsOneWidget);
    var deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Supprimer définitivement'),
    );
    expect(deleteButton.onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'supprimer');
    await tester.pumpAndSettle();
    expect(gateway.deleteCalls, 0);

    await tester.enterText(find.byType(TextField).last, 'SUPPRIMER');
    await tester.pumpAndSettle();
    deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Supprimer définitivement'),
    );
    expect(deleteButton.onPressed, isNotNull);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Supprimer définitivement'),
    );
    await tester.pumpAndSettle();

    expect(gateway.deleteCalls, 1);
    expect(deletedCallbackCalls, 1);
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

final class _FakeAccountDataLifecycleGateway
    implements AccountDataLifecycleGateway {
  int exportCalls = 0;
  int deleteCalls = 0;

  @override
  Future<AccountDataExportFile> prepareExport() async {
    exportCalls += 1;
    return AccountDataExportFile(
      bytes: Uint8List.fromList([123, 125]),
      fileName: 'export-test.pdf',
      mimeType: 'application/pdf',
    );
  }

  @override
  Future<void> deleteAllData() async {
    deleteCalls += 1;
  }
}

final class _FakeAccountDataExportPresenter
    implements AccountDataExportPresenter {
  AccountDataExportFile? presented;

  @override
  Future<void> present(AccountDataExportFile file) async => presented = file;
}

final class _DelayedAccountDataLifecycleGateway
    implements AccountDataLifecycleGateway {
  final Completer<AccountDataExportFile> _export = Completer();

  void completeExport() {
    _export.complete(
      AccountDataExportFile(
        bytes: Uint8List.fromList([123, 125]),
        fileName: 'export-test.pdf',
        mimeType: 'application/pdf',
      ),
    );
  }

  @override
  Future<AccountDataExportFile> prepareExport() => _export.future;

  @override
  Future<void> deleteAllData() async {}
}
