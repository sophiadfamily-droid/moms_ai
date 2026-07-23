import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/human/human_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/human/human_model_local_repository.dart';
import 'package:moms_ai/services/human/human_model_service.dart';
import 'package:moms_ai/services/human/legacy_user_profile_human_adapter.dart';
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
