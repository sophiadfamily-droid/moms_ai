import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_evidence.dart';
import 'package:moms_ai/models/memory_semantic_identity.dart';
import 'package:moms_ai/services/memory_semantic_identity_service.dart';

void main() {
  const service = MemorySemanticIdentityService();

  MemoryEvidenceQualification evidence({
    MemoryEvidenceSubjectType subject = MemoryEvidenceSubjectType.user,
    String? entityId,
  }) =>
      MemoryEvidenceQualification(
        classification: MemoryEvidenceClassification.directExplicit,
        subjectType: subject,
        subjectEntityId: entityId,
        canConfirmImmediately: subject != MemoryEvidenceSubjectType.unknown,
        isCorrection: false,
      );

  MemorySemanticResolution resolve(
    String text, {
    String proposalId = 'proposal-1',
    MemoryEvidenceQualification? qualification,
    MemorySemanticSubjectScope? scope,
    String? subjectId,
    MemorySemanticContextType? contextType,
    String? contextEntityId,
    LifeMemorySemanticType type = LifeMemorySemanticType.preference,
  }) =>
      service.resolve(
        proposalId: proposalId,
        text: text,
        semanticType: type,
        evidence: qualification ?? evidence(),
        explicitSubjectScope: scope,
        explicitSubjectEntityId: subjectId,
        contextType: contextType,
        contextEntityId: contextEntityId,
      );

  test('equivalent appointment formulations have one stable identity', () {
    final first = resolve('Je préfère mes rendez-vous le matin.');
    final second = resolve('JE PRÉFÈRE mes rendez-vous : le matin !');

    expect(first.identity.canonicalKey, second.identity.canonicalKey);
    expect(first.identity.domain, MemorySemanticDomain.planning);
    expect(first.identity.attribute,
        MemorySemanticAttribute.preferredAppointmentPeriod);
    expect(first.identity.contextType,
        MemorySemanticContextType.personalAppointments);
  });

  test('morning and afternoon share identity but retain separate values', () {
    final morning = resolve('Je préfère mes rendez-vous le matin.');
    final afternoon = resolve(
      'Je préfère mes rendez-vous l’après-midi.',
      proposalId: 'proposal-2',
    );

    expect(morning.identity.canonicalKey, afternoon.identity.canonicalKey);
    expect(morning.value, 'morning');
    expect(afternoon.value, 'afternoon');
  });

  test('different attributes and contexts remain different', () {
    final appointments = resolve('Je préfère mes rendez-vous le matin.');
    final availability = resolve(
      'Je ne suis jamais disponible le mardi après 18 h.',
      type: LifeMemorySemanticType.constraint,
    );
    final work = resolve(
      'Je travaille le mercredi matin.',
      type: LifeMemorySemanticType.fact,
    );

    expect(appointments.identity.canonicalKey,
        isNot(availability.identity.canonicalKey));
    expect(
        appointments.identity.canonicalKey, isNot(work.identity.canonicalKey));
    expect(appointments.identity.contextType,
        MemorySemanticContextType.personalAppointments);
    expect(work.identity.contextType, MemorySemanticContextType.workplace);
  });

  test('authenticated user and resolved entities have distinct keys', () {
    final user = resolve('Je préfère mes rendez-vous le matin.');
    final firstPerson = resolve(
      'Ma sœur préfère ses rendez-vous le matin.',
      qualification: evidence(
        subject: MemoryEvidenceSubjectType.structuredEntity,
        entityId: 'person-a',
      ),
    );
    final secondPerson = resolve(
      'Ma sœur préfère ses rendez-vous le matin.',
      proposalId: 'proposal-2',
      qualification: evidence(
        subject: MemoryEvidenceSubjectType.structuredEntity,
        entityId: 'person-b',
      ),
    );

    expect(user.identity.subjectScope,
        MemorySemanticSubjectScope.authenticatedUser);
    expect(firstPerson.identity.canonicalKey,
        isNot(secondPerson.identity.canonicalKey));
    expect(
        user.identity.canonicalKey, isNot(firstPerson.identity.canonicalKey));
  });

  test('unknown subjects are isolated and ineligible for contradiction', () {
    final unknownEvidence = evidence(
      subject: MemoryEvidenceSubjectType.unknown,
    );
    final first = resolve(
      'Cette personne préfère ses rendez-vous le matin.',
      qualification: unknownEvidence,
    );
    final second = resolve(
      'Cette personne préfère ses rendez-vous le matin.',
      proposalId: 'proposal-2',
      qualification: unknownEvidence,
    );

    expect(first.identity.subjectScope, MemorySemanticSubjectScope.unknown);
    expect(first.identity.eligibleForAutomaticContradiction, isFalse);
    expect(second.identity.eligibleForAutomaticContradiction, isFalse);
    expect(first.identity.canonicalKey, isNot(second.identity.canonicalKey));
  });

  test('households and residences require explicit stable scopes', () {
    final householdA = resolve(
      'Préférence générale',
      scope: MemorySemanticSubjectScope.household,
      subjectId: 'household-a',
      contextType: MemorySemanticContextType.household,
      contextEntityId: 'shared-calendar',
    );
    final householdB = resolve(
      'Préférence générale',
      scope: MemorySemanticSubjectScope.household,
      subjectId: 'household-b',
      contextType: MemorySemanticContextType.household,
      contextEntityId: 'shared-calendar',
    );
    final residenceA = resolve(
      'Mon adresse actuelle est 10 rue privée',
      scope: MemorySemanticSubjectScope.residence,
      subjectId: 'residence-a',
    );
    final residenceB = resolve(
      'Mon adresse actuelle est 20 rue secrète',
      scope: MemorySemanticSubjectScope.residence,
      subjectId: 'residence-b',
    );

    expect(householdA.identity.canonicalKey,
        isNot(householdB.identity.canonicalKey));
    expect(residenceA.identity.canonicalKey,
        isNot(residenceB.identity.canonicalKey));
    expect(
        householdA.identity.contextType, MemorySemanticContextType.household);
  });

  test('same attribute in two explicit contexts has distinct keys', () {
    final personal = resolve(
      'Je préfère mes rendez-vous le matin.',
      contextType: MemorySemanticContextType.personalAppointments,
      contextEntityId: 'calendar-id',
    );
    final professional = resolve(
      'Je préfère mes rendez-vous le matin.',
      contextType: MemorySemanticContextType.workAppointments,
      contextEntityId: 'calendar-id',
    );

    expect(personal.identity.canonicalKey,
        isNot(professional.identity.canonicalKey));
  });

  test('canonical key contains no raw address, secret, or full sentence', () {
    final address = resolve(
      'Mon adresse actuelle est 10 rue Très Privée, Paris.',
      type: LifeMemorySemanticType.fact,
    );
    final secret = resolve(
      'Souviens-toi que mon mot de passe est SuperSecret42.',
      proposalId: 'proposal-secret',
      type: LifeMemorySemanticType.fact,
    );

    expect(address.identity.canonicalKey, isNot(contains('10')));
    expect(address.identity.canonicalKey, isNot(contains('paris')));
    expect(secret.identity.canonicalKey, isNot(contains('supersecret')));
    expect(secret.identity.canonicalKey.length, lessThanOrEqualTo(240));
  });

  test('generic attributes are always ineligible', () {
    final train = resolve('Je préfère le train.');
    final room = resolve(
      'Je préfère une chambre calme.',
      proposalId: 'proposal-room',
    );

    expect(train.identity.attribute, MemorySemanticAttribute.generalPreference);
    expect(train.identity.eligibleForAutomaticContradiction, isFalse);
    expect(room.identity.eligibleForAutomaticContradiction, isFalse);
  });

  test('opaque identifiers preserve exact byte distinctions', () {
    final keys = ['Person-A', 'person-a', 'person_a']
        .map(
          (id) => resolve(
            'Ma sœur préfère ses rendez-vous le matin.',
            qualification: evidence(
              subject: MemoryEvidenceSubjectType.structuredEntity,
              entityId: id,
            ),
          ).identity,
        )
        .toList();

    expect(keys.map((item) => item.subjectFingerprint).toSet(), hasLength(3));
    expect(keys.map((item) => item.canonicalKey).toSet(), hasLength(3));
    for (final raw in ['Person-A', 'person-a', 'person_a']) {
      expect(keys.join(), isNot(contains(raw)));
    }
    expect(
      MemorySemanticIdentityService.fingerprint(
        namespace: 'zelia-memory-subject-v1',
        scope: 'structured_entity',
        exactId: 'Person-A',
      ),
      MemorySemanticIdentityService.fingerprint(
        namespace: 'zelia-memory-subject-v1',
        scope: 'structured_entity',
        exactId: 'Person-A',
      ),
    );
  });

  test('structured scopes without ids become stable isolated unknowns', () {
    for (final scope in const [
      MemorySemanticSubjectScope.structuredEntity,
      MemorySemanticSubjectScope.household,
      MemorySemanticSubjectScope.residence,
    ]) {
      final first = resolve(
        'Je préfère mes rendez-vous le matin.',
        scope: scope,
      );
      final retry = resolve(
        'Je préfère mes rendez-vous l’après-midi.',
        scope: scope,
      );
      final other = resolve(
        'Je préfère mes rendez-vous le matin.',
        proposalId: 'proposal-other',
        scope: scope,
      );

      expect(first.identity.subjectScope, MemorySemanticSubjectScope.unknown);
      expect(first.identity.eligibleForAutomaticContradiction, isFalse);
      expect(first.identity.canonicalKey, retry.identity.canonicalKey);
      expect(first.identity.canonicalKey, isNot(other.identity.canonicalKey));
    }
  });

  test('closed contexts expose only type and fingerprints', () {
    final personal = resolve(
      'Je préfère mes rendez-vous le matin.',
      contextType: MemorySemanticContextType.personalAppointments,
      contextEntityId: 'SuperSecret42',
    );
    final work = resolve(
      'Je préfère mes rendez-vous le matin.',
      contextType: MemorySemanticContextType.workAppointments,
      contextEntityId: 'SuperSecret42',
    );

    expect(personal.identity.canonicalKey, isNot(contains('SuperSecret42')));
    expect(personal.identity.toJson().toString(),
        isNot(contains('SuperSecret42')));
    expect(personal.identity.canonicalKey, isNot(work.identity.canonicalKey));
  });

  test('validated JSON round-trip and fail-closed reader', () {
    final identity = resolve(
      'Je préfère mes rendez-vous le matin.',
      contextEntityId: 'calendar-1',
    ).identity;
    final json = identity.toJson();

    expect(
      MemorySemanticIdentity.fromJson(json).toJson(),
      json,
    );
    expect(MemorySemanticIdentity.read(null).status,
        MemorySemanticIdentityReadStatus.absentLegacy);
    expect(
      MemorySemanticIdentity.read({...json}..remove('attribute')).status,
      MemorySemanticIdentityReadStatus.invalidModern,
    );
    for (final invalid in [
      {...json, 'schemaVersion': 99},
      {...json, 'domain': 'unknown-domain'},
      {...json, 'canonicalKey': 'forged'},
      {...json, 'eligibleForAutomaticContradiction': false},
      {...json, 'contextFingerprint': 42},
      {
        ...json,
        'domain': 'health',
        'canonicalKey': MemorySemanticIdentity.buildCanonicalKey(
          domain: MemorySemanticDomain.health,
          attribute: identity.attribute,
          subjectScope: identity.subjectScope,
          subjectFingerprint: identity.subjectFingerprint,
          contextType: identity.contextType,
          contextFingerprint: identity.contextFingerprint,
        ),
      },
    ]) {
      expect(MemorySemanticIdentity.read(invalid).status,
          MemorySemanticIdentityReadStatus.invalidModern);
    }
  });

  test('no household or residence is assumed without an explicit scope', () {
    final result = resolve('Je préfère mes rendez-vous le matin.');

    expect(result.identity.subjectScope,
        MemorySemanticSubjectScope.authenticatedUser);
    expect(result.identity.subjectFingerprint, isNull);
    expect(result.identity.canonicalKey, isNot(contains('household')));
    expect(result.identity.canonicalKey, isNot(contains('residence')));
  });
}
