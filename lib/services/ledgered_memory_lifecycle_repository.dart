import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_policy.dart';
import '../models/memory_contradiction.dart';
import 'action_ledger_service.dart';
import 'memory_lifecycle_repository.dart';

final class LedgeredMemoryLifecycleRepository
    implements
        MemoryLifecycleRepository,
        MemoryLifecycleReceiptReader,
        MemoryReplacementPendingRepository {
  const LedgeredMemoryLifecycleRepository({
    required MemoryLifecycleRepository delegate,
    required ActionLedgerService ledger,
    required Future<ActionAutonomyPolicy> Function() loadAutonomyPolicy,
    required Future<MemoryPolicy> Function() loadMemoryPolicy,
  })  : _delegate = delegate,
        _ledger = ledger,
        _loadAutonomyPolicy = loadAutonomyPolicy,
        _loadMemoryPolicy = loadMemoryPolicy;

  final MemoryLifecycleRepository _delegate;
  final ActionLedgerService _ledger;
  final Future<ActionAutonomyPolicy> Function() _loadAutonomyPolicy;
  final Future<MemoryPolicy> Function() _loadMemoryPolicy;

  @override
  Future<String?> allocateProposalId() => _delegate.allocateProposalId();

  @override
  Future<List<LifeMemoryFact>> findCandidates(
    MemoryProposal proposal, {
    int limit = 25,
  }) =>
      _delegate.findCandidates(proposal, limit: limit);

  @override
  Future<LifeMemoryFact?> getById(String memoryId) =>
      _delegate.getById(memoryId);

  MemoryReplacementPendingRepository get _replacementDelegate {
    final delegate = _delegate;
    if (delegate is! MemoryReplacementPendingRepository) {
      throw const FormatException(
        'memory_replacement_repository_unsupported',
      );
    }
    return delegate as MemoryReplacementPendingRepository;
  }

  @override
  Future<MemoryReplacementPersistenceResult?> persistReplacementProposal({
    required MemoryProposal proposal,
    required MemoryLifecycleMutation mutation,
    required MemoryContradictionMatch match,
    required String accountScopeId,
    required String logicalRequestId,
    required DateTime createdAt,
  }) =>
      _replacementDelegate.persistReplacementProposal(
        proposal: proposal,
        mutation: mutation,
        match: match,
        accountScopeId: accountScopeId,
        logicalRequestId: logicalRequestId,
        createdAt: createdAt,
      );

  @override
  Future<MemoryReplacementPendingAction?> findPendingReplacement({
    required String accountScopeId,
    required String logicalRequestId,
  }) =>
      _replacementDelegate.findPendingReplacement(
        accountScopeId: accountScopeId,
        logicalRequestId: logicalRequestId,
      );

  @override
  Future<MemoryReplacementPendingAction> updatePendingReplacementState({
    required MemoryReplacementPendingAction action,
    required MemoryReplacementActionState state,
    required DateTime updatedAt,
  }) =>
      _replacementDelegate.updatePendingReplacementState(
        action: action,
        state: state,
        updatedAt: updatedAt,
      );

  @override
  Future<void> createProposal(
    MemoryProposal proposal,
    MemoryLifecycleMutation mutation,
  ) async {
    final autonomy = await _loadAutonomyPolicy();
    final memoryPolicy = await _loadMemoryPolicy();
    if (!_allows(
      autonomy: autonomy,
      memoryPolicy: memoryPolicy,
      isHealth: _isHealthProposal(proposal),
    )) {
      throw const FormatException('memory_mutation_blocked_by_policy');
    }
    await _trace(
      mutation: mutation,
      expectedRevision: 0,
      resultRevision: 1,
      autonomy: autonomy,
      dispatch: () => _delegate.createProposal(proposal, mutation),
    );
  }

  @override
  Future<void> applyMutations(
    List<MemoryLifecycleMutation> mutations,
  ) async {
    if (mutations.isEmpty) return;
    final grouped = <String, List<MemoryLifecycleMutation>>{};
    for (final mutation in mutations) {
      grouped.putIfAbsent(mutation.memoryId, () => []).add(mutation);
    }
    for (final group in grouped.values) {
      final target = await _delegate.getById(group.first.memoryId);
      final receipt = await readTechnicalReceipt(group.first.memoryId);
      if (receipt == null) {
        throw const FormatException('memory_revision_unavailable');
      }
      final autonomy = await _loadAutonomyPolicy();
      final memoryPolicy = await _loadMemoryPolicy();
      if (!_allows(
        autonomy: autonomy,
        memoryPolicy: memoryPolicy,
        isHealth: target?.isExplicitHealth == true,
      )) {
        throw const FormatException('memory_mutation_blocked_by_policy');
      }
      await _trace(
        mutation: group.last,
        expectedRevision: receipt.revision,
        resultRevision: receipt.revision + 1,
        autonomy: autonomy,
        dispatch: () => _delegate.applyMutations(group),
      );
    }
  }

  Future<void> _trace({
    required MemoryLifecycleMutation mutation,
    required int expectedRevision,
    required int resultRevision,
    required ActionAutonomyPolicy autonomy,
    required Future<void> Function() dispatch,
  }) async {
    final mutationId = mutation.record.idempotencyKey;
    var entry = await _ledger.begin(
      mutationId: mutationId,
      actionType: _actionType(mutation.record.action),
      domain: ActionLedgerDomain.memory,
      origin: mutation.record.actor.name == 'user'
          ? ActionOrigin.explicitUserConfirmation
          : ActionOrigin.structuredContinuation,
      riskLevel: mutation.newState.name == 'deleted'
          ? ActionRiskLevel.destructive
          : ActionRiskLevel.sensitiveMutation,
      policyMode: autonomy.mode,
      policyVersion: autonomy.schemaVersion,
      target: ActionTargetReference(
        domain: ActionLedgerDomain.memory,
        entityType: 'memory',
        entityId: mutation.memoryId,
        operationType: mutation.record.action.name,
        revisionBefore: expectedRevision,
        tombstoneBefore: mutation.record.previousState?.name == 'deleted',
        patchType: 'memoryLifecycle',
        undoStrategy: ActionUndoStrategy.irreversible,
      ),
      undoCapability: const ActionUndoCapability(
        type: ActionUndoCapabilityType.irreversible,
        strategy: ActionUndoStrategy.irreversible,
        reasonCode: 'memory_lifecycle_inverse_not_captured',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: ActionLedgerDomain.memory,
        riskLevel: ActionRiskLevel.sensitiveMutation,
      ),
      correlationId: 'ledger-$mutationId',
      provenance: 'memory_lifecycle_repository',
    );
    if (entry.status != ActionLedgerStatus.authorized) return;
    entry = await _ledger.markDispatching(
      entry,
      transitionMutationId: '$mutationId:dispatch',
    );
    try {
      await dispatch();
      final recorded = await _ledger.recordResult(
        entry,
        outcome: ActionOutcome.completed,
        transitionMutationId: '$mutationId:result',
        resultRevision: resultRevision,
      );
      await _ledger.exposeUndo(
        recorded,
        transitionMutationId: '$mutationId:undo-capability',
      );
    } on StateError {
      await _ledger.recordResult(
        entry,
        outcome: ActionOutcome.conflict,
        transitionMutationId: '$mutationId:conflict',
      );
      rethrow;
    } on Object {
      await _ledger.recordResult(
        entry,
        outcome: ActionOutcome.unknownResult,
        transitionMutationId: '$mutationId:unknown',
      );
      rethrow;
    }
  }

  @override
  Future<MemoryLifecycleTechnicalReceipt?> readTechnicalReceipt(
    String memoryId,
  ) async {
    final reader = _delegate;
    return reader is MemoryLifecycleReceiptReader
        ? (reader as MemoryLifecycleReceiptReader)
            .readTechnicalReceipt(memoryId)
        : null;
  }

  static bool _allows({
    required ActionAutonomyPolicy autonomy,
    required MemoryPolicy memoryPolicy,
    required bool isHealth,
  }) =>
      autonomy.mode != ActionAutonomyMode.paused &&
      memoryPolicy.generalMode != MemoryGeneralMode.paused &&
      (!isHealth || memoryPolicy.healthMode == MemoryHealthMode.enabled);

  static bool _isHealthProposal(MemoryProposal proposal) =>
      proposal.sensitivity.name == 'highlySensitive' ||
      const {'health', 'medical', 'sante'}
          .contains(proposal.category.trim().toLowerCase());

  static ActionType _actionType(MemoryLifecycleAction action) =>
      switch (action) {
        MemoryLifecycleAction.propose => ActionType.proposeMemory,
        MemoryLifecycleAction.confirm ||
        MemoryLifecycleAction.activate =>
          ActionType.confirmMemory,
        MemoryLifecycleAction.delete => ActionType.deleteMemory,
        _ => ActionType.correctMemory,
      };
}
