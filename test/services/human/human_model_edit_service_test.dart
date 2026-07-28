import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/human/human_model_persistence.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/human/human_model_cloud_repository.dart';
import 'package:moms_ai/services/human/human_model_edit_service.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';
import 'package:moms_ai/services/human/human_model_user_profile_projection_service.dart';
import 'package:moms_ai/services/human/legacy_user_profile_reconciliation_service.dart';

import '../../fakes/fake_entity_id_generator.dart';

const _evidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

void main() {
  group('frontière canonique HM.3', () {
    test('enregistre N vers N+1 et conserve le même ID au renommage', () async {
      final fixture = await _Fixture.create();
      final result = await fixture.editor.commit(
        accountScopeId: 'account-a',
        transform: (model) => model.copyWith(
          persons: [
            model.persons.single.copyWith(displayName: 'Nouveau nom'),
          ],
        ),
      );

      expect(result.status, HumanModelEditStatus.success);
      expect(result.state?.knownCloudRevision, 2);
      expect(result.state?.model.persons.single.id, 'person-main');
      expect(result.state?.model.persons.single.displayName, 'Nouveau nom');
    });

    test('révision obsolète retourne un conflit sans fausse réussite',
        () async {
      final fixture = await _Fixture.create();
      fixture.cloud.current = fixture.cloud.current!.copyWith(
        modelRevision: 2,
        model: fixture.cloud.current!.model.copyWith(
          persons: [
            fixture.cloud.current!.model.persons.single
                .copyWith(displayName: 'Cloud'),
          ],
        ),
      );
      final result = await fixture.editor.commit(
        accountScopeId: 'account-a',
        transform: (model) => model.copyWith(
          persons: [model.persons.single.copyWith(displayName: 'Local')],
        ),
      );

      expect(result.status, HumanModelEditStatus.revisionConflict);
      expect(result.draft?.persons.single.displayName, 'Local');
      expect(fixture.cloud.current?.model.persons.single.displayName, 'Cloud');
    });

    test('hors ligne conserve une unique mutation en attente', () async {
      final fixture = await _Fixture.create();
      fixture.cloud.unavailable = true;
      final result = await fixture.editor.commit(
        accountScopeId: 'account-a',
        transform: (model) => model.copyWith(
          persons: [model.persons.single.copyWith(displayName: 'Local')],
        ),
      );

      expect(result.status, HumanModelEditStatus.pendingSync);
      expect(result.state?.pendingMutation, isNotNull);
      expect(result.state?.syncStatus, HumanModelSyncStatus.pendingUpload);

      final second = await fixture.editor.commit(
        accountScopeId: 'account-a',
        transform: (model) => model.copyWith(
          persons: [model.persons.single.copyWith(displayName: 'Autre')],
        ),
      );
      expect(second.status, HumanModelEditStatus.needsConfirmation);
      expect(
        second.state?.pendingMutation?.proposed.persons.single.displayName,
        'Local',
      );
    });

    test('transformation invalide est refusée avant écriture', () async {
      final fixture = await _Fixture.create();
      final result = await fixture.editor.commit(
        accountScopeId: 'account-a',
        transform: (model) => HumanModel(
          accountScopeId: model.accountScopeId,
          primaryPersonId: model.primaryPersonId,
          persons: const [],
        ),
      );
      expect(result.status, HumanModelEditStatus.validationFailure);
      expect(fixture.cloud.updateCount, 0);
    });

    test('profil explicite écrit HumanModel avec relations confirmées',
        () async {
      final fixture = await _Fixture.create();
      final profile = _legacy().copyWith(
        firstName: 'Personne Test',
        birthDate: '01/02/1990',
        partnerHumanPersonId: 'person-alex',
        partnerName: 'Alex',
        children: [
          ChildProfile(
            humanPersonId: 'person-sam',
            firstName: 'Sam',
            age: '',
            birthDate: '05/06/2018',
            gender: '',
            school: '',
            notes: '',
          ),
        ],
      );

      final result = await fixture.editor.commitLegacyProfile(
        accountScopeId: 'account-a',
        profile: profile,
      );

      expect(result.status, HumanModelEditStatus.success);
      expect(
          result.state?.model.personById('person-alex')?.displayName, 'Alex');
      expect(result.state?.model.personById('person-sam')?.displayName, 'Sam');
      expect(
        result.state?.model.relationships.map((item) => item.type),
        containsAll([
          HumanRelationshipTypes.partner,
          HumanRelationshipTypes.child,
        ]),
      );
      expect(fixture.cloud.updateCount, 1);
    });
  });

  group('personnes universelles', () {
    test('personne sans relation et deux homonymes restent distincts', () {
      final editor = _factoryEditor();
      final first = editor.newPerson('account-a', displayName: 'Alex');
      final second = editor.newPerson('account-a', displayName: 'Alex');
      expect(first.id, isNot(second.id));
      expect(first.identityLink, isNull);
      expect(second.identityLink, isNull);
    });

    test('archivage conserve le lien Identity sans suppression', () {
      final person = HumanPerson(
        id: 'person-a',
        accountScopeId: 'account-a',
        identityLink: PersistedIdentityLink(
          entityId: 'identity-a',
          entityType: EntityType.person,
        ),
        evidence: _evidence,
      );
      final archived = person.copyWith(status: HumanPersonStatus.historical);
      expect(archived.identityLink?.entityId, 'identity-a');
      expect(archived.status, HumanPersonStatus.historical);
    });

    for (final status in [
      HumanPersonStatus.absent,
      HumanPersonStatus.deceased,
    ]) {
      test('statut ${status.name} est représentable', () {
        final person = _factoryEditor().newPerson('account-a');
        expect(person.copyWith(status: status).status, status);
      });
    }
  });

  group('relations, foyers, domiciles et responsabilités', () {
    for (final type in HumanRelationshipTypes.known) {
      test('relation $type est représentable sans inverse implicite', () {
        final relation = _factoryEditor().newRelationship(
          accountScopeId: 'account-a',
          sourcePersonId: 'person-a',
          targetPersonId: 'person-b',
          type: type,
          customType:
              type == HumanRelationshipTypes.custom ? 'Cousinage' : null,
        );
        expect(relation.type, type);
        expect(relation.reciprocal, isFalse);
      });
    }

    test('période future, terminée et invalide suivent le modèle canonique',
        () {
      final future = HumanValidityPeriod(
        validFrom: DateTime.utc(2030),
      );
      final ended = HumanValidityPeriod(
        validFrom: DateTime.utc(2020),
        validUntil: DateTime.utc(2021),
      );
      expect(future.isActiveAt(DateTime.utc(2029)), isFalse);
      expect(ended.isActiveAt(DateTime.utc(2022)), isFalse);
      expect(
        () => HumanValidityPeriod(
          validFrom: DateTime.utc(2022),
          validUntil: DateTime.utc(2021),
        ).validate(),
        throwsA(isA<HumanModelException>()),
      );
    });

    test('plusieurs foyers et appartenances simultanées sont valides', () {
      final editor = _factoryEditor();
      final first = editor.newHousehold('account-a', displayName: 'A');
      final second = editor.newHousehold(
        'account-a',
        displayName: 'B',
        status: HouseholdStatus.secondary,
      );
      final memberships = [
        editor.newMembership(
          accountScopeId: 'account-a',
          householdId: first.id,
          personId: 'person-main',
          role: HouseholdMembershipRoles.alternatingMember,
        ),
        editor.newMembership(
          accountScopeId: 'account-a',
          householdId: second.id,
          personId: 'person-main',
          role: HouseholdMembershipRoles.temporaryMember,
        ),
      ];
      final model = _model().copyWith(
        households: [first, second],
        memberships: memberships,
      );
      expect(model.households, hasLength(2));
      expect(model.memberships, hasLength(2));
    });

    test('domicile sans adresse complète et associations multiples', () {
      final residence = _factoryEditor().newResidence(
        accountScopeId: 'account-a',
        label: 'Lieu de vie',
        personIds: const ['person-main'],
      );
      expect(residence.placeEntityId, isNull);
      expect(residence.personIds, ['person-main']);
    });

    for (final type in _responsibilityTypesForTest) {
      test('responsabilité $type reste déclarative', () {
        final responsibility = _factoryEditor().newResponsibility(
          accountScopeId: 'account-a',
          responsiblePersonId: 'person-a',
          subjectPersonId: 'person-b',
          type: type,
          customType:
              type == HumanResponsibilityTypes.custom ? 'Organisation' : null,
        );
        expect(responsibility.type, type);
        expect(
          responsibility.evidence.source,
          HumanInformationSource.explicitUserInput,
        );
      });
    }
  });

  group('réconciliation et projection legacy', () {
    test('rejet persistant empêche la même proposition de réapparaître',
        () async {
      final source = _model().copyWith(
        legacyProfile: _legacy().toJson(),
      );
      final initial = const LegacyUserProfileReconciliationService().reconcile(
        current: source,
        legacyProfile: _legacy(partnerName: 'Proposition'),
      );
      final marker = HumanLegacyReconciliationMarker.forModel(initial.proposed);
      final current = source.copyWith(
        legacyProfile: {
          ...initial.proposed.legacyProfile,
          HumanLegacyReconciliationMarker.field: marker,
        },
      );
      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: current,
        legacyProfile: _legacy(partnerName: 'Proposition'),
      );
      expect(result.status, LegacyHumanReconciliationStatus.unchanged);
    });

    test('projection principale est déterministe et conserve le legacy', () {
      final legacy = _legacy().copyWith(
        legacyExtensions: const {'unknown': 'kept'},
      );
      final model = _model().copyWith(
        persons: [
          _model().persons.single.copyWith(displayName: 'Nom canonique'),
        ],
      );
      final projected = const HumanModelUserProfileProjectionService().project(
        model: model,
        legacy: legacy,
      );
      expect(projected.firstName, 'Nom canonique');
      expect(projected.legacyExtensions['unknown'], 'kept');
    });

    test('partenaire ambigu et enfant sans mapping ne sont pas inventés', () {
      final legacy = _legacy(partnerName: 'Ancien');
      final projected = const HumanModelUserProfileProjectionService().project(
        model: _model(),
        legacy: legacy,
      );
      expect(projected.partnerName, 'Ancien');
      expect(projected.children, isEmpty);
    });
  });
}

HumanModelEditService _factoryEditor() => HumanModelEditService(
      humanModelService: HumanModelService(
        localRepository: HumanModelLocalRepository.withStore(_MemoryStore()),
      ),
      idGenerator: FakeEntityIdGenerator(
        List.generate(100, (index) => 'generated-$index'),
      ),
    );

HumanModel _model() => HumanModel(
      accountScopeId: 'account-a',
      primaryPersonId: 'person-main',
      persons: [
        HumanPerson(
          id: 'person-main',
          accountScopeId: 'account-a',
          displayName: 'Principal',
          evidence: _evidence,
        ),
      ],
    );

UserProfile _legacy({String partnerName = ''}) => UserProfile(
      humanPersonId: 'person-main',
      firstName: 'Legacy',
      familyStatus: '',
      workStatus: '',
      partnerName: partnerName,
      wantsNotifications: true,
      children: const [],
    );

const _responsibilityTypesForTest = [
  HumanResponsibilityTypes.parental,
  HumanResponsibilityTypes.custody,
  HumanResponsibilityTypes.accompaniment,
  HumanResponsibilityTypes.care,
  HumanResponsibilityTypes.dailyAssistance,
  HumanResponsibilityTypes.transport,
  HumanResponsibilityTypes.emergency,
  HumanResponsibilityTypes.temporary,
  HumanResponsibilityTypes.delegation,
  HumanResponsibilityTypes.custom,
];

final class _Fixture {
  _Fixture(this.editor, this.cloud);

  final HumanModelEditService editor;
  final _Cloud cloud;

  static Future<_Fixture> create() async {
    final local = HumanModelLocalRepository.withStore(_MemoryStore());
    final cloud = _Cloud(
      RevisionedHumanModel(
        model: _model(),
        modelRevision: 1,
        lastMutationId: 'initial',
        migrationVersion: 1,
        migrationStatus: HumanModelMigrationStatus.complete,
      ),
    );
    await local.saveState(
      HumanModelLocalState(
        model: _model(),
        knownCloudRevision: 1,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'initial',
        migrationStatus: HumanModelMigrationStatus.complete,
      ),
    );
    return _Fixture(
      HumanModelEditService(
        humanModelService: HumanModelService(
          localRepository: local,
          cloudRepository: cloud,
        ),
        idGenerator: FakeEntityIdGenerator(
          List.generate(20, (index) => 'mutation-$index'),
        ),
      ),
      cloud,
    );
  }
}

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
  _Cloud(this.current);

  RevisionedHumanModel? current;
  bool unavailable = false;
  int updateCount = 0;

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
    updateCount++;
    if (unavailable) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.unavailable,
      );
    }
    if (current?.modelRevision != expectedRevision) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.revisionConflict,
      );
    }
    current = RevisionedHumanModel(
      model: model,
      modelRevision: expectedRevision + 1,
      lastMutationId: mutationId,
      migrationVersion: 1,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
    return HumanModelWriteResult.success(current!);
  }
}

extension on RevisionedHumanModel {
  RevisionedHumanModel copyWith({
    HumanModel? model,
    int? modelRevision,
  }) =>
      RevisionedHumanModel(
        model: model ?? this.model,
        modelRevision: modelRevision ?? this.modelRevision,
        lastMutationId: lastMutationId,
        migrationVersion: migrationVersion,
        migrationStatus: migrationStatus,
      );
}
