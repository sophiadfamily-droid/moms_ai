import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/services/memory_consumption_policy.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_contradiction.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_semantic_identity.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_answer_classifier.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';

void main() {
  final now = DateTime.utc(2026, 7, 21, 10);

  group('ConversationAnswerClassifier', () {
    const classifier = ConversationAnswerClassifier();

    test('recognizes guarded positive and negative French answers', () {
      for (final answer in const [
        'oui',
        'Oui, retiens-le.',
        'd’accord',
        'confirme',
        'garde cette information',
        'tu peux la mémoriser',
        'oui je confirme',
      ]) {
        expect(classifier.classify(answer), ConversationAnswer.positive);
      }
      for (final answer in const [
        'non',
        'ne retiens pas ça',
        'oublie',
        'annule',
        'je ne veux pas que tu le mémorises',
        'non merci',
        'ne remplace pas',
        'garde l’ancienne information',
      ]) {
        expect(classifier.classify(answer), ConversationAnswer.negative);
      }
    });

    test('does not infer an answer from ambiguous text', () {
      expect(
        classifier.classify('oui mais non, finalement'),
        ConversationAnswer.ambiguous,
      );
      expect(
        classifier.classify('peut-être'),
        ConversationAnswer.ambiguous,
      );
    });
  });

  group('memory conversational confirmation', () {
    test('replacement confirmation executes after explicit acceptance',
        () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      final fingerprint = 'a' * 64;
      coordinator.setPendingMemoryConfirmation(
        MemoryConfirmationRequest(
          action: MemoryLifecycleAction.replace,
          proposalId: 'proposal-1',
          memoryId: 'existing-1',
          prompt: 'Veux-tu remplacer cette préférence ?',
          changeType: 'memoryReplacementConfirmation',
          sensitivity: LifeContextSensitivity.standard,
          consequence: 'Replacement pending',
          contradictionCandidate: MemoryContradictionCandidate(
            contradictionId: 'b' * 64,
            existingMemoryId: 'existing-1',
            proposedMemoryId: 'proposal-1',
            canonicalKey: 'canonical-key',
            existingRevision: 2,
            proposedRevision: 1,
            existingValueFingerprint: fingerprint,
            proposedValueFingerprint: 'c' * 64,
            subjectScope: 'authenticated_user',
            detectedAt: now,
            reasonCode:
                MemoryContradictionReasonCode.incompatibleClosedAttributeValues,
            eligibleForReplacement: true,
          ),
          replacementPendingAction: MemoryReplacementPendingAction(
            actionId: 'd' * 64,
            accountScopeFingerprint: 'e' * 64,
            existingMemoryId: 'existing-1',
            proposedMemoryId: 'proposal-1',
            canonicalKey: 'v1|planning|preferred_appointment_period|'
                'authenticated_user|scope|personal_appointments|none',
            expectedExistingRevision: 2,
            expectedProposedRevision: 1,
            contradictionId: 'b' * 64,
            reasonCode:
                MemoryContradictionReasonCode.incompatibleClosedAttributeValues,
            state: MemoryReplacementActionState.pending,
            logicalRequestFingerprint: 'f' * 64,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        createdAt: now,
      );

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result?.diagnosticCode, 'memoryReplacementExecuted');
      expect(result?.message, isNot(contains('Generic preference')));
      expect(repository.applied, isEmpty);
      expect(coordinator.state.pendingAction, isNull);
      expect(repository.executionCalls, 1);
      expect(repository.applied, isEmpty);
    });

    test('replacement refusal declines durable action without memory mutation',
        () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      coordinator.setPendingMemoryConfirmation(
        _replacementRequest(now),
        createdAt: now,
      );

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'garde l’ancienne information',
        referenceDate: now,
      );

      expect(result?.diagnosticCode, 'memoryReplacementDeclined');
      expect(result?.message, contains('rien n’a été remplacé'));
      expect(repository.replacementAction?.state,
          MemoryReplacementActionState.declined);
      expect(repository.applied, isEmpty);
      expect(coordinator.state.pendingAction, isNull);
    });

    test('ambiguous replacement answer leaves durable action pending',
        () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      coordinator.setPendingMemoryConfirmation(
        _replacementRequest(now),
        createdAt: now,
      );

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'plus tard',
        referenceDate: now,
      );

      expect(result?.message, contains('oui ou non'));
      expect(repository.replacementAction, isNull);
      expect(repository.applied, isEmpty);
      expect(coordinator.state.pendingAction, isNotNull);
    });

    test('replacement conflict never announces success', () async {
      final repository = _FakeRepository(_memory())
        ..executionCode = MemoryReplacementExecutionCode.revisionConflict;
      final coordinator = _coordinator(repository);
      coordinator.setPendingMemoryConfirmation(
        _replacementRequest(now),
        createdAt: now,
      );

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result?.diagnosticCode, 'memoryReplacementConflict');
      expect(result?.message, contains('revérifier'));
      expect(result?.message, isNot(contains('Generic preference')));
      expect(coordinator.state.pendingAction, isNull);
    });

    test('unavailable replacement remains retryable without success claim',
        () async {
      final repository = _FakeRepository(_memory())
        ..executionCode = MemoryReplacementExecutionCode.unavailable;
      final coordinator = _coordinator(repository);
      coordinator.setPendingMemoryConfirmation(
        _replacementRequest(now),
        createdAt: now,
      );

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result?.diagnosticCode, 'memoryReplacementUnavailable');
      expect(result?.message, isNot(contains('mis à jour')));
      expect(
        coordinator.state.pendingAction?.memoryReplacementAction?.state,
        MemoryReplacementActionState.acceptedPendingExecution,
      );
    });

    test('coordinator reconstruction restores a durable pending action',
        () async {
      final repository = _FakeRepository(_memory())
        ..replacementAction = _replacementRequest(now).replacementPendingAction;
      final coordinator = _coordinator(repository);

      final restored = await coordinator.restorePendingMemoryReplacement(
        accountScopeId: 'account-test',
        logicalRequestId: 'logical-1',
        restoredAt: now,
      );

      expect(restored, isTrue);
      expect(coordinator.state.pendingAction?.memoryReplacementAction?.actionId,
          'd' * 64);
    });

    test('coordinator reconstruction executes an already accepted action',
        () async {
      final repository = _FakeRepository(_memory())
        ..replacementAction =
            _replacementRequest(now).replacementPendingAction!.withState(
                  MemoryReplacementActionState.acceptedPendingExecution,
                  now,
                );
      final coordinator = _coordinator(repository);

      final restored = await coordinator.restorePendingMemoryReplacement(
        accountScopeId: 'account-test',
        logicalRequestId: 'logical-1',
        restoredAt: now,
      );

      expect(restored, isTrue);
      expect(repository.executionCalls, 1);
      expect(coordinator.state.pendingAction, isNull);
    });

    test('presents a stable proposal before calling the backend', () async {
      final repository = _FakeRepository(_memory());
      final backend = _FakeBackend();
      final context = _MemoryContext(repository);
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
      );

      final outcome = await coordinator.send(
        input: ConversationInput(
          message: 'Remember this preference',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(outcome?.reply, contains('Generic preference'));
      expect(backend.calls, 0);
      expect(
        coordinator.state.pendingAction?.proposalId,
        'proposal-1',
      );
      expect(
        coordinator.state.pendingAction?.type,
        PendingConversationActionType.memoryConfirmation,
      );
    });

    test('an explicit memory failure never falls through to the backend',
        () async {
      final repository = _FakeRepository(_memory());
      final backend = _FakeBackend();
      final context = _MemoryContext(repository, returnsProposal: false);
      final coordinator = ConversationCoordinator(
        backend: backend,
        contextProvider: context,
      );

      final outcome = await coordinator.send(
        input: ConversationInput(
          message: 'Souviens toi que je préfère les rendez-vous le matin',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(outcome?.reply, contains('pas pu ajouter'));
      expect(backend.calls, 0);
      expect(coordinator.state.pendingAction, isNull);
    });

    test('confirms then activates a proposal as the user', () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      _setPending(coordinator, now);

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui, retiens-le',
        referenceDate: now,
      );

      expect(result?.message, contains('mémorisée'));
      expect(repository.memory.lifecycleState, MemoryLifecycleState.active);
      expect(repository.applied, hasLength(2));
      expect(
        repository.applied.map((mutation) => mutation.newState),
        [MemoryLifecycleState.confirmed, MemoryLifecycleState.active],
      );
      expect(
        repository.applied.every(
          (mutation) => mutation.record.actor == MemoryLifecycleActor.user,
        ),
        isTrue,
      );
      expect(
        MemoryConsumptionPolicy.consumable(
          MemoryContext(memories: [repository.memory]).memories,
          referenceDate: now,
        ),
        hasLength(1),
      );
      expect(coordinator.state.pendingAction, isNull);
    });

    test('rejects a proposal without activating it', () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      _setPending(coordinator, now);

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'ne retiens pas ça',
        referenceDate: now,
      );

      expect(result?.message, contains('ne retiendrai pas'));
      expect(repository.memory.lifecycleState, MemoryLifecycleState.rejected);
      expect(repository.applied, hasLength(1));
      expect(
        MemoryConsumptionPolicy.consumable(
          MemoryContext(memories: [repository.memory]).memories,
          referenceDate: now,
        ),
        isEmpty,
      );
    });

    test('keeps an ambiguous request pending without mutation', () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      _setPending(coordinator, now);

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'peut-être plus tard',
        referenceDate: now,
      );

      expect(result?.message, contains('oui ou non'));
      expect(repository.applied, isEmpty);
      expect(
        coordinator.state.pendingAction?.proposalId,
        'proposal-1',
      );
    });

    test('does not consume an event confirmation', () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      coordinator.setPendingEventConfirmation(_event());

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result, isNull);
      expect(repository.applied, isEmpty);
      expect(
        coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventConfirmation,
      );
    });

    test('requires a stable proposal identifier and an existing pending state',
        () async {
      final repository = _FakeRepository(_memory());
      final coordinator = _coordinator(repository);
      coordinator.setPendingMemoryConfirmation(
        const MemoryConfirmationRequest(
          action: MemoryLifecycleAction.confirm,
          proposalId: '',
          prompt: '',
          changeType: 'proposal',
          sensitivity: LifeContextSensitivity.standard,
          consequence: '',
        ),
        createdAt: now,
      );

      expect(
        await coordinator.resolvePendingMemoryConfirmation(
          answer: 'oui',
          referenceDate: now,
        ),
        isNull,
      );
      expect(repository.applied, isEmpty);
    });

    test('handles missing and terminal proposals without mutation', () async {
      for (final state in [
        null,
        MemoryLifecycleState.rejected,
        MemoryLifecycleState.deleted,
      ]) {
        final repository = _FakeRepository(
          state == null ? null : _memory(state: state),
        );
        final coordinator = _coordinator(repository);
        _setPending(coordinator, now);

        final result = await coordinator.resolvePendingMemoryConfirmation(
          answer: 'oui',
          referenceDate: now,
        );

        expect(result?.message, contains('plus disponible'));
        expect(repository.applied, isEmpty);
      }
    });

    test('reports an already active proposal idempotently', () async {
      final repository = _FakeRepository(
        _memory(state: MemoryLifecycleState.active),
      );
      final coordinator = _coordinator(repository);
      _setPending(coordinator, now);

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );
      final repeated = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result?.message, contains('déjà mémorisée'));
      expect(repeated, isNull);
      expect(repository.applied, isEmpty);
    });

    test('does not announce success when persistence fails', () async {
      final repository = _FakeRepository(_memory(), failWrites: true);
      final coordinator = _coordinator(repository);
      _setPending(coordinator, now);

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result?.message, contains('pas pu enregistrer'));
      expect(repository.memory.lifecycleState, MemoryLifecycleState.proposed);
      expect(
        coordinator.state.pendingAction?.proposalId,
        'proposal-1',
      );
    });

    test('does not confirm an expired proposal', () async {
      final repository = _FakeRepository(
        _memory(validUntil: now.subtract(const Duration(minutes: 1))),
      );
      final coordinator = _coordinator(repository);
      _setPending(coordinator, now);

      final result = await coordinator.resolvePendingMemoryConfirmation(
        answer: 'oui',
        referenceDate: now,
      );

      expect(result?.message, contains('plus disponible'));
      expect(repository.applied, isEmpty);
    });
  });
}

MemoryConfirmationRequest _replacementRequest(DateTime now) {
  return MemoryConfirmationRequest(
    action: MemoryLifecycleAction.replace,
    proposalId: 'proposal-1',
    memoryId: 'existing-1',
    prompt: 'Veux-tu remplacer cette préférence ?',
    changeType: 'memoryReplacementConfirmation',
    sensitivity: LifeContextSensitivity.standard,
    consequence: 'Replacement pending',
    replacementPendingAction: MemoryReplacementPendingAction(
      actionId: 'd' * 64,
      accountScopeFingerprint: 'e' * 64,
      existingMemoryId: 'existing-1',
      proposedMemoryId: 'proposal-1',
      canonicalKey: 'v1|planning|preferred_appointment_period|'
          'authenticated_user|scope|personal_appointments|none',
      expectedExistingRevision: 2,
      expectedProposedRevision: 1,
      contradictionId: 'b' * 64,
      reasonCode:
          MemoryContradictionReasonCode.incompatibleClosedAttributeValues,
      state: MemoryReplacementActionState.pending,
      logicalRequestFingerprint: 'f' * 64,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void _setPending(ConversationCoordinator coordinator, DateTime createdAt) {
  coordinator.setPendingMemoryConfirmation(
    const MemoryConfirmationRequest(
      action: MemoryLifecycleAction.confirm,
      proposalId: 'proposal-1',
      prompt: '',
      newValue: 'Generic preference',
      changeType: 'proposal',
      sensitivity: LifeContextSensitivity.standard,
      consequence: 'Activated after confirmation',
    ),
    createdAt: createdAt,
  );
}

ConversationCoordinator _coordinator(_FakeRepository repository) {
  return ConversationCoordinator(
    backend: _FakeBackend(),
    contextProvider: _FakeContext(),
    memoryLifecycleRepository: repository,
  );
}

LifeMemoryFact _memory({
  MemoryLifecycleState state = MemoryLifecycleState.proposed,
  DateTime? validUntil,
}) {
  return LifeMemoryFact(
    id: 'proposal-1',
    text: 'Generic preference',
    normalizedText: 'generic preference',
    semanticType: LifeMemorySemanticType.preference,
    category: 'preference',
    importance: 1,
    sourceType: LifeContextSourceType.memory,
    confirmationStatus: state == MemoryLifecycleState.active
        ? MemoryConfirmationStatus.confirmed
        : MemoryConfirmationStatus.unconfirmed,
    sensitivity: LifeContextSensitivity.standard,
    evidenceType: LifeContextEvidenceType.explicit,
    lifecycleState: state,
    lifecycleStateIsExplicit: true,
    schemaVersion: 1,
    consumptionTrust: MemoryConsumptionTrust.modernValid,
    validUntil: validUntil,
  );
}

final class _FakeRepository
    implements MemoryLifecycleRepository, MemoryReplacementPendingRepository {
  LifeMemoryFact? _memory;
  final bool failWrites;
  final List<MemoryLifecycleMutation> applied = [];
  MemoryReplacementPendingAction? replacementAction;
  int executionCalls = 0;
  MemoryReplacementExecutionCode executionCode =
      MemoryReplacementExecutionCode.executed;

  _FakeRepository(this._memory, {this.failWrites = false});

  LifeMemoryFact get memory => _memory!;

  @override
  Future<String?> allocateProposalId() async => 'proposal-1';

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {
    if (failWrites) throw StateError('write failed');
    applied.addAll(mutations);
    for (final mutation in mutations) {
      final current = _memory;
      if (current != null && current.id == mutation.memoryId) {
        _memory = _copyWithState(current, mutation.newState);
      }
    }
  }

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {}

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      _memory == null ? const [] : [_memory!];

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async {
    return _memory?.id == memoryId ? _memory : null;
  }

  @override
  Future<MemoryReplacementPersistenceResult?> persistReplacementProposal({
    required MemoryProposal proposal,
    required MemoryLifecycleMutation mutation,
    required MemoryContradictionMatch match,
    required String accountScopeId,
    required String logicalRequestId,
    required DateTime createdAt,
  }) async =>
      null;

  @override
  Future<MemoryReplacementPendingAction?> findPendingReplacement({
    required String accountScopeId,
    required String logicalRequestId,
  }) async =>
      replacementAction;

  @override
  Future<MemoryReplacementPendingAction> updatePendingReplacementState({
    required MemoryReplacementPendingAction action,
    required MemoryReplacementActionState state,
    required DateTime updatedAt,
  }) async {
    replacementAction = action.withState(state, updatedAt);
    return replacementAction!;
  }

  @override
  Future<MemoryReplacementExecutionResult> executeAcceptedMemoryReplacement({
    required MemoryReplacementPendingAction action,
    required String accountScopeId,
    required DateTime referenceDate,
  }) async {
    executionCalls++;
    return MemoryReplacementExecutionResult(executionCode);
  }
}

LifeMemoryFact _copyWithState(
  LifeMemoryFact memory,
  MemoryLifecycleState state,
) {
  return LifeMemoryFact(
    id: memory.id,
    text: memory.text,
    normalizedText: memory.normalizedText,
    semanticType: memory.semanticType,
    category: memory.category,
    importance: memory.importance,
    sourceType: memory.sourceType,
    sourceId: memory.sourceId,
    createdAt: memory.createdAt,
    updatedAt: memory.updatedAt,
    validFrom: memory.validFrom,
    validUntil: memory.validUntil,
    schemaVersion: memory.schemaVersion,
    consumptionTrust: memory.consumptionTrust,
    hasInvalidExpiration: memory.hasInvalidExpiration,
    hasRestrictedSecret: memory.hasRestrictedSecret,
    confirmationStatus: state == MemoryLifecycleState.active
        ? MemoryConfirmationStatus.confirmed
        : memory.confirmationStatus,
    sensitivity: memory.sensitivity,
    evidenceType: memory.evidenceType,
    lifecycleState: state,
    lifecycleStateIsExplicit: true,
    confidence: memory.confidence,
    legacyData: memory.legacyData,
  );
}

final class _FakeBackend implements ChatBackendClient {
  int calls = 0;

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    calls++;
    return const ChatBackendResponse(reply: 'OK', actions: [], memories: []);
  }
}

class _FakeContext implements ConversationContextProvider {
  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    return ChatBackendRequest(
      message: message,
      profile: const {},
      profileContext: const {},
      memories: const [],
      memoryReasoning: const [],
      events: const [],
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final class _MemoryContext extends _FakeContext
    implements MemoryConversationContextProvider {
  @override
  final MemoryLifecycleRepository memoryLifecycleRepository;

  _MemoryContext(
    this.memoryLifecycleRepository, {
    this.returnsProposal = true,
  });

  final bool returnsProposal;

  @override
  Future<MemoryConfirmationRequest?> proposeResponseMemory(dynamic memory) {
    return Future.value(null);
  }

  @override
  Future<MemoryConfirmationRequest?> proposeUserMemory(
    String message, {
    String? logicalRequestId,
    String? resolvedSubjectEntityId,
    MemorySemanticSubjectScope? semanticSubjectScope,
    MemorySemanticContextType? semanticContextType,
    String? semanticContextEntityId,
  }) async {
    if (!returnsProposal) return null;
    return const MemoryConfirmationRequest(
      action: MemoryLifecycleAction.confirm,
      proposalId: 'proposal-1',
      prompt: '',
      newValue: 'Generic preference',
      changeType: 'proposal',
      sensitivity: LifeContextSensitivity.standard,
      consequence: 'Activated after confirmation',
    );
  }
}

UserProfile _profile() {
  return UserProfile(
    firstName: 'User',
    familyStatus: '',
    workStatus: '',
    partnerName: '',
    wantsNotifications: true,
    children: const [],
  );
}

EventModel _event() {
  return EventModel(
    title: 'Activity',
    date: '2026-07-21',
    time: '10:00',
    notes: '',
    category: 'Personal',
    createdAt: DateTime.utc(2026, 7, 20),
    startDateTimeIso: '2026-07-21T10:00:00.000Z',
    durationMinutes: 30,
  );
}
