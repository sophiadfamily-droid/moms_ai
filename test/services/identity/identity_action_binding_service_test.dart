import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_candidate.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_resolution.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/services/identity/identity_action_binding_service.dart';
import 'package:moms_ai/services/identity/identity_application_models.dart';

void main() {
  group('binding models', () {
    test('creates a valid unresolved event participant binding', () {
      final binding = _service().create(
        accountScopeId: 'account-a',
        continuation: _continuation(),
      );

      expect(binding.bindingId, 'binding-1');
      expect(binding.continuation.actionDraftId, 'event-draft-1');
      expect(
          binding.continuation.target, IdentityActionTarget.eventParticipant);
      expect(binding.resolvedEntityId, isNull);
      expect(binding.isApplied, isFalse);
    });

    test('rejects empty binding and draft identifiers', () {
      expect(
        () => PendingIdentityActionBinding(
          bindingId: '',
          accountScopeId: 'account-a',
          continuation: _continuation(),
        ),
        throwsA(_conversationError('invalid_binding_id')),
      );
      expect(
        () => IdentityActionContinuation(
          actionKind: IdentityActionKind.event,
          actionDraftId: '',
          target: IdentityActionTarget.eventParticipant,
        ),
        throwsA(_conversationError('invalid_action_draft_id')),
      );
    });

    test('enforces coherent binding results', () {
      final binding = _binding();
      expect(
        () => IdentityActionBindingResult(
          status: IdentityActionBindingStatus.attached,
          bindingId: binding.bindingId,
          actionDraftId: binding.continuation.actionDraftId,
          target: binding.continuation.target,
          diagnosticCode: 'attached',
          binding: binding,
        ),
        throwsA(_conversationError('attached_binding_requires_entity')),
      );
      expect(
        () => IdentityActionBindingResult(
          status: IdentityActionBindingStatus.invalid,
          bindingId: binding.bindingId,
          actionDraftId: binding.continuation.actionDraftId,
          target: binding.continuation.target,
          resolvedEntityId: 'entity-1',
          diagnosticCode: 'invalid',
          binding: binding,
        ),
        throwsA(_conversationError('unattached_binding_cannot_contain_entity')),
      );
    });
  });

  group('direct application results', () {
    test('attaches a directly resolved identity', () {
      final result = _service().fromApplicationResult(
        binding: _binding(),
        applicationResult: _resolvedApplicationResult(),
      );

      expect(result.status, IdentityActionBindingStatus.attached);
      expect(result.resolvedEntityId, 'entity-1');
      expect(result.binding.resolvedEntityId, 'entity-1');
    });

    test('maps ambiguity to pending clarification', () {
      final result = _service().fromApplicationResult(
        binding: _binding(),
        applicationResult: _ambiguousApplicationResult(),
      );
      expect(result.status, IdentityActionBindingStatus.pendingClarification);
      expect(result.resolvedEntityId, isNull);
    });

    test('refuses notFound, invalid, and repository failures', () {
      final results = [
        IdentityApplicationResult.fromResolution(
          EntityResolution.notFound(reasonCode: 'not_found'),
        ),
        IdentityApplicationResult.fromResolution(
          EntityResolution.invalid(signals: const [], reasonCode: 'invalid'),
        ),
        IdentityApplicationResult.repositoryFailure(),
      ];

      for (final applicationResult in results) {
        final result = _service().fromApplicationResult(
          binding: _binding(),
          applicationResult: applicationResult,
        );
        expect(result.status, IdentityActionBindingStatus.invalid);
        expect(result.resolvedEntityId, isNull);
      }
    });
  });

  group('clarification application and idempotence', () {
    test('links and applies one matching clarification', () {
      final service = _service();
      final linked = service.linkClarification(
        binding: _binding(),
        clarificationId: 'clarification-1',
      );
      final result = service.applyClarification(
        binding: linked,
        clarificationResult: _clarification(
          IdentityClarificationStatus.resolved,
          entityId: 'entity-1',
        ),
        bindingId: 'binding-1',
        clarificationId: 'clarification-1',
      );

      expect(result.status, IdentityActionBindingStatus.attached);
      expect(result.actionDraftId, 'event-draft-1');
      expect(result.resolvedEntityId, 'entity-1');
    });

    test('refuses wrong binding and clarification identifiers', () {
      final service = _service();
      final linked = service.linkClarification(
        binding: _binding(),
        clarificationId: 'clarification-1',
      );
      final clarification = _clarification(
        IdentityClarificationStatus.resolved,
        entityId: 'entity-1',
      );

      expect(
        service
            .applyClarification(
              binding: linked,
              clarificationResult: clarification,
              bindingId: 'binding-other',
              clarificationId: 'clarification-1',
            )
            .diagnosticCode,
        'binding_id_mismatch',
      );
      expect(
        service
            .applyClarification(
              binding: linked,
              clarificationResult: clarification,
              bindingId: 'binding-1',
              clarificationId: 'clarification-other',
            )
            .diagnosticCode,
        'clarification_id_mismatch',
      );
    });

    test('maps cancellation and expiration without attaching an entity', () {
      final service = _service();
      final linked = service.linkClarification(
        binding: _binding(),
        clarificationId: 'clarification-1',
      );
      for (final status in [
        IdentityClarificationStatus.cancelled,
        IdentityClarificationStatus.expired,
      ]) {
        final result = service.applyClarification(
          binding: linked,
          clarificationResult: _clarification(status),
          bindingId: 'binding-1',
          clarificationId: 'clarification-1',
        );
        expect(
          result.status,
          status == IdentityClarificationStatus.cancelled
              ? IdentityActionBindingStatus.cancelled
              : IdentityActionBindingStatus.expired,
        );
        expect(result.resolvedEntityId, isNull);
        expect(result.binding.isApplied, isFalse);
      }
    });

    test('returns alreadyApplied for an applied binding', () {
      final service = _service();
      final first = service.fromApplicationResult(
        binding: _binding(),
        applicationResult: _resolvedApplicationResult(),
      );
      final repeated = service.fromApplicationResult(
        binding: first.binding,
        applicationResult: _resolvedApplicationResult(),
      );

      expect(repeated.status, IdentityActionBindingStatus.alreadyApplied);
      expect(repeated.resolvedEntityId, isNull);
      expect(repeated.diagnosticCode, 'identity_binding_already_applied');
    });

    test('keeps account and draft identity isolated', () {
      final first = _service().create(
        accountScopeId: 'account-a',
        continuation: _continuation(actionDraftId: 'event-draft-1'),
      );
      final second = _service().create(
        accountScopeId: 'account-b',
        continuation: _continuation(actionDraftId: 'event-draft-2'),
      );

      expect(first.accountScopeId, 'account-a');
      expect(second.accountScopeId, 'account-b');
      expect(first.continuation.actionDraftId,
          isNot(second.continuation.actionDraftId));
    });

    test('diagnostics contain no labels, scope, or raw conversation data', () {
      final result = _service().invalid(
        binding: _binding(),
        diagnosticCode: 'identity_not_found',
      );
      expect(result.diagnosticCode, 'identity_not_found');
      expect(result.diagnosticCode, isNot(contains('account-a')));
      expect(result.diagnosticCode, isNot(contains('Person')));
    });
  });

  group('confirmed creation application', () {
    test('attaches only a successfully created identity', () {
      final result = _service().applyCreation(
        binding: _binding(),
        creationResult: IdentityCreationResult(
          status: IdentityCreationStatus.created,
          proposalId: 'proposal-1',
          createdEntityId: 'entity-created',
          diagnosticCode: 'identity_created',
          followUpMessage: 'Created',
        ),
      );

      expect(result.status, IdentityActionBindingStatus.attached);
      expect(result.resolvedEntityId, 'entity-created');
      expect(result.actionDraftId, 'event-draft-1');
    });

    test('keeps pending or terminal creation results unresolved', () {
      for (final status in [
        IdentityCreationStatus.stillPending,
        IdentityCreationStatus.repositoryFailure,
        IdentityCreationStatus.cancelled,
        IdentityCreationStatus.expired,
        IdentityCreationStatus.alreadyExists,
        IdentityCreationStatus.invalid,
      ]) {
        final result = _service().applyCreation(
          binding: _binding(),
          creationResult: IdentityCreationResult(
            status: status,
            proposalId: 'proposal-1',
            diagnosticCode: 'creation_${status.name}',
            followUpMessage: 'Result',
          ),
        );
        expect(result.resolvedEntityId, isNull);
        expect(result.binding.isApplied, isFalse);
      }
    });
  });
}

final now = DateTime.utc(2026, 7, 21, 10);
const source = EntitySource(type: EntitySourceType.user);

IdentityActionBindingService _service() => const IdentityActionBindingService(
      idGenerator: _FakeIdGenerator(),
    );

IdentityActionContinuation _continuation({
  String actionDraftId = 'event-draft-1',
}) =>
    IdentityActionContinuation(
      actionKind: IdentityActionKind.event,
      actionDraftId: actionDraftId,
      target: IdentityActionTarget.eventParticipant,
    );

PendingIdentityActionBinding _binding() => PendingIdentityActionBinding(
      bindingId: 'binding-1',
      accountScopeId: 'account-a',
      continuation: _continuation(),
    );

IdentityApplicationResult _resolvedApplicationResult() =>
    IdentityApplicationResult.fromResolution(
      EntityResolution.resolved(
        entity: _entity('entity-1', 'Person A'),
        confidence: EntityResolutionConfidence.strong,
        signals: const [EntityMatchSignal.exactAlias],
        reasonCode: 'resolved',
      ),
    );

IdentityApplicationResult _ambiguousApplicationResult() =>
    IdentityApplicationResult.fromResolution(
      EntityResolution.ambiguous(
        candidates: [
          EntityCandidate(entity: _entity('entity-1', 'Person A')),
          EntityCandidate(entity: _entity('entity-2', 'Person B')),
        ],
        signals: const [EntityMatchSignal.multipleCandidates],
        reasonCode: 'ambiguous',
      ),
    );

LifeEntity _entity(String id, String label) => LifeEntity.fromLabel(
      id: id,
      type: EntityType.person,
      canonicalLabel: label,
      source: source,
      createdAt: now,
      updatedAt: now,
    );

IdentityClarificationResult _clarification(
  IdentityClarificationStatus status, {
  String? entityId,
}) =>
    IdentityClarificationResult(
      status: status,
      resolvedEntityId: entityId,
      clarificationId: 'clarification-1',
      diagnosticCode: 'clarification_${status.name}',
      followUpMessage: 'Result',
    );

Matcher _conversationError(String code) => isA<ConversationIdentityException>()
    .having((error) => error.code, 'code', code);

final class _FakeIdGenerator implements EntityIdGenerator {
  const _FakeIdGenerator();

  @override
  String generate() => 'binding-1';
}
