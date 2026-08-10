import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/human/human_model_persistence.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/human/human_model_cloud_repository.dart';
import 'package:moms_ai/screens/human_profile_screen.dart';
import 'package:moms_ai/services/human/human_model_edit_service.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';

const _sizes = [
  Size(360, 800),
  Size(390, 844),
  Size(412, 915),
  Size(820, 1180),
  Size(1024, 1366),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profil humain expose toutes les sections sans détail technique',
      (tester) async {
    final editor = await _editor();
    await tester.pumpWidget(
      MaterialApp(
        home: HumanProfileScreen(
          legacyProfile: _profile(),
          editService: editor,
          accountScopeId: 'account-a',
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Moi',
      'Personnes',
      'Relations',
      'Foyers',
      'Domiciles',
      'Responsabilités',
      'Informations à confirmer',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('account-a'), findsNothing);
    expect(find.textContaining('modelRevision'), findsNothing);
    expect(find.textContaining('schemaVersion'), findsNothing);
    expect(find.textContaining('mutation'), findsNothing);
  });

  testWidgets('une personne seule peut ouvrir le formulaire et annuler',
      (tester) async {
    final editor = await _editor();
    await tester.pumpWidget(
      MaterialApp(
        home: HumanProfileScreen(
          legacyProfile: _profile(),
          editService: editor,
          accountScopeId: 'account-a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personnes'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune autre personne ajoutée'), findsWidgets);
    await tester.tap(find.text('Ajouter une personne'));
    await tester.pumpAndSettle();
    expect(find.text('Nom d’affichage'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Mon organisation'), findsOneWidget);
  });

  testWidgets('autre relation vide enregistre le profil sous Autre',
      (tester) async {
    final editor = await _editor();
    var legacyPartnerWasOverwritten = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HumanProfileScreen(
          legacyProfile: _profile(),
          editService: editor,
          accountScopeId: 'account-a',
          startAddingPerson: true,
          onLegacyProfileUpdated: (_) => legacyPartnerWasOverwritten = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ajouter une personne'), findsOneWidget);
    expect(find.text('Prénom'), findsOneWidget);
    expect(find.text('Date de naissance'), findsOneWidget);
    expect(find.text('Quel est son lien avec toi ?'), findsOneWidget);
    expect(find.text('Votre relation'), findsNothing);
    expect(find.text('Horaires ou planning de travail'), findsNothing);
    expect(find.text('Ce que Zelia doit savoir'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Samira');
    await tester.tap(find.text('Partenaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autre relation').last);
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(FilledButton, 'Ajouter');
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final state = await editor.load('account-a');
    expect(state!.model.persons, hasLength(2));
    expect(
      state.model.persons.any((person) => person.displayName == 'Samira'),
      isTrue,
    );
    expect(state.model.relationships, hasLength(1));
    expect(
        state.model.relationships.single.type, HumanRelationshipTypes.custom);
    expect(
      state.model.relationships.single.customType,
      'Autre',
    );
    expect(legacyPartnerWasOverwritten, isFalse);
  });

  testWidgets('un profil partenaire ouvre et conserve sa fiche complète',
      (tester) async {
    final editor = await _editor(
      extraPerson: HumanPerson(
        id: 'person-partner',
        accountScopeId: 'account-a',
        displayName: 'Alex',
        evidence: _confirmedEvidence,
      ),
      relationship: HumanRelationship(
        id: 'relationship-partner',
        accountScopeId: 'account-a',
        sourcePersonId: 'person-main',
        targetPersonId: 'person-partner',
        type: HumanRelationshipTypes.partner,
        evidence: _confirmedEvidence,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HumanProfileScreen(
          legacyProfile: _profile(),
          editService: editor,
          accountScopeId: 'account-a',
          personIdToEdit: 'person-partner',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Votre relation'), findsOneWidget);
    expect(find.text('Date de fiançailles'), findsNothing);
    expect(find.text('Date de mariage'), findsNothing);
    await tester.tap(find.text('En couple').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fiancée').last);
    await tester.pumpAndSettle();
    expect(find.text('Date de fiançailles'), findsOneWidget);
    expect(find.text('Date de mariage'), findsNothing);
    expect(find.text('Horaires ou planning de travail'), findsOneWidget);
    expect(find.text('Ce que Zelia doit savoir'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Horaires ou planning de travail'),
      'Lundi au vendredi, 8 h à 17 h',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Ce que Zelia doit savoir'),
      'Peut récupérer les enfants le mardi.',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Enregistrer');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final state = await editor.load('account-a');
    final partner = state!.model.personById('person-partner')!;
    expect(
      partner.customFields['workSchedule'],
      'Lundi au vendredi, 8 h à 17 h',
    );
    expect(
      partner.customFields['usefulNotes'],
      'Peut récupérer les enfants le mardi.',
    );
  });

  for (final size in _sizes) {
    testWidgets(
      'profil humain reste utilisable à ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: HumanProfileScreen(
              legacyProfile: _profile(),
              editService: await _editor(),
              accountScopeId: 'account-a',
            ),
          ),
        );
        await tester.pumpAndSettle();
        Object? exception;
        while ((exception = tester.takeException()) != null) {
          expect(exception.toString(), isEmpty);
        }
        expect(find.text('Mon organisation'), findsOneWidget);
      },
    );
  }

  testWidgets('texte agrandi conserve les sections principales',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: HumanProfileScreen(
            legacyProfile: _profile(),
            editService: await _editor(),
            accountScopeId: 'account-a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Personnes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Informations à confirmer'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Informations à confirmer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _confirmedEvidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

Future<HumanModelEditService> _editor({
  HumanPerson? extraPerson,
  HumanRelationship? relationship,
}) async {
  final model = HumanModel(
    accountScopeId: 'account-a',
    primaryPersonId: 'person-main',
    persons: [
      HumanPerson(
        id: 'person-main',
        accountScopeId: 'account-a',
        evidence: _confirmedEvidence,
      ),
      if (extraPerson != null) extraPerson,
    ],
    relationships: [if (relationship != null) relationship],
  );
  final local = HumanModelLocalRepository.withStore(_MemoryStore());
  await local.saveState(
    HumanModelLocalState(
      model: model,
      knownCloudRevision: 1,
      syncStatus: HumanModelSyncStatus.synced,
      lastMutationId: 'initial',
      migrationStatus: HumanModelMigrationStatus.complete,
    ),
  );
  return HumanModelEditService(
    humanModelService: HumanModelService(
      localRepository: local,
      cloudRepository: _Cloud(model),
    ),
  );
}

UserProfile _profile() => UserProfile(
      firstName: '',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );

final class _MemoryStore implements HumanModelKeyValueStore {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

final class _Cloud implements HumanModelCloudRepository {
  _Cloud(HumanModel model)
      : current = RevisionedHumanModel(
          model: model,
          modelRevision: 1,
          lastMutationId: 'initial',
          migrationVersion: 1,
          migrationStatus: HumanModelMigrationStatus.complete,
        );

  RevisionedHumanModel current;

  @override
  Future<RevisionedHumanModel?> read(String accountScopeId) async => current;

  @override
  Future<HumanModelWriteResult> createIfAbsent({
    required HumanModel model,
    required String mutationId,
    required String creationSource,
  }) async =>
      const HumanModelWriteResult.status(HumanModelWriteStatus.alreadyExists);

  @override
  Future<HumanModelWriteResult> update({
    required HumanModel model,
    required int expectedRevision,
    required String mutationId,
  }) async {
    current = RevisionedHumanModel(
      model: model,
      modelRevision: expectedRevision + 1,
      lastMutationId: mutationId,
      migrationVersion: 1,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
    return HumanModelWriteResult.success(current);
  }
}
