import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_candidate.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_reference.dart';
import 'package:moms_ai/core/identity/entity_resolution.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/services/identity/identity_application_models.dart';
import 'package:moms_ai/services/identity/identity_clarification_service.dart';

void main() {
  group('pending clarification models', () {
    test('creates a valid immutable clarification', () {
      final choices = [_choice('entity-1', 'Person A')];
      final pending = _pending(choices: choices);
      choices.clear();

      expect(pending.candidateChoices, hasLength(1));
      expect(pending.isExpiredAt(now), isFalse);
      expect(pending.isExpiredAt(now.add(const Duration(minutes: 15))), isTrue);
      expect(() => pending.candidateChoices.clear(), throwsUnsupportedError);
    });

    test('rejects invalid identifiers, dates, and choice counts', () {
      expect(
        () => _pending(clarificationId: ''),
        throwsA(_conversationError('invalid_clarification_id')),
      );
      expect(
        () => _pending(expiresAt: now),
        throwsA(_conversationError('invalid_expiration_date')),
      );
      expect(
        () => _pending(choices: const []),
        throwsA(_conversationError('invalid_choice_count')),
      );
      expect(
        () => _pending(
          choices: List.generate(
            21,
            (index) => _choice('entity-$index', 'Person $index'),
          ),
        ),
        throwsA(_conversationError('invalid_choice_count')),
      );
      expect(
        () => _pending(choices: [
          _choice('entity-1', 'Person A'),
          _choice('entity-1', 'Person B'),
        ]),
        throwsA(_conversationError('duplicate_choice_entity_id')),
      );
    });

    test('enforces coherent typed results', () {
      final resolved = IdentityClarificationResult(
        status: IdentityClarificationStatus.resolved,
        resolvedEntityId: 'entity-1',
        clarificationId: 'clarification-1',
        diagnosticCode: 'clarification_resolved',
        followUpMessage: 'Resolved',
      );
      expect(resolved.resolvedEntityId, 'entity-1');
      expect(
        () => IdentityClarificationResult(
          status: IdentityClarificationStatus.resolved,
          clarificationId: 'clarification-1',
          diagnosticCode: 'invalid',
          followUpMessage: 'Invalid',
        ),
        throwsA(_conversationError('resolved_clarification_requires_entity')),
      );
      expect(
        () => IdentityClarificationResult(
          status: IdentityClarificationStatus.cancelled,
          resolvedEntityId: 'entity-1',
          clarificationId: 'clarification-1',
          diagnosticCode: 'cancelled',
          followUpMessage: 'Cancelled',
        ),
        throwsA(
          _conversationError('unresolved_clarification_cannot_contain_entity'),
        ),
      );
    });
  });

  group('clarification creation', () {
    test('accepts ambiguous and needsConfirmation results', () {
      final service = _service();
      final ambiguous = service.create(
        applicationResult: _applicationResult(
          EntityResolution.ambiguous(
            candidates: _candidates(),
            signals: const [EntityMatchSignal.multipleCandidates],
            reasonCode: 'multiple_candidates',
          ),
        ),
        request: _request(),
      );
      final confirmation = service.create(
        applicationResult: _applicationResult(
          EntityResolution.needsConfirmation(
            candidates: [_candidates().first],
            signals: const [EntityMatchSignal.multipleCandidates],
            reasonCode: 'candidate_limit_reached',
          ),
        ),
        request: _request(),
      );

      expect(ambiguous.candidateChoices, hasLength(2));
      expect(confirmation.candidateChoices, hasLength(1));
      expect(ambiguous.expiresAt.difference(ambiguous.createdAt),
          const Duration(minutes: 15));
    });

    test('rejects resolved and notFound application results', () {
      final service = _service();
      for (final resolution in [
        EntityResolution.resolved(
          entity: _entity('entity-1', 'Person A'),
          confidence: EntityResolutionConfidence.strong,
          signals: const [EntityMatchSignal.exactAlias],
          reasonCode: 'resolved',
        ),
        EntityResolution.notFound(reasonCode: 'not_found'),
      ]) {
        expect(
          () => service.create(
            applicationResult: _applicationResult(resolution),
            request: _request(),
          ),
          throwsA(
            _conversationError('clarification_requires_unresolved_candidates'),
          ),
        );
      }
    });

    test('sorts choices deterministically and retains only display fields', () {
      final service = _service();
      final pending = service.create(
        applicationResult: _applicationResult(
          EntityResolution.ambiguous(
            candidates: _candidates().reversed.toList(),
            signals: const [EntityMatchSignal.multipleCandidates],
            reasonCode: 'multiple_candidates',
          ),
        ),
        request: _request(),
      );

      expect(
        pending.candidateChoices.map((choice) => choice.entityId),
        ['entity-1', 'entity-2'],
      );
      expect(pending.candidateChoices.first.displayLabel, 'Person A');
    });

    test('generates a safe question without internal identifiers', () {
      final service = _service();
      final pending = service.create(
        applicationResult: _ambiguousResult(),
        request: _request(),
      );
      final question = service.question(pending);

      expect(question, contains('1. Person A'));
      expect(question, contains('2. Person B'));
      expect(question, isNot(contains('entity-1')));
      expect(question, isNot(contains('account-a')));
    });

    test('presents and confirms one needsConfirmation candidate safely', () {
      final service = _service();
      final pending = service.create(
        applicationResult: _applicationResult(
          EntityResolution.needsConfirmation(
            candidates: [_candidates().first],
            signals: const [EntityMatchSignal.multipleCandidates],
            reasonCode: 'candidate_limit_reached',
          ),
        ),
        request: _request(),
      );

      expect(service.question(pending), contains('Est-ce bien celle-ci'));
      expect(
        service.process(pending: pending, answer: 'oui').resolvedEntityId,
        'entity-1',
      );
    });
  });

  group('deterministic answer parsing', () {
    late IdentityClarificationService service;
    late PendingIdentityClarification pending;

    setUp(() {
      service = _service();
      pending = service.create(
        applicationResult: _ambiguousResult(),
        request: _request(),
      );
    });

    test('accepts numeric and ordinal choices', () {
      for (final answer in ['1', '1.', 'le 1', 'le premier']) {
        expect(
          service.process(pending: pending, answer: answer).resolvedEntityId,
          'entity-1',
        );
      }
      for (final answer in ['2', '2.', 'la deuxième']) {
        expect(
          service.process(pending: pending, answer: answer).resolvedEntityId,
          'entity-2',
        );
      }
    });

    test('accepts a unique exact label', () {
      final result = service.process(pending: pending, answer: 'Person B');
      expect(result.status, IdentityClarificationStatus.resolved);
      expect(result.resolvedEntityId, 'entity-2');
    });

    test('keeps duplicate labels ambiguous', () {
      final duplicate = _pending(choices: [
        _choice('entity-1', 'Shared'),
        _choice('entity-2', 'Shared'),
      ]);
      final result = service.process(pending: duplicate, answer: 'Shared');

      expect(result.status, IdentityClarificationStatus.stillAmbiguous);
      expect(result.resolvedEntityId, isNull);
    });

    test('keeps out-of-range, empty, and incomprehensible answers pending', () {
      for (final answer in ['3', '', 'maybe later']) {
        final result = service.process(pending: pending, answer: answer);
        expect(result.status, IdentityClarificationStatus.stillAmbiguous);
        expect(result.diagnosticCode, 'clarification_still_ambiguous');
      }
    });

    test('handles refusal and cancellation without a selected entity', () {
      for (final answer in ['non', 'aucun', 'annule']) {
        final result = service.process(pending: pending, answer: answer);
        expect(result.status, IdentityClarificationStatus.cancelled);
        expect(result.resolvedEntityId, isNull);
      }
    });

    test('expires deterministically at the boundary', () {
      final result = service.process(
        pending: pending,
        answer: '1',
        referenceDate: pending.expiresAt,
      );

      expect(result.status, IdentityClarificationStatus.expired);
      expect(result.resolvedEntityId, isNull);
      expect(result.diagnosticCode, 'clarification_expired');
    });

    test('does not expose raw values in diagnostics', () {
      final result = service.process(pending: pending, answer: 'unknown');
      expect(result.diagnosticCode, 'clarification_still_ambiguous');
      expect(result.diagnosticCode, isNot(contains('Person')));
      expect(result.diagnosticCode, isNot(contains('account')));
    });
  });
}

final now = DateTime.utc(2026, 7, 21, 10);
const source = EntitySource(type: EntitySourceType.user);

IdentityClarificationService _service() => IdentityClarificationService(
      idGenerator: _FakeIdGenerator(),
      now: () => now,
    );

IdentityResolutionRequest _request() => IdentityResolutionRequest(
      scope: IdentityAccountScope('account-a'),
      reference: EntityReference.text(
        value: 'Person',
        kind: EntityReferenceKind.alias,
        source: source,
      ),
    );

IdentityApplicationResult _ambiguousResult() => _applicationResult(
      EntityResolution.ambiguous(
        candidates: _candidates(),
        signals: const [EntityMatchSignal.multipleCandidates],
        reasonCode: 'multiple_candidates',
      ),
    );

IdentityApplicationResult _applicationResult(EntityResolution resolution) =>
    IdentityApplicationResult.fromResolution(resolution);

List<EntityCandidate> _candidates() => [
      EntityCandidate(entity: _entity('entity-1', 'Person A')),
      EntityCandidate(entity: _entity('entity-2', 'Person B')),
    ];

LifeEntity _entity(String id, String label) => LifeEntity.fromLabel(
      id: id,
      type: EntityType.person,
      canonicalLabel: label,
      source: source,
      createdAt: now,
      updatedAt: now,
      metadata: const {
        'internal': ['not copied'],
      },
    );

IdentityClarificationChoice _choice(String id, String label) =>
    IdentityClarificationChoice(
      entityId: id,
      type: EntityType.person,
      displayLabel: label,
    );

PendingIdentityClarification _pending({
  String clarificationId = 'clarification-1',
  List<IdentityClarificationChoice>? choices,
  DateTime? expiresAt,
}) =>
    PendingIdentityClarification(
      clarificationId: clarificationId,
      reference: _request().reference,
      candidateChoices: choices ?? [_choice('entity-1', 'Person A')],
      createdAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(minutes: 15)),
      accountScopeId: 'account-a',
    );

Matcher _conversationError(String code) => isA<ConversationIdentityException>()
    .having((error) => error.code, 'code', code);

final class _FakeIdGenerator implements EntityIdGenerator {
  @override
  String generate() => 'clarification-1';
}
