import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';
import 'package:moms_ai/services/human/human_profile_facts_service.dart';
import 'package:moms_ai/services/human/legacy_user_profile_human_adapter.dart';
import 'package:moms_ai/services/human/legacy_user_profile_reconciliation_service.dart';
import 'package:moms_ai/services/human/human_model_user_profile_projection_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../fakes/fake_entity_id_generator.dart';

UserProfile _profile({
  String firstName = 'Personne principale',
  String partnerName = '',
  String familyStatus = '',
  String relationshipStatus = '',
  List<ChildProfile> children = const [],
}) {
  return UserProfile(
    firstName: firstName,
    familyStatus: familyStatus,
    workStatus: 'activité variable',
    partnerName: partnerName,
    wantsNotifications: true,
    children: children,
    relationshipStatus: relationshipStatus,
    medicalNotes: 'donnée sensible héritée',
    emergencyContactName: 'contact hérité',
  );
}

ChildProfile _child(String name, {String birthDate = ''}) {
  return ChildProfile(
    firstName: name,
    age: '',
    birthDate: birthDate,
    gender: '',
    school: 'école héritée',
    notes: '',
    medicalNotes: 'donnée enfant héritée',
    schoolTimeRanges: [
      TimeRangeModel(startTime: '08:30', endTime: '16:30'),
    ],
  );
}

FakeEntityIdGenerator _ids() => FakeEntityIdGenerator([
      'person-primary',
      'person-partner',
      'relation-partner',
      'person-child-a',
      'relation-child-a',
      'person-child-b',
      'relation-child-b',
    ]);

void main() {
  group('adaptateur legacy prudent', () {
    test('IDs techniques legacy sont additifs et réutilisés', () {
      final profile = _profile(
        partnerName: 'Alex',
        children: [_child('Lou')],
      ).copyWith(
        humanPersonId: 'person-existing-main',
        partnerHumanPersonId: 'person-existing-partner',
        children: [
          _child('Lou').copyWith(humanPersonId: 'person-existing-child'),
        ],
      );
      final model = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: {
          ...profile.toJson(),
          'unknownLegacyValue': 'kept',
        },
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator([
          'relation-partner',
          'relation-child',
        ]),
      );
      expect(model.primaryPersonId, 'person-existing-main');
      expect(model.personById('person-existing-partner'), isNotNull);
      expect(model.personById('person-existing-child'), isNotNull);
      expect(model.legacyProfile['unknownLegacyValue'], 'kept');
      final children = model.legacyProfile['children'] as List;
      expect(
        (children.single as Map)['humanPersonId'],
        'person-existing-child',
      );
    });

    test('profil minimal crée seulement la personne principale stable', () {
      final profile = _profile(firstName: '');
      final model = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: profile.toJson(),
        accountScopeId: 'account-a',
        idGenerator: _ids(),
      );
      expect(model.persons, hasLength(1));
      expect(model.primaryPersonId, 'person-primary');
      expect(model.households, isEmpty);
      expect(model.responsibilities, isEmpty);
      expect(model.persons.single.identityLink, isNull);
    });

    test('partnerName produit une relation partenaire non genrée à confirmer',
        () {
      final profile = _profile(
        partnerName: 'Alex',
        familyStatus: 'valeur ambiguë',
        relationshipStatus: 'situation compliquée',
      );
      final model = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: {
          ...profile.toJson(),
          'legacyUnknownField': 'préservé',
        },
        accountScopeId: 'account-a',
        idGenerator: _ids(),
      );
      expect(model.persons, hasLength(2));
      expect(model.relationships.single.type, HumanRelationshipTypes.partner);
      expect(model.relationships.single.evidence.confirmation,
          HumanConfirmationStatus.needsConfirmation);
      expect(model.households, isEmpty);
      expect(model.legacyProfile['familyStatus'], 'valeur ambiguë');
      expect(model.legacyProfile['relationshipStatus'], 'situation compliquée');
      expect(model.legacyProfile['legacyUnknownField'], 'préservé');
    });

    test('plusieurs enfants restent distincts sans second parent ni domicile',
        () {
      final profile = _profile(
        children: [
          _child('Camille', birthDate: '2017-03-01'),
          _child('Camille', birthDate: '2019-05-02'),
        ],
      );
      final model = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: profile.toJson(),
        accountScopeId: 'account-a',
        idGenerator: _ids(),
      );
      expect(model.persons, hasLength(3));
      expect(model.relationships, hasLength(2));
      expect(
        model.relationships.every(
          (relation) => relation.type == HumanRelationshipTypes.child,
        ),
        isTrue,
      );
      expect(model.households, isEmpty);
      expect(model.residences, isEmpty);
      expect(model.responsibilities, isEmpty);
      expect(model.legacyProfile.toString(), contains('schoolTimeRanges'));
      expect(model.legacyProfile.toString(), contains('medicalNotes'));
    });

    test('aucune Identity ne naît d’un prénom ambigu ou homonyme', () {
      final profile = _profile(
        partnerName: 'Alex',
        children: [_child('Alex')],
      );
      final model = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: profile.toJson(),
        accountScopeId: 'account-a',
        idGenerator: _ids(),
      );
      expect(model.persons.map((person) => person.id).toSet(),
          hasLength(model.persons.length));
      expect(
          model.persons.every((person) => person.identityLink == null), isTrue);
    });

    test(
        'édition explicite persiste personnes, dates et relations puis restaure le profil',
        () {
      final initial = _profile(firstName: 'Initial').copyWith(
        humanPersonId: 'person-main',
      );
      final current = const LegacyUserProfileHumanAdapter().migrate(
        profile: initial,
        legacyProfile: initial.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator(['unused']),
      );
      final edited = initial.copyWith(
        firstName: 'Personne Test',
        birthDate: '01/02/1990',
        familyStatus: 'Je vis en couple',
        workStatus: 'Je suis salariée',
        partnerHumanPersonId: 'person-alex',
        partnerName: 'Alex',
        partnerBirthDate: '03/04/1991',
        relationshipStatus: 'Mariée',
        marriageDate: '12/08/2020',
        children: [
          _child('Sam', birthDate: '05/06/2018')
              .copyWith(humanPersonId: 'person-sam'),
        ],
      );
      final updated = const LegacyUserProfileReconciliationService()
          .applyExplicitProfileEdit(
        current: current,
        profile: edited,
        idGenerator: FakeEntityIdGenerator(['relation-alex', 'relation-sam']),
      );

      expect(updated.personById('person-main')?.displayName, 'Personne Test');
      expect(
        updated.personById('person-main')?.customFields,
        containsPair('familyStatus', 'Je vis en couple'),
      );
      expect(
        updated.personById('person-main')?.customFields,
        containsPair('workStatus', 'Je suis salariée'),
      );
      expect(updated.personById('person-alex')?.displayName, 'Alex');
      expect(updated.personById('person-sam')?.displayName, 'Sam');
      expect(
        updated.personById('person-sam')?.customFields['birthDate'],
        '05/06/2018',
      );
      expect(
        updated.relationships.map((relation) => relation.type),
        containsAll([
          HumanRelationshipTypes.partner,
          HumanRelationshipTypes.child,
        ]),
      );
      final partnerRelationship = updated.relationships.singleWhere(
        (relation) => relation.targetPersonId == 'person-alex',
      );
      expect(
        partnerRelationship.structuredNotes,
        containsPair('relationshipStatus', 'Mariée'),
      );
      expect(
        partnerRelationship.structuredNotes,
        containsPair('marriageDate', '12/08/2020'),
      );
      expect(
        updated.relationships.every(
          (relation) =>
              relation.evidence.source ==
                  HumanInformationSource.explicitUserInput &&
              relation.evidence.confirmation ==
                  HumanConfirmationStatus.confirmed,
        ),
        isTrue,
      );

      final cloudProfileWithoutHumanFields = UserProfile(
        firstName: '',
        familyStatus: '',
        workStatus: 'activité variable',
        partnerName: '',
        wantsNotifications: true,
        children: const [],
      );
      final restored = const HumanModelUserProfileProjectionService().project(
        model: updated,
        legacy: cloudProfileWithoutHumanFields,
      );
      expect(restored.firstName, 'Personne Test');
      expect(restored.birthDate, '01/02/1990');
      expect(restored.familyStatus, 'Je vis en couple');
      expect(restored.workStatus, 'Je suis salariée');
      expect(restored.partnerName, 'Alex');
      expect(restored.partnerBirthDate, '03/04/1991');
      expect(restored.relationshipStatus, 'Mariée');
      expect(restored.marriageDate, '12/08/2020');
      expect(restored.children.single.firstName, 'Sam');
      expect(restored.children.single.birthDate, '05/06/2018');
      expect(restored.children.single.humanPersonId, 'person-sam');
    });

    test('la projection retire les personnes rendues historiques', () {
      final profile =
          _profile(partnerName: 'Alex', children: [_child('Sam')]).copyWith(
        humanPersonId: 'person-main',
        partnerHumanPersonId: 'person-alex',
        partnerBirthDate: '03/04/1991',
        relationshipStatus: 'Mariée',
        children: [
          _child('Sam').copyWith(humanPersonId: 'person-sam'),
        ],
      );
      final migrated = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: profile.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator(['relation-alex', 'relation-sam']),
      );
      final historical = migrated.copyWith(
        persons: migrated.persons
            .map(
              (person) => person.id == 'person-main'
                  ? person
                  : person.copyWith(status: HumanPersonStatus.historical),
            )
            .toList(),
        relationships: migrated.relationships
            .map(
              (relation) => relation.copyWith(
                status: HumanRecordStatus.historical,
              ),
            )
            .toList(),
      );

      final restored = const HumanModelUserProfileProjectionService().project(
        model: historical,
        legacy: profile,
      );

      expect(restored.partnerHumanPersonId, isEmpty);
      expect(restored.partnerName, isEmpty);
      expect(restored.partnerBirthDate, isEmpty);
      expect(restored.relationshipStatus, isEmpty);
      expect(restored.children, isEmpty);
    });

    test('récupère les détails du couple déjà présents dans un ancien profil',
        () {
      final profile = _profile(
        partnerName: 'Alex',
        relationshipStatus: 'Fiancée',
      ).copyWith(
        humanPersonId: 'person-main',
        partnerHumanPersonId: 'person-alex',
        engagementDate: '04/05/2024',
      );
      final migrated = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: profile.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator(['relation-alex']),
      );
      final oldModel = migrated.copyWith(
        relationships: [
          migrated.relationships.single.copyWith(structuredNotes: const {}),
        ],
      );

      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: oldModel,
        legacyProfile: profile,
      );

      expect(
        result.proposed.relationships.single.structuredNotes,
        containsPair('relationshipStatus', 'Fiancée'),
      );
      expect(
        result.proposed.relationships.single.structuredNotes,
        containsPair('engagementDate', '04/05/2024'),
      );
      expect(
        result.proposed.personById('person-main')?.customFields,
        containsPair('workStatus', 'activité variable'),
      );
      expect(
        result.proposed.personById('person-alex')?.customFields,
        isNot(contains('usefulNotes')),
      );
    });

    test('migre les faits durables de chaque personne avec leur provenance',
        () {
      final child = _child('Lou', birthDate: '2018-03-04').copyWith(
        humanPersonId: 'person-lou',
        gender: 'Fille',
        className: 'CE2',
        allergies: 'Arachides',
        doctor: 'Docteure Martin',
      );
      final profile = _profile(partnerName: 'Alex', children: [child]).copyWith(
        humanPersonId: 'person-main',
        partnerHumanPersonId: 'person-alex',
        city: 'Trondheim',
        homeAddress: '1 rue du Test',
        workAddress: '2 avenue du Travail',
        vehicleInfo: 'Voiture familiale',
        allergies: 'Pollen',
        doctorName: 'Docteure Dupont',
        emergencyContactName: 'Sam',
        partnerNotes: 'Travaille parfois de nuit',
        partnerWorkSchedule: 'Planning variable',
      );

      final model = const LegacyUserProfileHumanAdapter().migrate(
        profile: profile,
        legacyProfile: profile.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator([
          'relation-alex',
          'relation-lou',
        ]),
      );

      final primary = model.personById('person-main')!;
      final partner = model.personById('person-alex')!;
      final lou = model.personById('person-lou')!;
      expect(primary.customFields, containsPair('city', 'Trondheim'));
      expect(
          primary.customFields, containsPair('homeAddress', '1 rue du Test'));
      expect(primary.customFields, containsPair('allergies', 'Pollen'));
      expect(partner.customFields,
          containsPair('usefulNotes', 'Travaille parfois de nuit'));
      expect(lou.customFields, containsPair('className', 'CE2'));
      expect(lou.customFields, containsPair('allergies', 'Arachides'));
      expect(
        HumanProfileFactsV1.evidenceFor(primary, 'city'),
        isA<HumanEvidence>()
            .having((value) => value.source, 'source',
                HumanInformationSource.legacyProfile)
            .having((value) => value.confirmation, 'confirmation',
                HumanConfirmationStatus.needsConfirmation),
      );

      final restored = const HumanModelUserProfileProjectionService().project(
        model: model,
        legacy: _profile(),
      );
      expect(restored.city, 'Trondheim');
      expect(restored.homeAddress, '1 rue du Test');
      expect(restored.partnerNotes, 'Travaille parfois de nuit');
      expect(restored.partnerWorkSchedule, 'Planning variable');
      expect(restored.children.single.className, 'CE2');
      expect(restored.children.single.allergies, 'Arachides');
    });

    test('une édition explicite remplace le fait et confirme sa provenance',
        () {
      final initial = _profile().copyWith(
        humanPersonId: 'person-main',
        city: 'Ancienne ville',
        allergies: 'Ancienne allergie',
      );
      final current = const LegacyUserProfileHumanAdapter().migrate(
        profile: initial,
        legacyProfile: initial.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator(const []),
      );
      final edited = initial.copyWith(
        city: 'Nouvelle ville',
        allergies: '',
      );

      final updated = const LegacyUserProfileReconciliationService()
          .applyExplicitProfileEdit(
        current: current,
        profile: edited,
        idGenerator: FakeEntityIdGenerator(const []),
      );
      final primary = updated.personById('person-main')!;
      expect(primary.customFields, containsPair('city', 'Nouvelle ville'));
      expect(primary.customFields, isNot(contains('allergies')));
      expect(HumanProfileFactsV1.evidenceFor(primary, 'allergies'), isNull);
      expect(
        HumanProfileFactsV1.evidenceFor(primary, 'city'),
        isA<HumanEvidence>()
            .having((value) => value.source, 'source',
                HumanInformationSource.explicitUserInput)
            .having((value) => value.confirmation, 'confirmation',
                HumanConfirmationStatus.confirmed),
      );
    });

    test(
        'une ancienne copie du profil ne remplace pas un fait confirmé ensuite',
        () {
      final initial = _profile().copyWith(
        humanPersonId: 'person-main',
        city: 'Ancienne ville',
      );
      final migrated = const LegacyUserProfileHumanAdapter().migrate(
        profile: initial,
        legacyProfile: initial.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator(const []),
      );
      final confirmed = const LegacyUserProfileReconciliationService()
          .applyExplicitProfileEdit(
        current: migrated,
        profile: initial.copyWith(city: 'Ville confirmée'),
        idGenerator: FakeEntityIdGenerator(const []),
      );

      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: confirmed,
        legacyProfile: initial,
        rawLegacyProfile: initial.toJson(),
      );

      final primary = result.proposed.personById('person-main')!;
      expect(primary.customFields, containsPair('city', 'Ville confirmée'));
      expect(
        HumanProfileFactsV1.evidenceFor(primary, 'city'),
        isA<HumanEvidence>()
            .having((value) => value.source, 'source',
                HumanInformationSource.explicitUserInput)
            .having((value) => value.confirmation, 'confirmation',
                HumanConfirmationStatus.confirmed),
      );
    });

    test('une personne ajoutée par réconciliation reçoit aussi ses faits', () {
      final initial = _profile().copyWith(humanPersonId: 'person-main');
      final migrated = const LegacyUserProfileHumanAdapter().migrate(
        profile: initial,
        legacyProfile: initial.toJson(),
        accountScopeId: 'account-a',
        idGenerator: FakeEntityIdGenerator(const []),
      );
      final partnerAndChild = initial.copyWith(
        partnerHumanPersonId: 'person-alex',
        partnerName: 'Alex',
        partnerNotes: 'Travail de nuit',
        children: [
          _child('Lou').copyWith(
            humanPersonId: 'person-lou',
            className: 'CE2',
          ),
        ],
      );

      final result = const LegacyUserProfileReconciliationService().reconcile(
        current: migrated,
        legacyProfile: partnerAndChild,
        idGenerator: FakeEntityIdGenerator(['relation-alex', 'relation-lou']),
      );

      expect(
        result.proposed.personById('person-alex')?.customFields,
        containsPair('usefulNotes', 'Travail de nuit'),
      );
      expect(
        result.proposed.personById('person-lou')?.customFields,
        containsPair('className', 'CE2'),
      );
    });

    test('tous les champs V1 connus ont une destination de migration', () {
      final fields = _profile().toJson().keys.toSet();
      final classified = <String>{
        ...HumanProfileFactsV1.coreHumanFields,
        ...HumanProfileFactsV1.relationshipFields,
        ...HumanProfileFactsV1.settingsFields,
        ...HumanProfileFactsV1.memoryFields,
        ...HumanProfileFactsV1.scheduleFields,
      };
      expect(fields.difference(classified), isEmpty);
    });
  });

  group('stockage et migration locale', () {
    late SharedPreferences preferences;
    late HumanModelLocalRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_profile': jsonEncode(_profile().toJson()),
      });
      preferences = await SharedPreferences.getInstance();
      repository = HumanModelLocalRepository(preferences);
    });

    test('migration répétée et redémarrage ne dupliquent aucun identifiant',
        () async {
      final profile = _profile(partnerName: 'Alex', children: [_child('Lou')]);
      final generator = _ids();
      final service = HumanModelService(
        repository: repository,
        idGenerator: generator,
      );
      final first = await service.loadOrMigrate(
        accountScopeId: 'account-a',
        legacyProfile: profile,
      );
      final second = await service.loadOrMigrate(
        accountScopeId: 'account-a',
        legacyProfile: profile.copyWith(firstName: 'Nouveau prénom'),
      );
      final afterRestart =
          await HumanModelLocalRepository(preferences).load('account-a');
      expect(second.toJson(), first.toJson());
      expect(afterRestart?.toJson(), first.toJson());
      expect(generator.callCount, 5);
      expect(afterRestart?.primaryPersonId, 'person-primary');
    });

    test('les comptes sont isolés par clé et scope', () async {
      final serviceA = HumanModelService(
        repository: repository,
        idGenerator: FakeEntityIdGenerator(['person-a']),
      );
      final serviceB = HumanModelService(
        repository: repository,
        idGenerator: FakeEntityIdGenerator(['person-b']),
      );
      final a = await serviceA.loadOrMigrate(
        accountScopeId: 'account-a',
        legacyProfile: _profile(),
      );
      final b = await serviceB.loadOrMigrate(
        accountScopeId: 'account-b',
        legacyProfile: _profile(),
      );
      expect(a.primaryPersonId, isNot(b.primaryPersonId));
      expect(await repository.load('account-a'), isNotNull);
      expect(await repository.load('account-b'), isNotNull);
    });

    test('JSON corrompu échoue sans effacer ancien profil', () async {
      await preferences.setString(
        '${HumanModelLocalRepository.storageKeyPrefix}:account-a',
        '{"schemaVersion":1,"persons":',
      );
      expect(
        () => repository.load('account-a'),
        throwsA(
          isA<HumanModelException>().having(
            (error) => error.code,
            'code',
            'invalid_human_model_json',
          ),
        ),
      );
      expect(preferences.getString('user_profile'), isNotNull);
    });

    test('scope stocké différent est refusé explicitement', () async {
      final foreign = HumanModel(
        accountScopeId: 'account-b',
        primaryPersonId: 'person-b',
        persons: [
          HumanPerson(
            id: 'person-b',
            accountScopeId: 'account-b',
            evidence: const HumanEvidence(
              source: HumanInformationSource.explicitUserInput,
              confirmation: HumanConfirmationStatus.confirmed,
            ),
          ),
        ],
      );
      await preferences.setString(
        '${HumanModelLocalRepository.storageKeyPrefix}:account-a',
        jsonEncode(foreign.toJson()),
      );
      expect(
        () => repository.load('account-a'),
        throwsA(
          isA<HumanModelException>().having(
            (error) => error.code,
            'code',
            'human_model_scope_mismatch',
          ),
        ),
      );
    });

    test('projection du service reste minimale et non personnelle', () async {
      final service = HumanModelService(
        repository: repository,
        idGenerator: FakeEntityIdGenerator(['person-primary']),
      );
      final model = await service.loadOrMigrate(
        accountScopeId: 'account-a',
        legacyProfile: _profile(),
      );
      final projection = service.project(model, DateTime.utc(2026));
      expect(projection.toJson(), {
        'schemaVersion': 1,
        'personCount': 1,
        'currentHouseholdCount': 0,
        'currentResponsibilityCount': 0,
      });
      expect(projection.toJson().keys,
          isNot(contains(anyOf('name', 'profile', 'uid'))));
    });
  });
}
