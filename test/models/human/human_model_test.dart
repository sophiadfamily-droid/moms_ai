import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/models/human/human_model.dart';

const _scope = 'account-test';
const _confirmed = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

HumanPerson _person(
  String id, {
  HumanPersonStatus status = HumanPersonStatus.active,
  PersistedIdentityLink? identityLink,
}) {
  return HumanPerson(
    id: id,
    accountScopeId: _scope,
    status: status,
    identityLink: identityLink,
    evidence: _confirmed,
  );
}

HumanModel _model({
  List<HumanPerson>? persons,
  List<HumanRelationship> relationships = const [],
  List<HumanHousehold> households = const [],
  List<HumanResidence> residences = const [],
  List<HumanHouseholdMembership> memberships = const [],
  List<HumanResponsibility> responsibilities = const [],
  Map<String, Object?> unknownFields = const {},
}) {
  return HumanModel(
    accountScopeId: _scope,
    primaryPersonId: 'person-main',
    persons: persons ?? [_person('person-main')],
    relationships: relationships,
    households: households,
    residences: residences,
    memberships: memberships,
    responsibilities: responsibilities,
    unknownFields: unknownFields,
  );
}

HumanRelationship _relation(
  String id,
  String target,
  String type, {
  String source = 'person-main',
  String? customType,
  HumanRecordStatus status = HumanRecordStatus.active,
  HumanValidityPeriod validity = const HumanValidityPeriod(),
}) {
  return HumanRelationship(
    id: id,
    accountScopeId: _scope,
    sourcePersonId: source,
    targetPersonId: target,
    type: type,
    customType: customType,
    status: status,
    validity: validity,
    evidence: _confirmed,
  );
}

void main() {
  group('structures humaines universelles', () {
    test('catalogues relationnels et responsabilités couvrent HM.1', () {
      expect(
        HumanRelationshipTypes.known,
        containsAll({
          'partner',
          'spouse',
          'formerPartner',
          'parent',
          'child',
          'sibling',
          'halfSibling',
          'stepParent',
          'stepChild',
          'grandParent',
          'grandChild',
          'guardian',
          'responsiblePerson',
          'caregiver',
          'caredForPerson',
          'fosterFamily',
          'fosterChild',
          'closePerson',
          'custom',
        }),
      );
      expect(
        {
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
        },
        hasLength(10),
      );
    });

    test('personne seule sans foyer déclaré', () {
      final model = _model();
      expect(model.persons, hasLength(1));
      expect(model.households, isEmpty);
    });

    test('couples mariés, non mariés et de même sexe sans genre imposé', () {
      final persons = [
        _person('person-main'),
        _person('person-partner-a'),
        _person('person-partner-b'),
      ];
      final model = _model(
        persons: persons,
        relationships: [
          _relation('relation-spouse', 'person-partner-a',
              HumanRelationshipTypes.spouse),
          _relation('relation-partner', 'person-partner-b',
              HumanRelationshipTypes.partner),
        ],
      );
      expect(model.relationships.map((item) => item.type),
          containsAll(['spouse', 'partner']));
      expect(
          model.persons
              .every((person) => !person.toJson().containsKey('gender')),
          isTrue);
    });

    test('parents séparés, garde alternée et enfant dans deux foyers', () {
      final persons = [
        _person('person-main'),
        _person('person-parent-2'),
        _person('person-child'),
      ];
      final households = [
        HumanHousehold(
          id: 'household-a',
          accountScopeId: _scope,
          evidence: _confirmed,
        ),
        HumanHousehold(
          id: 'household-b',
          accountScopeId: _scope,
          status: HouseholdStatus.secondary,
          evidence: _confirmed,
        ),
      ];
      final memberships = [
        for (final household in households)
          HumanHouseholdMembership(
            id: 'membership-${household.id}',
            accountScopeId: _scope,
            householdId: household.id,
            personId: 'person-child',
            role: HouseholdMembershipRoles.alternatingMember,
            evidence: _confirmed,
          ),
      ];
      final model = _model(
        persons: persons,
        relationships: [
          _relation(
              'relation-child-1', 'person-child', HumanRelationshipTypes.child),
          _relation(
            'relation-child-2',
            'person-child',
            HumanRelationshipTypes.child,
            source: 'person-parent-2',
          ),
        ],
        households: households,
        memberships: memberships,
      );
      expect(model.memberships, hasLength(2));
      expect(model.households, hasLength(2));
    });

    test('famille recomposée, demi-fratrie et beau-parent', () {
      final model = _model(
        persons: [
          _person('person-main'),
          _person('person-child'),
          _person('person-half-sibling'),
          _person('person-step-parent'),
        ],
        relationships: [
          _relation('relation-half', 'person-half-sibling',
              HumanRelationshipTypes.halfSibling,
              source: 'person-child'),
          _relation('relation-step', 'person-step-parent',
              HumanRelationshipTypes.stepParent,
              source: 'person-child'),
        ],
      );
      expect(model.relationships, hasLength(2));
    });

    test('adoption et famille accueil restent explicites sans règle juridique',
        () {
      final model = _model(
        persons: [
          _person('person-main'),
          _person('person-adopted'),
          _person('person-fostered'),
        ],
        relationships: [
          _relation(
            'relation-adoption',
            'person-adopted',
            HumanRelationshipTypes.custom,
            customType: 'adoptiveParent',
          ),
          _relation('relation-foster', 'person-fostered',
              HumanRelationshipTypes.fosterChild),
        ],
      );
      expect(model.relationships.first.customType, 'adoptiveParent');
      expect(model.relationships.last.type, HumanRelationshipTypes.fosterChild);
    });

    test('parent absent ou décédé et relation grand-parent', () {
      final model = _model(
        persons: [
          _person('person-main'),
          _person('person-absent', status: HumanPersonStatus.absent),
          _person('person-deceased', status: HumanPersonStatus.deceased),
          _person('person-grand-parent'),
        ],
        relationships: [
          _relation('relation-grand-parent', 'person-grand-parent',
              HumanRelationshipTypes.grandParent),
        ],
      );
      expect(
          model.personById('person-absent')?.status, HumanPersonStatus.absent);
      expect(model.personById('person-deceased')?.status,
          HumanPersonStatus.deceased);
    });

    test('adulte dépendant, aidant et responsables temporaires', () {
      final validity = HumanValidityPeriod(
        validFrom: DateTime.utc(2026, 1, 1),
        validUntil: DateTime.utc(2026, 12, 31),
      );
      final model = _model(
        persons: [
          _person('person-main'),
          _person('person-dependent'),
          _person('person-nanny'),
          _person('person-close'),
        ],
        responsibilities: [
          HumanResponsibility(
            id: 'responsibility-care',
            accountScopeId: _scope,
            responsiblePersonId: 'person-main',
            subjectPersonId: 'person-dependent',
            type: HumanResponsibilityTypes.dailyAssistance,
            evidence: _confirmed,
          ),
          HumanResponsibility(
            id: 'responsibility-nanny',
            accountScopeId: _scope,
            responsiblePersonId: 'person-nanny',
            subjectPersonId: 'person-dependent',
            type: HumanResponsibilityTypes.temporary,
            validity: validity,
            evidence: _confirmed,
          ),
          HumanResponsibility(
            id: 'responsibility-close',
            accountScopeId: _scope,
            responsiblePersonId: 'person-close',
            subjectPersonId: 'person-dependent',
            type: HumanResponsibilityTypes.emergency,
            validity: validity,
            evidence: _confirmed,
          ),
        ],
      );
      expect(model.activeResponsibilities(DateTime.utc(2026, 6)), hasLength(3));
      expect(model.activeResponsibilities(DateTime.utc(2027)), hasLength(1));
    });

    test('plusieurs domiciles et hébergement temporaire', () {
      final household = HumanHousehold(
        id: 'household-main',
        accountScopeId: _scope,
        evidence: _confirmed,
      );
      final model = _model(
        households: [household],
        residences: [
          HumanResidence(
            id: 'residence-primary',
            accountScopeId: _scope,
            label: 'Domicile principal',
            householdIds: const ['household-main'],
            evidence: _confirmed,
          ),
          HumanResidence(
            id: 'residence-temporary',
            accountScopeId: _scope,
            label: 'Hébergement temporaire',
            personIds: const ['person-main'],
            status: ResidenceStatus.temporary,
            evidence: _confirmed,
          ),
        ],
        memberships: [
          HumanHouseholdMembership(
            id: 'membership-hosted',
            accountScopeId: _scope,
            householdId: household.id,
            personId: 'person-main',
            role: HouseholdMembershipRoles.hostedGuest,
            evidence: _confirmed,
          ),
        ],
      );
      expect(model.residences, hasLength(2));
      expect(
          model.memberships.single.role, HouseholdMembershipRoles.hostedGuest);
    });
  });

  group('temporalité, validation et identité', () {
    test('relations actuelle, terminée, future, historique et à confirmer', () {
      final persons = [_person('person-main'), _person('person-other')];
      final model = _model(
        persons: persons,
        relationships: [
          _relation(
            'relation-current',
            'person-other',
            HumanRelationshipTypes.closePerson,
            validity: HumanValidityPeriod(validFrom: DateTime.utc(2025, 1, 1)),
          ),
          _relation(
            'relation-ended',
            'person-other',
            HumanRelationshipTypes.formerPartner,
            status: HumanRecordStatus.ended,
            validity: HumanValidityPeriod(
              validFrom: DateTime.utc(2020),
              validUntil: DateTime.utc(2021),
            ),
          ),
          _relation(
            'relation-future',
            'person-other',
            HumanRelationshipTypes.responsiblePerson,
            validity: HumanValidityPeriod(validFrom: DateTime.utc(2030, 1, 1)),
          ),
          _relation(
            'relation-history',
            'person-other',
            HumanRelationshipTypes.closePerson,
            status: HumanRecordStatus.historical,
          ),
        ],
      );
      expect(model.activeRelationships(DateTime.utc(2026)), hasLength(1));
      expect(model.relationships, hasLength(4));
      expect(
        HumanEvidence(
          source: HumanInformationSource.zeliaProposal,
          confirmation: HumanConfirmationStatus.needsConfirmation,
        ).confirmation,
        HumanConfirmationStatus.needsConfirmation,
      );
    });

    test('période invalide et relation vers soi-même sont refusées', () {
      expect(
        () => HumanValidityPeriod(
          validFrom: DateTime.utc(2026, 2),
          validUntil: DateTime.utc(2026, 1),
        ).validate(),
        throwsA(isA<HumanModelException>()),
      );
      expect(
        () => _relation(
          'relation-self',
          'person-main',
          HumanRelationshipTypes.closePerson,
        ),
        throwsA(isA<HumanModelException>()),
      );
    });

    test('références absentes, scopes étrangers et doublons sont refusés', () {
      expect(
        () => _model(
          relationships: [
            _relation('relation-missing', 'missing',
                HumanRelationshipTypes.closePerson),
          ],
        ),
        throwsA(isA<HumanModelException>()),
      );
      expect(
        () => HumanModel(
          accountScopeId: _scope,
          primaryPersonId: 'person-main',
          persons: [
            _person('person-main'),
            HumanPerson(
              id: 'person-other',
              accountScopeId: 'other-account',
              evidence: _confirmed,
            ),
          ],
        ),
        throwsA(isA<HumanModelException>()),
      );
      expect(
        () => _model(persons: [_person('person-main'), _person('person-main')]),
        throwsA(isA<HumanModelException>()),
      );
    });

    test('appartenance dupliquée et responsabilité incomplète sont refusées',
        () {
      final household = HumanHousehold(
        id: 'household-main',
        accountScopeId: _scope,
        evidence: _confirmed,
      );
      final membership = HumanHouseholdMembership(
        id: 'membership-a',
        accountScopeId: _scope,
        householdId: household.id,
        personId: 'person-main',
        role: HouseholdMembershipRoles.permanentMember,
        evidence: _confirmed,
      );
      expect(
        () => _model(
          households: [household],
          memberships: [
            membership,
            HumanHouseholdMembership(
              id: 'membership-b',
              accountScopeId: _scope,
              householdId: household.id,
              personId: 'person-main',
              role: HouseholdMembershipRoles.permanentMember,
              evidence: _confirmed,
            ),
          ],
        ),
        throwsA(isA<HumanModelException>()),
      );
      expect(
        () => HumanResponsibility(
          id: 'responsibility-invalid',
          accountScopeId: _scope,
          responsiblePersonId: '',
          subjectPersonId: 'person-main',
          type: HumanResponsibilityTypes.care,
          evidence: _confirmed,
        ),
        throwsA(isA<HumanModelException>()),
      );
    });

    test('lien Identity personne confirmé est conservé mais facultatif', () {
      final link = PersistedIdentityLink(
        entityId: 'identity-person',
        entityType: EntityType.person,
      );
      final model = _model(
        persons: [
          _person('person-main', identityLink: link),
          _person('person-unlinked'),
        ],
      );
      final decoded = HumanModel.fromJson(model.toJson());
      expect(decoded.personById('person-main')?.identityLink, link);
      expect(decoded.personById('person-unlinked')?.identityLink, isNull);
    });
  });

  group('sérialisation versionnée', () {
    test('aller-retour JSON déterministe, ordre stable et champs inconnus', () {
      final model = _model(
        persons: [
          _person('person-z'),
          _person('person-main'),
          _person('person-a'),
        ],
        unknownFields: const {
          'futureCompatibleField': {'value': 1},
        },
      );
      final first = jsonEncode(model.toJson());
      final decoded = HumanModel.fromJson(jsonDecode(first));
      expect(jsonEncode(decoded.toJson()), first);
      expect(decoded.persons.map((item) => item.id),
          ['person-a', 'person-main', 'person-z']);
      expect(decoded.schemaVersion, HumanModel.currentSchemaVersion);
      expect(decoded.unknownFields, contains('futureCompatibleField'));
    });

    test('les structures JSON imbriquées sont figées et triées', () {
      final source = <String, Object?>{
        'z': [
          {'b': 2, 'a': 1},
        ],
        'a': true,
      };
      final model = _model(unknownFields: source);
      source['later'] = false;
      expect(model.unknownFields.keys, ['a', 'z']);
      expect(
        () => (model.unknownFields['z'] as List).add('mutation'),
        throwsUnsupportedError,
      );
      expect(
        (model.unknownFields['z'] as List).single,
        {'a': 1, 'b': 2},
      );
    });

    test('type relation inconnu est conservé comme type personnalisé', () {
      final json = _model(
        persons: [_person('person-main'), _person('person-other')],
        relationships: [
          _relation(
              'relation-custom', 'person-other', HumanRelationshipTypes.custom,
              customType: 'mentor'),
        ],
      ).toJson();
      final relation = (json['relationships'] as List).single as Map;
      relation['type'] = 'trustedMentor';
      relation.remove('customType');
      final decoded = HumanModel.fromJson(json);
      expect(decoded.relationships.single.type, HumanRelationshipTypes.custom);
      expect(decoded.relationships.single.customType, 'trustedMentor');
    });

    test('JSON corrompu et version future échouent explicitement', () {
      expect(
        () => HumanModel.fromJson('not-an-object'),
        throwsA(isA<HumanModelException>()),
      );
      final json = _model().toJson()
        ..['schemaVersion'] = HumanModel.currentSchemaVersion + 1;
      expect(
        () => HumanModel.fromJson(json),
        throwsA(
          isA<HumanModelException>().having(
            (error) => error.code,
            'code',
            'unsupported_human_schema_version',
          ),
        ),
      );
    });
  });
}
