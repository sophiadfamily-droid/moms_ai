import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/conversation_reference_resolution.dart';
import 'package:moms_ai/services/conversation_reference_resolver.dart';

void main() {
  const resolver = ConversationReferenceResolver();
  final now = DateTime.utc(2026, 7, 27, 10);

  group('priority and deterministic resolution', () {
    test('explicit unique person wins and exposes only a stable ID', () {
      final result = resolver.resolve(
        _request(
          type: ConversationReferenceEntityType.person,
          hasExplicitMention: true,
          explicit: [_candidate('kassim', type: _person)],
          pending: [_candidate('other', type: _person)],
        ),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.resolved);
      expect(result.entityId, 'kassim');
      expect(
        result.source,
        ConversationReferenceSource.explicitEntityMention,
      );
      expect(result.candidateIds, isEmpty);
      expect(
        result.toDiagnosticMetadata().keys,
        {
          'referenceType',
          'entityType',
          'candidateCount',
          'reasonCode',
          'resolved',
        },
      );
    });

    test('pending action has priority over validated history', () {
      final result = resolver.resolve(
        _request(
          type: _event,
          pending: [_candidate('event-pending', type: _event)],
          history: [_history('event-history', type: _event, now: now)],
        ),
        referenceDate: now,
      );

      expect(result.entityId, 'event-pending');
      expect(result.source, ConversationReferenceSource.pendingAction);
    });

    test('validated recent history resolves one compatible antecedent', () {
      final result = resolver.resolve(
        _request(
          type: _person,
          history: [_history('person-1', type: _person, now: now)],
        ),
        referenceDate: now,
      );

      expect(result.entityId, 'person-1');
      expect(
        result.source,
        ConversationReferenceSource.validatedConversationHistory,
      );
    });

    test('stale history is refused', () {
      final result = resolver.resolve(
        _request(
          type: _person,
          history: [
            ValidatedConversationReference(
              entityId: 'person-1',
              entityType: _person,
              accountScopeId: 'account-a',
              validatedAt: now.subtract(const Duration(minutes: 15)),
              expiresAt: now.subtract(const Duration(microseconds: 1)),
            ),
          ],
        ),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.unresolved);
      expect(
        result.reasonCode,
        ConversationReferenceReasonCode.staleOrUnvalidatedHistory,
      );
    });

    test('history accepts only the strict validated time window', () {
      final validatedAt = now;
      final expiresAt = now.add(const Duration(minutes: 15));
      final reference = ValidatedConversationReference(
        entityId: 'event-1',
        entityType: _event,
        accountScopeId: 'account-a',
        validatedAt: validatedAt,
        expiresAt: expiresAt,
      );

      expect(reference.isValidAt(validatedAt), isTrue);
      expect(
        reference
            .isValidAt(expiresAt.subtract(const Duration(microseconds: 1))),
        isTrue,
      );
      expect(reference.isValidAt(expiresAt), isFalse);
      expect(
        reference.isValidAt(expiresAt.add(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(
        reference
            .isValidAt(validatedAt.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
    });

    test('future validated timestamp is refused after reconstruction', () {
      final corruptedFuture = ValidatedConversationReference.fromPersistedJson(
        {
          'schemaVersion': 1,
          'entityType': 'event',
          'entityId': 'event-1',
          'validatedAt': now.add(const Duration(minutes: 1)).toIso8601String(),
          'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(),
          'source': 'validatedConversationHistory',
        },
        accountScopeId: 'account-a',
      );
      final result = resolver.resolve(
        _request(type: _event, history: [corruptedFuture]),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.unresolved);
      expect(
        result.reasonCode,
        ConversationReferenceReasonCode.staleOrUnvalidatedHistory,
      );
    });

    test('invalid, incoherent and overlong persisted timestamps are refused',
        () {
      for (final payload in [
        {
          'schemaVersion': 1,
          'entityType': 'event',
          'entityId': 'event-1',
          'validatedAt': 'invalid',
          'expiresAt': now.toIso8601String(),
          'source': 'validatedConversationHistory',
        },
        {
          'schemaVersion': 1,
          'entityType': 'event',
          'entityId': 'event-1',
          'validatedAt': now.toIso8601String(),
          'expiresAt':
              now.subtract(const Duration(seconds: 1)).toIso8601String(),
          'source': 'validatedConversationHistory',
        },
        {
          'schemaVersion': 1,
          'entityType': 'event',
          'entityId': 'event-1',
          'validatedAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(minutes: 16)).toIso8601String(),
          'source': 'validatedConversationHistory',
        },
      ]) {
        expect(
          () => ValidatedConversationReference.fromPersistedJson(
            payload,
            accountScopeId: 'account-a',
          ),
          throwsFormatException,
        );
      }
    });
  });

  group('people and ambiguity', () {
    test('one pronoun candidate resolves and several never do', () {
      final unique = resolver.resolve(
        _request(
          type: _person,
          pending: [_candidate('person-1', type: _person)],
        ),
        referenceDate: now,
      );
      final ambiguous = resolver.resolve(
        _request(
          type: _person,
          history: [
            _history('person-1', type: _person, now: now),
            _history('person-2', type: _person, now: now),
          ],
        ),
        referenceDate: now,
      );

      expect(unique.entityId, 'person-1');
      expect(
        ambiguous.status,
        ConversationReferenceResolutionStatus.ambiguous,
      );
      expect(ambiguous.candidateIds, ['person-1', 'person-2']);
    });

    test('two people with the same explicit name remain ambiguous', () {
      final result = resolver.resolve(
        _request(
          type: _person,
          hasExplicitMention: true,
          explicit: [
            _candidate('person-a', type: _person),
            _candidate('person-b', type: _person),
          ],
        ),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.ambiguous);
      expect(
        result.reasonCode,
        ConversationReferenceReasonCode.multipleExplicitCandidates,
      );
    });

    test('unknown named third party does not fall back to history', () {
      final result = resolver.resolve(
        _request(
          type: _person,
          hasExplicitMention: true,
          history: [_history('known-person', type: _person, now: now)],
        ),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.unresolved);
      expect(
        result.reasonCode,
        ConversationReferenceReasonCode.explicitMentionNotFound,
      );
    });

    test('foreign, inactive and unverified entities are refused', () {
      for (final scenario in [
        (
          _candidate('foreign', type: _person, scope: 'account-b'),
          ConversationReferenceReasonCode.accountScopeMismatch,
        ),
        (
          _candidate('deleted', type: _person, active: false),
          ConversationReferenceReasonCode.inactiveOrDeletedEntity,
        ),
        (
          _candidate('forged', type: _person, verified: false),
          ConversationReferenceReasonCode.entityNotLocallyVerified,
        ),
      ]) {
        final result = resolver.resolve(
          _request(
            type: _person,
            hasExplicitMention: true,
            explicit: [scenario.$1],
          ),
          referenceDate: now,
        );
        expect(result.status, ConversationReferenceResolutionStatus.unresolved);
        expect(result.reasonCode, scenario.$2);
      }
    });
  });

  group('actions and relations', () {
    test('one event tomorrow resolves and several require clarification', () {
      final unique = resolver.resolve(
        _request(
          type: _event,
          explicit: [_candidate('event-1', type: _event)],
          hasExplicitMention: true,
        ),
        referenceDate: now,
      );
      final ambiguous = resolver.resolve(
        _request(
          type: _event,
          explicit: [
            _candidate('event-1', type: _event),
            _candidate('event-2', type: _event),
          ],
          hasExplicitMention: true,
        ),
        referenceDate: now,
      );

      expect(unique.entityId, 'event-1');
      expect(
        ambiguous.status,
        ConversationReferenceResolutionStatus.ambiguous,
      );
    });

    test('a unique structured school resolves only through Life Context', () {
      final result = resolver.resolve(
        _request(
          type: _place,
          life: [_candidate('school-1', type: _place)],
          allowLife: true,
        ),
        referenceDate: now,
      );

      expect(result.entityId, 'school-1');
      expect(result.source, ConversationReferenceSource.lifeContext);
    });

    test('multiple schools, residences and households remain ambiguous', () {
      for (final type in [_place, _residence, _household]) {
        final result = resolver.resolve(
          _request(
            type: type,
            life: [
              _candidate('${type.name}-1', type: type),
              _candidate('${type.name}-2', type: type),
            ],
            allowLife: true,
          ),
          referenceDate: now,
        );
        expect(
          result.status,
          ConversationReferenceResolutionStatus.ambiguous,
          reason: type.name,
        );
      }
    });

    test('a backend ID is unusable until locally verified', () {
      final result = resolver.resolve(
        _request(
          type: _event,
          backendId: 'backend-event',
          explicit: [_candidate('local-event', type: _event)],
        ),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.unresolved);
      expect(
        result.reasonCode,
        ConversationReferenceReasonCode.entityNotLocallyVerified,
      );
    });

    test('unsupported action remains explicit and mutation-free', () {
      final result = resolver.resolve(
        _request(type: _routine, isSupported: false),
        referenceDate: now,
      );

      expect(result.status, ConversationReferenceResolutionStatus.unsupported);
      expect(result.entityId, isNull);
    });
  });

  test('universal roles never influence candidate selection', () {
    const roleIds = [
      'separated-parent',
      'same-sex-partner',
      'step-parent',
      'grand-parent',
      'nanny',
      'dependent-adult',
      'unrelated-person',
    ];

    for (final id in roleIds) {
      final result = resolver.resolve(
        _request(
          type: _person,
          pending: [_candidate(id, type: _person)],
        ),
        referenceDate: now,
      );
      expect(result.entityId, id);
    }
  });

  test('contract is bounded and diagnostics never contain IDs or text', () {
    final result = ConversationReferenceResolution(
      status: ConversationReferenceResolutionStatus.ambiguous,
      referenceType: ConversationReferenceType.pronoun,
      entityType: _person,
      candidateIds: ['person-2', 'person-1'],
      source: ConversationReferenceSource.validatedConversationHistory,
      reasonCode: ConversationReferenceReasonCode.multipleHistoryCandidates,
    );

    expect(result.schemaVersion, 1);
    expect(result.candidateIds, ['person-1', 'person-2']);
    expect(
        result.toDiagnosticMetadata().toString(), isNot(contains('person-')));
    expect(
      () => ConversationReferenceResolution(
        status: ConversationReferenceResolutionStatus.ambiguous,
        referenceType: ConversationReferenceType.pronoun,
        entityType: _person,
        candidateIds: List.generate(21, (index) => 'person-$index'),
        source: ConversationReferenceSource.validatedConversationHistory,
        reasonCode: ConversationReferenceReasonCode.multipleHistoryCandidates,
      ),
      throwsFormatException,
    );
  });

  test('coordinator reconstruction and retry remain deterministic', () {
    final history = [_history('event-1', type: _event, now: now)];
    final request = _request(type: _event, history: history);

    final first = resolver.resolve(request, referenceDate: now);
    final reconstructed = const ConversationReferenceResolver()
        .resolve(request, referenceDate: now);
    final retry = const ConversationReferenceResolver()
        .resolve(request, referenceDate: now);

    expect(reconstructed.entityId, first.entityId);
    expect(retry.entityId, first.entityId);
    expect(retry.reasonCode, first.reasonCode);
  });
}

const _person = ConversationReferenceEntityType.person;
const _event = ConversationReferenceEntityType.event;
const _routine = ConversationReferenceEntityType.routine;
const _place = ConversationReferenceEntityType.structuredPlace;
const _residence = ConversationReferenceEntityType.residence;
const _household = ConversationReferenceEntityType.household;

ConversationReferenceRequest _request({
  required ConversationReferenceEntityType type,
  bool hasExplicitMention = false,
  bool allowLife = false,
  bool isSupported = true,
  String? backendId,
  List<ConversationReferenceCandidate> explicit = const [],
  List<ConversationReferenceCandidate> pending = const [],
  List<ValidatedConversationReference> history = const [],
  List<ConversationReferenceCandidate> life = const [],
}) =>
    ConversationReferenceRequest(
      accountScopeId: 'account-a',
      referenceType: hasExplicitMention
          ? ConversationReferenceType.explicitMention
          : ConversationReferenceType.pronoun,
      entityType: type,
      hasExplicitMention: hasExplicitMention,
      allowLifeContextRelation: allowLife,
      isSupported: isSupported,
      backendProposedEntityId: backendId,
      explicitCandidates: explicit,
      pendingCandidates: pending,
      validatedHistory: history,
      lifeContextCandidates: life,
    );

ConversationReferenceCandidate _candidate(
  String id, {
  required ConversationReferenceEntityType type,
  String scope = 'account-a',
  bool active = true,
  bool verified = true,
}) =>
    ConversationReferenceCandidate(
      entityId: id,
      entityType: type,
      accountScopeId: scope,
      source: ConversationReferenceSource.currentMessage,
      isActive: active,
      isLocallyVerified: verified,
    );

ValidatedConversationReference _history(
  String id, {
  required ConversationReferenceEntityType type,
  required DateTime now,
}) =>
    ValidatedConversationReference(
      entityId: id,
      entityType: type,
      accountScopeId: 'account-a',
      validatedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(const Duration(minutes: 14)),
    );
