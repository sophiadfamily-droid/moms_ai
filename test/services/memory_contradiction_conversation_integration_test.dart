import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_evidence.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_contradiction.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/models/memory_semantic_identity.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/memory_lifecycle_repository.dart';
import 'package:moms_ai/services/memory_proposal_factory.dart';

void main() {
  final now = DateTime.utc(2026, 7, 26, 10);

  test('direct correction creates one proposed replacement pending', () async {
    final repository = _Repository(_confirmedMorning(now));
    final provider = DefaultConversationContextProvider(
      loadAccountScope: () async => 'account-a',
      memoryLifecycleRepository: repository,
      loadMemoryPolicy: () async => MemoryPolicy.restrictiveDefault(
        accountScopeId: 'account-a',
        changedAt: now,
      ),
    );

    final first = await provider.proposeUserMemory(
      'Finalement, je préfère mes rendez-vous l’après-midi.',
      logicalRequestId: 'logical-1',
    );
    final retry = await provider.proposeUserMemory(
      'Finalement, je préfère mes rendez-vous l’après-midi.',
      logicalRequestId: 'logical-1',
    );

    expect(first?.action, MemoryLifecycleAction.replace);
    expect(first?.changeType, 'memoryReplacementConfirmation');
    expect(first?.contradictionCandidate?.existingMemoryId, 'memory-1');
    expect(first?.contradictionCandidate?.existingRevision, 3);
    expect(repository.created, hasLength(1));
    expect(repository.created.single.proposal.id, hasLength(64));
    expect(repository.created.single.mutation.newState,
        MemoryLifecycleState.proposed);
    expect(repository.appliedMutations, isEmpty);
    expect(retry?.contradictionCandidate?.contradictionId,
        first?.contradictionCandidate?.contradictionId);
    expect(repository.created.single.mutation.record.metadata.toString(),
        isNot(contains('morning')));
    expect(repository.created.single.mutation.record.metadata.toString(),
        isNot(contains('afternoon')));

    final distinct = await provider.proposeUserMemory(
      'Finalement, je préfère mes rendez-vous l’après-midi.',
      logicalRequestId: 'logical-2',
    );
    expect(distinct?.proposalId, isNot(first?.proposalId));
    expect(repository.created, hasLength(2));
  });
}

LifeMemoryFact _confirmedMorning(DateTime now) {
  final proposal = const MemoryProposalFactory().fromHistoricalPayload(
    id: 'old-identity',
    payload: const {
      'text': 'Je préfère mes rendez-vous le matin.',
      'category': 'preference',
      'importance': 2,
    },
    source: 'explicit_user_message',
    proposedAt: now,
    evidenceQualification: MemoryEvidenceQualification(
      classification: MemoryEvidenceClassification.directExplicit,
      subjectType: MemoryEvidenceSubjectType.user,
      canConfirmImmediately: true,
      isCorrection: false,
    ),
  )!;
  return LifeMemoryFact(
    id: 'memory-1',
    text: proposal.text,
    normalizedText: proposal.normalizedText,
    semanticType: proposal.semanticType,
    category: proposal.category,
    importance: proposal.importance,
    sourceType: LifeContextSourceType.memory,
    confirmationStatus: MemoryConfirmationStatus.confirmed,
    sensitivity: LifeContextSensitivity.standard,
    evidenceType: LifeContextEvidenceType.explicit,
    lifecycleState: MemoryLifecycleState.active,
    lifecycleStateIsExplicit: true,
    consumptionTrust: MemoryConsumptionTrust.modernValid,
    schemaVersion: 1,
    semanticIdentityRead:
        MemorySemanticIdentityReadResult.valid(proposal.semanticIdentity!),
    semanticValue: proposal.semanticValue,
    memoryRevision: 3,
    accountScopeId: 'account-a',
  );
}

final class _Created {
  const _Created(this.proposal, this.mutation);
  final MemoryProposal proposal;
  final MemoryLifecycleMutation mutation;
}

final class _Repository
    implements MemoryLifecycleRepository, MemoryReplacementPendingRepository {
  _Repository(this.existing);

  final LifeMemoryFact existing;
  final List<_Created> created = [];
  final List<MemoryLifecycleMutation> appliedMutations = [];
  int allocations = 0;
  MemoryReplacementPendingAction? pending;

  @override
  Future<String?> allocateProposalId() async => 'allocated-${++allocations}';

  @override
  Future<void> applyMutations(List<MemoryLifecycleMutation> mutations) async {
    appliedMutations.addAll(mutations);
  }

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    if (created.any((item) => item.proposal.id == proposal.id)) return;
    created.add(_Created(proposal, mutation));
  }

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) async =>
      [existing];

  @override
  Future<LifeMemoryFact?> getById(String memoryId) async =>
      memoryId == existing.id ? existing : null;

  @override
  Future<MemoryReplacementPersistenceResult?> persistReplacementProposal({
    required MemoryProposal proposal,
    required MemoryLifecycleMutation mutation,
    required MemoryContradictionMatch match,
    required String accountScopeId,
    required String logicalRequestId,
    required DateTime createdAt,
  }) async {
    if (created.every((item) => item.proposal.id != proposal.id)) {
      created.add(_Created(proposal, mutation));
    }
    final candidate = MemoryContradictionCandidate(
      contradictionId: 'b' * 64,
      existingMemoryId: match.existingMemoryId,
      proposedMemoryId: proposal.id,
      canonicalKey: match.canonicalKey,
      existingRevision: match.existingRevision,
      proposedRevision: 1,
      existingValueFingerprint: match.existingValueFingerprint,
      proposedValueFingerprint: match.proposedValueFingerprint,
      subjectScope: match.subjectScope,
      detectedAt: createdAt.toUtc(),
      reasonCode: match.reasonCode,
      eligibleForReplacement: true,
    );
    if (pending?.proposedMemoryId != proposal.id) {
      pending = MemoryReplacementPendingAction(
        actionId: proposal.id,
        accountScopeFingerprint: 'c' * 64,
        existingMemoryId: match.existingMemoryId,
        proposedMemoryId: proposal.id,
        canonicalKey: match.canonicalKey,
        expectedExistingRevision: match.existingRevision,
        expectedProposedRevision: 1,
        contradictionId: candidate.contradictionId,
        reasonCode: match.reasonCode,
        state: MemoryReplacementActionState.pending,
        logicalRequestFingerprint: 'd' * 64,
        createdAt: createdAt.toUtc(),
        updatedAt: createdAt.toUtc(),
      );
    }
    return MemoryReplacementPersistenceResult(
      action: pending!,
      candidate: candidate,
    );
  }

  @override
  Future<MemoryReplacementPendingAction?> findPendingReplacement({
    required String accountScopeId,
    required String logicalRequestId,
  }) async =>
      pending;

  @override
  Future<MemoryReplacementPendingAction> updatePendingReplacementState({
    required MemoryReplacementPendingAction action,
    required MemoryReplacementActionState state,
    required DateTime updatedAt,
  }) async {
    pending = action.withState(state, updatedAt);
    return pending!;
  }

  @override
  Future<MemoryReplacementExecutionResult> executeAcceptedMemoryReplacement({
    required MemoryReplacementPendingAction action,
    required String accountScopeId,
    required DateTime referenceDate,
  }) async =>
      const MemoryReplacementExecutionResult(
        MemoryReplacementExecutionCode.executed,
      );
}
