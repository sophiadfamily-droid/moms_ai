import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/human/human_model_persistence.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/human/human_model_cloud_repository.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';
import 'package:moms_ai/services/human/legacy_user_profile_reconciliation_service.dart';

import '../../fakes/fake_entity_id_generator.dart';

const _evidence = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

HumanModel _model(String scope, String personId, {String? name}) => HumanModel(
      accountScopeId: scope,
      primaryPersonId: personId,
      persons: [
        HumanPerson(
          id: personId,
          accountScopeId: scope,
          displayName: name,
          evidence: _evidence,
        ),
      ],
    );

UserProfile _profile({String firstName = 'Profil', String partnerName = ''}) =>
    UserProfile(
      firstName: firstName,
      familyStatus: '',
      workStatus: '',
      partnerName: partnerName,
      wantsNotifications: true,
      children: const [],
    );

final class _MemoryStore implements HumanModelKeyValueStore {
  final values = <String, String>{};
  bool failNextWrite = false;

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      return false;
    }
    values[key] = value;
    return true;
  }
}

final class _FakeCloudRepository implements HumanModelCloudRepository {
  RevisionedHumanModel? current;
  bool unavailable = false;

  @override
  Future<RevisionedHumanModel?> read(String accountScopeId) async {
    if (unavailable) {
      throw const HumanModelException('human_cloud_unavailable');
    }
    if (current != null && current!.model.accountScopeId != accountScopeId) {
      throw const HumanModelException('human_model_scope_mismatch');
    }
    return current;
  }

  @override
  Future<HumanModelWriteResult> createIfAbsent({
    required HumanModel model,
    required String mutationId,
    required String creationSource,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (unavailable) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.unavailable,
      );
    }
    if (current != null) {
      if (current!.lastMutationId == mutationId &&
          jsonEncode(current!.model.toJson()) == jsonEncode(model.toJson())) {
        return HumanModelWriteResult.success(current!);
      }
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.alreadyExists,
      );
    }
    current = RevisionedHumanModel(
      model: model,
      modelRevision: 1,
      lastMutationId: mutationId,
      migrationVersion: 1,
      migrationStatus: HumanModelMigrationStatus.complete,
    );
    return HumanModelWriteResult.success(current!);
  }

  @override
  Future<HumanModelWriteResult> update({
    required HumanModel model,
    required int expectedRevision,
    required String mutationId,
  }) async {
    if (unavailable) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.unavailable,
      );
    }
    final existing = current;
    if (existing == null) {
      return const HumanModelWriteResult.status(
        HumanModelWriteStatus.notFound,
      );
    }
    if (existing.lastMutationId == mutationId) {
      return jsonEncode(existing.model.toJson()) == jsonEncode(model.toJson())
          ? HumanModelWriteResult.success(existing)
          : const HumanModelWriteResult.status(
              HumanModelWriteStatus.invalidModel,
            );
    }
    if (existing.modelRevision != expectedRevision) {
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

void main() {
  group('enveloppe locale versionnée et rollback', () {
    test('lit le JSON HM.1 comme état localOnly rétrocompatible', () async {
      final store = _MemoryStore();
      final model = _model('account-a', 'person-a');
      store.values['human_model_v1:account-a'] = jsonEncode(model.toJson());
      final state = await HumanModelLocalRepository.withStore(store)
          .loadState('account-a');
      expect(state?.model.toJson(), model.toJson());
      expect(state?.syncStatus, HumanModelSyncStatus.localOnly);
      expect(state?.knownCloudRevision, isNull);
    });

    test('conserve une seule sauvegarde précédente et relit l’écriture',
        () async {
      final store = _MemoryStore();
      final repository = HumanModelLocalRepository.withStore(store);
      final first = HumanModelLocalState(
        model: _model('account-a', 'person-a', name: 'Version A'),
        knownCloudRevision: 1,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'mutation-a',
        migrationStatus: HumanModelMigrationStatus.complete,
      );
      final second = HumanModelLocalState(
        model: _model('account-a', 'person-a', name: 'Version B'),
        knownCloudRevision: 2,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'mutation-b',
        migrationStatus: HumanModelMigrationStatus.complete,
      );
      await repository.saveState(first);
      await repository.saveState(second);
      expect(store.values.keys.where((key) => key.contains('previous')),
          hasLength(1));
      store.values['human_model_v1:account-a'] = '{corrupt';
      final recovered = await repository.loadState('account-a');
      expect(recovered?.model.persons.single.displayName, 'Version A');
      expect(recovered?.syncStatus, HumanModelSyncStatus.corruptedLocal);
    });

    test('un échec de sauvegarde ne détruit pas la valeur courante', () async {
      final store = _MemoryStore();
      final repository = HumanModelLocalRepository.withStore(store);
      final first = HumanModelLocalState(
        model: _model('account-a', 'person-a', name: 'Version A'),
        syncStatus: HumanModelSyncStatus.localOnly,
        migrationStatus: HumanModelMigrationStatus.complete,
      );
      await repository.saveState(first);
      store.failNextWrite = true;
      await expectLater(
        repository.saveState(
          HumanModelLocalState(
            model: _model('account-a', 'person-a', name: 'Version B'),
            syncStatus: HumanModelSyncStatus.localOnly,
            migrationStatus: HumanModelMigrationStatus.complete,
          ),
        ),
        throwsA(isA<HumanModelException>()),
      );
      expect(
          (await repository.loadState('account-a'))
              ?.model
              .persons
              .single
              .displayName,
          'Version A');
    });
  });

  group('bootstrap cloud et concurrence', () {
    test('cloud existant gagne et restaure un appareil réinstallé', () async {
      final cloud = _FakeCloudRepository()
        ..current = RevisionedHumanModel(
          model: _model('account-a', 'person-cloud'),
          modelRevision: 4,
          lastMutationId: 'mutation-cloud',
          migrationVersion: 1,
          migrationStatus: HumanModelMigrationStatus.complete,
        );
      final store = _MemoryStore();
      final service = HumanModelService(
        localRepository: HumanModelLocalRepository.withStore(store),
        cloudRepository: cloud,
        idGenerator: FakeEntityIdGenerator(['reconcile-mutation']),
      );
      final result = await service.bootstrap(accountScopeId: 'account-a');
      expect(result.status, HumanModelBootstrapStatus.restoredFromCloud);
      expect(result.state?.knownCloudRevision, 4);
      expect(result.state?.model.primaryPersonId, 'person-cloud');
    });

    test('modèle HM.1 local conserve ses IDs lors du premier upload', () async {
      final cloud = _FakeCloudRepository();
      final store = _MemoryStore();
      final local = HumanModelLocalRepository.withStore(store);
      await local.save(_model('account-a', 'person-hm1'));
      final service = HumanModelService(
        localRepository: local,
        cloudRepository: cloud,
        idGenerator: FakeEntityIdGenerator(['mutation-upload']),
      );
      final result = await service.bootstrap(accountScopeId: 'account-a');
      expect(result.state?.model.primaryPersonId, 'person-hm1');
      expect(cloud.current?.model.primaryPersonId, 'person-hm1');
      expect(result.state?.knownCloudRevision, 1);
    });

    test('deux appareils migrants produisent un seul gagnant cloud', () async {
      final cloud = _FakeCloudRepository();
      final serviceA = HumanModelService(
        localRepository: HumanModelLocalRepository.withStore(_MemoryStore()),
        cloudRepository: cloud,
        idGenerator: FakeEntityIdGenerator(['person-a', 'mutation-a']),
      );
      final serviceB = HumanModelService(
        localRepository: HumanModelLocalRepository.withStore(_MemoryStore()),
        cloudRepository: cloud,
        idGenerator: FakeEntityIdGenerator(['person-b', 'mutation-b']),
      );
      final results = await Future.wait([
        serviceA.bootstrap(
          accountScopeId: 'account-a',
          legacyProfile: _profile(),
        ),
        serviceB.bootstrap(
          accountScopeId: 'account-a',
          legacyProfile: _profile(),
        ),
      ]);
      expect(cloud.current, isNotNull);
      expect(
        results.map((result) => result.state?.model.primaryPersonId).toSet(),
        {cloud.current!.model.primaryPersonId},
      );
      expect(cloud.current?.modelRevision, 1);
    });

    test('absence totale reste absente sans profil humain inventé', () async {
      final service = HumanModelService(
        localRepository: HumanModelLocalRepository.withStore(_MemoryStore()),
        cloudRepository: _FakeCloudRepository(),
      );
      final result = await service.bootstrap(accountScopeId: 'account-a');
      expect(result.status, HumanModelBootstrapStatus.absent);
      expect(result.state, isNull);
    });

    test('démarrage hors ligne conserve le dernier état local', () async {
      final cloud = _FakeCloudRepository()..unavailable = true;
      final local = HumanModelLocalRepository.withStore(_MemoryStore());
      await local.save(_model('account-a', 'person-local'));
      final service = HumanModelService(
        localRepository: local,
        cloudRepository: cloud,
      );
      final result = await service.bootstrap(accountScopeId: 'account-a');
      expect(result.status, HumanModelBootstrapStatus.localFallback);
      expect(result.state?.model.primaryPersonId, 'person-local');
      expect(result.state?.syncStatus, HumanModelSyncStatus.pendingUpload);
    });
  });

  group('écriture canonique révisionnée', () {
    test('N vers N+1 réussit et un retry mutationId reste idempotent',
        () async {
      final cloud = _FakeCloudRepository()
        ..current = RevisionedHumanModel(
          model: _model('account-a', 'person-a', name: 'Avant'),
          modelRevision: 1,
          lastMutationId: 'initial',
          migrationVersion: 1,
          migrationStatus: HumanModelMigrationStatus.complete,
        );
      final local = HumanModelLocalRepository.withStore(_MemoryStore());
      await local.saveState(HumanModelLocalState(
        model: cloud.current!.model,
        knownCloudRevision: 1,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'initial',
        migrationStatus: HumanModelMigrationStatus.complete,
      ));
      final service = HumanModelService(
        localRepository: local,
        cloudRepository: cloud,
      );
      final proposed = _model('account-a', 'person-a', name: 'Après');
      final first = await service.saveCanonical(
        proposed: proposed,
        expectedRevision: 1,
        mutationId: 'mutation-update',
      );
      final retry = await cloud.update(
        model: proposed,
        expectedRevision: 1,
        mutationId: 'mutation-update',
      );
      expect(first.value?.modelRevision, 2);
      expect(retry.value?.modelRevision, 2);
      expect(cloud.current?.modelRevision, 2);
    });

    test('révision obsolète garde une mutation locale en conflit', () async {
      final cloud = _FakeCloudRepository()
        ..current = RevisionedHumanModel(
          model: _model('account-a', 'person-a', name: 'Cloud'),
          modelRevision: 2,
          lastMutationId: 'remote',
          migrationVersion: 1,
          migrationStatus: HumanModelMigrationStatus.complete,
        );
      final local = HumanModelLocalRepository.withStore(_MemoryStore());
      await local.saveState(HumanModelLocalState(
        model: _model('account-a', 'person-a', name: 'Ancien'),
        knownCloudRevision: 1,
        syncStatus: HumanModelSyncStatus.synced,
        lastMutationId: 'initial',
        migrationStatus: HumanModelMigrationStatus.complete,
      ));
      final service = HumanModelService(
        localRepository: local,
        cloudRepository: cloud,
      );
      final result = await service.saveCanonical(
        proposed: _model('account-a', 'person-a', name: 'Local'),
        expectedRevision: 1,
        mutationId: 'local-mutation',
      );
      expect(result.status, HumanModelWriteStatus.revisionConflict);
      final state = await local.loadState('account-a');
      expect(state?.syncStatus, HumanModelSyncStatus.remoteChanged);
      expect(state?.pendingMutation?.mutationId, 'local-mutation');
      expect(cloud.current?.model.persons.single.displayName, 'Cloud');
    });
  });

  group('réconciliation legacy additive', () {
    test('nouveau partenaire muni ID stable garde le type partenaire', () {
      final current = HumanModel(
        accountScopeId: 'account-a',
        primaryPersonId: 'person-main',
        persons: [
          HumanPerson(
            id: 'person-main',
            accountScopeId: 'account-a',
            evidence: const HumanEvidence(
              source: HumanInformationSource.legacyProfile,
              confirmation: HumanConfirmationStatus.needsConfirmation,
            ),
          ),
        ],
        legacyProfile: {
          ..._profile().toJson(),
          'humanPersonId': 'person-main',
        },
      );
      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: current,
        legacyProfile: _profile(partnerName: 'Alex').copyWith(
          partnerHumanPersonId: 'person-partner-new',
        ),
        idGenerator: FakeEntityIdGenerator(['relation-partner-new']),
      );
      expect(result.status, LegacyHumanReconciliationStatus.additiveUpdate);
      expect(result.proposed.personById('person-partner-new'), isNotNull);
      expect(result.proposed.relationships.single.type,
          HumanRelationshipTypes.partner);
      expect(result.proposed.relationships.single.targetPersonId,
          'person-partner-new');
      expect(result.proposed.relationships.single.evidence.confirmation,
          HumanConfirmationStatus.needsConfirmation);
    });

    test('nouvel enfant muni ID stable est ajouté sans fusion par prénom', () {
      final current = HumanModel(
        accountScopeId: 'account-a',
        primaryPersonId: 'person-main',
        persons: [
          HumanPerson(
            id: 'person-main',
            accountScopeId: 'account-a',
            evidence: const HumanEvidence(
              source: HumanInformationSource.legacyProfile,
              confirmation: HumanConfirmationStatus.needsConfirmation,
            ),
          ),
        ],
        legacyProfile: {
          ..._profile().toJson(),
          'humanPersonId': 'person-main',
        },
      );
      final child = ChildProfile(
        humanPersonId: 'person-child-new',
        firstName: 'Camille',
        age: '',
        birthDate: '',
        gender: '',
        school: '',
        notes: '',
      );
      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: current,
        legacyProfile: _profile().copyWith(children: [child]),
        idGenerator: FakeEntityIdGenerator(['relation-child-new']),
      );
      expect(result.status, LegacyHumanReconciliationStatus.additiveUpdate);
      expect(result.proposed.personById('person-child-new'), isNotNull);
      expect(result.proposed.relationships.single.targetPersonId,
          'person-child-new');
      expect(result.proposed.relationships.single.evidence.confirmation,
          HumanConfirmationStatus.needsConfirmation);
    });

    test('renommage déterministe de la personne legacy non confirmée', () {
      final legacyEvidence = const HumanEvidence(
        source: HumanInformationSource.legacyProfile,
        confirmation: HumanConfirmationStatus.needsConfirmation,
      );
      final model = HumanModel(
        accountScopeId: 'account-a',
        primaryPersonId: 'person-main',
        persons: [
          HumanPerson(
            id: 'person-main',
            accountScopeId: 'account-a',
            displayName: 'Avant',
            evidence: legacyEvidence,
          ),
        ],
        legacyProfile: _profile(firstName: 'Avant').toJson()
          ..['humanPersonId'] = 'person-main'
          ..['unknownHistoricalField'] = 'preserved',
      );
      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: model,
        legacyProfile: _profile(firstName: 'Après'),
      );
      expect(result.status, LegacyHumanReconciliationStatus.additiveUpdate);
      expect(result.proposed.persons.single.id, 'person-main');
      expect(result.proposed.persons.single.displayName, 'Après');
      expect(
        result.proposed.legacyProfile['unknownHistoricalField'],
        'preserved',
      );
    });

    test('un changement partenaire ambigu exige confirmation', () {
      final current = HumanModel(
        accountScopeId: 'account-a',
        primaryPersonId: 'person-main',
        persons: [
          HumanPerson(
            id: 'person-main',
            accountScopeId: 'account-a',
            evidence: _evidence,
          ),
          HumanPerson(
            id: 'person-partner',
            accountScopeId: 'account-a',
            evidence: _evidence,
          ),
        ],
        relationships: [
          HumanRelationship(
            id: 'relation-partner',
            accountScopeId: 'account-a',
            sourcePersonId: 'person-main',
            targetPersonId: 'person-partner',
            type: HumanRelationshipTypes.partner,
            evidence: _evidence,
          ),
        ],
        legacyProfile: {
          ..._profile(partnerName: 'Alex').toJson(),
          'humanPersonId': 'person-main',
          'partnerHumanPersonId': 'person-partner',
        },
      );
      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: current,
        legacyProfile: _profile(partnerName: 'Sam'),
      );
      expect(result.status, LegacyHumanReconciliationStatus.needsConfirmation);
      expect(result.ambiguousFields, contains('partner'));
      expect(result.proposed.relationships.single.targetPersonId,
          'person-partner');
    });
  });
}
