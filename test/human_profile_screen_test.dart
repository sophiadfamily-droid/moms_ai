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
    expect(find.text('Nom d’affichage (facultatif)'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Mon organisation'), findsOneWidget);
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

Future<HumanModelEditService> _editor() async {
  final model = HumanModel(
    accountScopeId: 'account-a',
    primaryPersonId: 'person-main',
    persons: [
      HumanPerson(
        id: 'person-main',
        accountScopeId: 'account-a',
        evidence: const HumanEvidence(
          source: HumanInformationSource.explicitUserInput,
          confirmation: HumanConfirmationStatus.confirmed,
        ),
      ),
    ],
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
