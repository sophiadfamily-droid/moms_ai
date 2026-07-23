import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import '../models/action_inverse_patch.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import '../models/shopping_item_model.dart';
import '../models/task_model.dart';
import '../models/user_profile.dart';
import '../models/memory_policy.dart';
import 'action_ledger_service.dart';
import 'action_undo_engine.dart';
import 'event_service.dart';
import 'event_mutation_result.dart';
import 'memory_library_service.dart';
import 'revisioned_domain_local_repository.dart';
import 'revisioned_domain_sync_service.dart';

abstract interface class ActionUndoAdapter {
  ActionLedgerDomain get domain;

  Future<ActionUndoResult> execute({
    required ActionLedgerEntry source,
    required ActionUndoRequest request,
    required bool policyAllowsMutation,
    required bool domainPolicyAllowsMutation,
  });
}

final class EventActionUndoAdapter implements ActionUndoAdapter {
  const EventActionUndoAdapter({
    required ActionLedgerService ledger,
    ActionUndoEngine engine = const ActionUndoEngine(),
  })  : _ledger = ledger,
        _engine = engine;

  final ActionLedgerService _ledger;
  final ActionUndoEngine _engine;

  @override
  ActionLedgerDomain get domain => ActionLedgerDomain.event;

  @override
  Future<ActionUndoResult> execute({
    required ActionLedgerEntry source,
    required ActionUndoRequest request,
    required bool policyAllowsMutation,
    required bool domainPolicyAllowsMutation,
  }) async {
    final matches = (await EventService.getEvents()).where(
      (event) => event.id == source.targetReference.entityId,
    );
    final current = matches.isEmpty ? null : matches.single;
    final evaluation = _engine.evaluate(
      ActionUndoEvaluation(
        entry: source,
        request: ActionUndoRequest(
          undoMutationId: request.undoMutationId,
          sourceLedgerEntryId: request.sourceLedgerEntryId,
          accountScopeId: request.accountScopeId,
          currentRevision: current?.eventRevision ?? -1,
          policyMode: request.policyMode,
          policyVersion: request.policyVersion,
          confirmed: request.confirmed,
          requestedAt: request.requestedAt,
        ),
        policyAllowsMutation: policyAllowsMutation,
        domainPolicyAllowsMutation: domainPolicyAllowsMutation,
        now: request.requestedAt,
      ),
    );
    if (evaluation.type != ActionUndoResultType.ready) return evaluation;
    if (current == null ||
        source.undoCapability.strategy != ActionUndoStrategy.undoCreateEvent) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: source.undoCapability,
        reasonCode: 'undo_event_strategy_not_supported',
      );
    }
    final requested = await _ledger.markUndoRequested(
      source,
      transitionMutationId: '${request.undoMutationId}:requested',
    );
    final dispatching = await _ledger.markUndoDispatching(
      requested,
      transitionMutationId: '${request.undoMutationId}:source-dispatch',
    );
    final result = await EventService.deleteEvent(
      existing: current,
      expectedEventRevision: current.eventRevision,
      mutationId: request.undoMutationId,
    );
    final outcome = switch (result.status) {
      EventMutationStatus.success => ActionOutcome.completed,
      EventMutationStatus.persistenceFailure => ActionOutcome.pendingSync,
      EventMutationStatus.revisionConflict ||
      EventMutationStatus.alreadyExists ||
      EventMutationStatus.scopeMismatch =>
        ActionOutcome.conflict,
      _ => ActionOutcome.rejected,
    };
    await _ledger.recordUndoResult(
      dispatching,
      outcome: outcome,
      transitionMutationId: '${request.undoMutationId}:source-result',
    );
    return ActionUndoResult(
      type: outcome == ActionOutcome.completed
          ? ActionUndoResultType.ready
          : outcome == ActionOutcome.conflict
              ? ActionUndoResultType.targetChanged
              : ActionUndoResultType.conflict,
      capability: source.undoCapability,
      reasonCode: outcome == ActionOutcome.completed
          ? 'undo_completed'
          : 'undo_dispatch_failed',
    );
  }
}

final class TaskActionUndoAdapter implements ActionUndoAdapter {
  const TaskActionUndoAdapter({
    required TaskRevisionSyncService sync,
    required ActionLedgerService ledger,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    ActionUndoEngine engine = const ActionUndoEngine(),
  })  : _sync = sync,
        _ledger = ledger,
        _local = local,
        _engine = engine;

  final TaskRevisionSyncService _sync;
  final ActionLedgerService _ledger;
  final RevisionedDomainLocalRepository _local;
  final ActionUndoEngine _engine;

  @override
  ActionLedgerDomain get domain => ActionLedgerDomain.task;

  @override
  Future<ActionUndoResult> execute({
    required ActionLedgerEntry source,
    required ActionUndoRequest request,
    required bool policyAllowsMutation,
    required bool domainPolicyAllowsMutation,
  }) async {
    final current = (await _local.loadTasks(request.accountScopeId))
        .where((value) => value.entityId == source.targetReference.entityId);
    final revision = current.isEmpty ? -1 : current.single.revision;
    final evaluation = _engine.evaluate(
      ActionUndoEvaluation(
        entry: source,
        request: ActionUndoRequest(
          undoMutationId: request.undoMutationId,
          sourceLedgerEntryId: request.sourceLedgerEntryId,
          accountScopeId: request.accountScopeId,
          currentRevision: revision < 1 ? request.currentRevision : revision,
          policyMode: request.policyMode,
          policyVersion: request.policyVersion,
          confirmed: request.confirmed,
          requestedAt: request.requestedAt,
        ),
        policyAllowsMutation: policyAllowsMutation,
        domainPolicyAllowsMutation: domainPolicyAllowsMutation,
        now: request.requestedAt,
      ),
    );
    final strategy = source.undoCapability.strategy;
    final patch = source.inversePatch;
    final supported = strategy == ActionUndoStrategy.undoCreateTask ||
        patch is TaskInversePatch &&
            {
              ActionUndoStrategy.undoUpdateTask,
              ActionUndoStrategy.undoCompleteTask,
              ActionUndoStrategy.undoReopenTask,
              ActionUndoStrategy.undoDeleteTask,
            }.contains(strategy);
    if (evaluation.type != ActionUndoResultType.ready ||
        current.isEmpty ||
        !supported) {
      return evaluation.type == ActionUndoResultType.ready
          ? ActionUndoResult(
              type: ActionUndoResultType.notSupported,
              capability: source.undoCapability,
              reasonCode: 'undo_task_strategy_not_supported',
            )
          : evaluation;
    }
    final value = current.single;
    final restoringTombstone =
        strategy == ActionUndoStrategy.undoDeleteTask && value.isTombstone;
    if (strategy == ActionUndoStrategy.undoCreateTask && value.isTombstone ||
        strategy != ActionUndoStrategy.undoCreateTask &&
            patch is! TaskInversePatch ||
        strategy != ActionUndoStrategy.undoDeleteTask && value.isTombstone) {
      return ActionUndoResult(
        type: ActionUndoResultType.targetChanged,
        capability: source.undoCapability,
        reasonCode: 'undo_task_tombstone_mismatch',
      );
    }
    final inverseTask = patch is TaskInversePatch
        ? TaskModel(
            id: value.entityId,
            title: patch.title,
            category: patch.category,
            isDone: patch.isDone,
            createdAt: patch.createdAt,
            isImportant: patch.isImportant,
            dueDate: patch.dueDate,
            notes: patch.notes,
            planning: patch.planning,
            priority: patch.priority,
          )
        : value.task;
    final mutationType = strategy == ActionUndoStrategy.undoCreateTask
        ? TaskMutationType.deleteTask
        : restoringTombstone
            ? TaskMutationType.restoreTask
            : TaskMutationType.updateTask;
    final requestedSource = await _ledger.markUndoRequested(
      source,
      transitionMutationId: '${request.undoMutationId}:requested',
    );
    final dispatchingSource = await _ledger.markUndoDispatching(
      requestedSource,
      transitionMutationId: '${request.undoMutationId}:source-dispatch',
    );
    final undoEntry = await _ledger.begin(
      mutationId: request.undoMutationId,
      actionType: mutationType == TaskMutationType.deleteTask
          ? ActionType.deleteTask
          : ActionType.updateTask,
      domain: domain,
      origin: ActionOrigin.explicitUserConfirmation,
      riskLevel: ActionRiskLevel.destructive,
      policyMode: request.policyMode,
      policyVersion: request.policyVersion,
      target: ActionTargetReference(
        domain: domain,
        entityType: 'task',
        entityId: value.entityId,
        operationType: strategy.name,
        revisionBefore: value.revision,
        tombstoneBefore: value.isTombstone,
        patchType: patch?.type ?? 'taskTombstone',
        undoStrategy: ActionUndoStrategy.irreversible,
      ),
      undoCapability: const ActionUndoCapability(
        type: ActionUndoCapabilityType.irreversible,
        strategy: ActionUndoStrategy.irreversible,
        reasonCode: 'undo_of_undo_not_supported',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: ActionLedgerDomain.task,
        riskLevel: ActionRiskLevel.destructive,
      ),
      correlationId: 'undo-${request.undoMutationId}',
      provenance: 'task_undo_adapter',
      parentLedgerEntryId: source.ledgerEntryId,
    );
    final dispatching = await _ledger.markDispatching(
      undoEntry,
      transitionMutationId: '${request.undoMutationId}:dispatch',
    );
    final result = await _sync.apply(
      request.accountScopeId,
      TaskMutation(
        mutationId: request.undoMutationId,
        targetId: value.entityId,
        expectedRevision: value.revision,
        createdAt: request.requestedAt,
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: mutationType,
        task: inverseTask,
      ),
    );
    await _ledger.recordResult(
      dispatching,
      outcome: _outcome(result.status),
      transitionMutationId: '${request.undoMutationId}:result',
      resultRevision: result.value?.revision,
    );
    await _ledger.recordUndoResult(
      dispatchingSource,
      outcome: _outcome(result.status),
      transitionMutationId: '${request.undoMutationId}:source-result',
    );
    return ActionUndoResult(
      type: result.isRealSuccess
          ? ActionUndoResultType.ready
          : result.status == RevisionedCloudWriteStatus.revisionConflict
              ? ActionUndoResultType.targetChanged
              : ActionUndoResultType.conflict,
      capability: source.undoCapability,
      reasonCode:
          result.isRealSuccess ? 'undo_completed' : 'undo_dispatch_failed',
    );
  }
}

final class ShoppingActionUndoAdapter implements ActionUndoAdapter {
  const ShoppingActionUndoAdapter({
    required ShoppingRevisionSyncService sync,
    required ActionLedgerService ledger,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    ActionUndoEngine engine = const ActionUndoEngine(),
  })  : _sync = sync,
        _ledger = ledger,
        _local = local,
        _engine = engine;

  final ShoppingRevisionSyncService _sync;
  final ActionLedgerService _ledger;
  final RevisionedDomainLocalRepository _local;
  final ActionUndoEngine _engine;

  @override
  ActionLedgerDomain get domain => ActionLedgerDomain.shopping;

  @override
  Future<ActionUndoResult> execute({
    required ActionLedgerEntry source,
    required ActionUndoRequest request,
    required bool policyAllowsMutation,
    required bool domainPolicyAllowsMutation,
  }) async {
    final current = (await _local.loadShopping(request.accountScopeId))
        .where((value) => value.entityId == source.targetReference.entityId);
    final revision = current.isEmpty ? -1 : current.single.revision;
    final evaluation = _engine.evaluate(
      ActionUndoEvaluation(
        entry: source,
        request: ActionUndoRequest(
          undoMutationId: request.undoMutationId,
          sourceLedgerEntryId: request.sourceLedgerEntryId,
          accountScopeId: request.accountScopeId,
          currentRevision: revision < 1 ? request.currentRevision : revision,
          policyMode: request.policyMode,
          policyVersion: request.policyVersion,
          confirmed: request.confirmed,
          requestedAt: request.requestedAt,
        ),
        policyAllowsMutation: policyAllowsMutation,
        domainPolicyAllowsMutation: domainPolicyAllowsMutation,
        now: request.requestedAt,
      ),
    );
    final strategy = source.undoCapability.strategy;
    final patch = source.inversePatch;
    final supported = strategy == ActionUndoStrategy.undoAddShoppingItem ||
        patch is ShoppingInversePatch &&
            {
              ActionUndoStrategy.undoUpdateShoppingItem,
              ActionUndoStrategy.undoRemoveShoppingItem,
            }.contains(strategy);
    if (evaluation.type != ActionUndoResultType.ready ||
        current.isEmpty ||
        !supported) {
      return evaluation.type == ActionUndoResultType.ready
          ? ActionUndoResult(
              type: ActionUndoResultType.notSupported,
              capability: source.undoCapability,
              reasonCode: 'undo_shopping_strategy_not_supported',
            )
          : evaluation;
    }
    final value = current.single;
    final restoring = strategy == ActionUndoStrategy.undoRemoveShoppingItem &&
        value.isTombstone;
    if (strategy == ActionUndoStrategy.undoAddShoppingItem &&
            value.isTombstone ||
        strategy != ActionUndoStrategy.undoAddShoppingItem &&
            patch is! ShoppingInversePatch ||
        strategy != ActionUndoStrategy.undoRemoveShoppingItem &&
            value.isTombstone ||
        patch is ShoppingInversePatch &&
            patch.clearGeneration != value.clearGeneration) {
      return ActionUndoResult(
        type: ActionUndoResultType.targetChanged,
        capability: source.undoCapability,
        reasonCode: 'undo_shopping_state_mismatch',
      );
    }
    final inverseItem = patch is ShoppingInversePatch
        ? ShoppingItemModel(
            id: value.entityId,
            title: patch.title,
            isBought: patch.isBought,
            createdAt: patch.createdAt,
            category: patch.category,
            notes: patch.notes,
            isUrgent: patch.isUrgent,
            section: patch.section,
          )
        : value.item;
    final mutationType = strategy == ActionUndoStrategy.undoAddShoppingItem
        ? ShoppingMutationType.removeItem
        : restoring
            ? ShoppingMutationType.restoreItem
            : ShoppingMutationType.updateItem;
    final requestedSource = await _ledger.markUndoRequested(
      source,
      transitionMutationId: '${request.undoMutationId}:requested',
    );
    final dispatchingSource = await _ledger.markUndoDispatching(
      requestedSource,
      transitionMutationId: '${request.undoMutationId}:source-dispatch',
    );
    final undoEntry = await _ledger.begin(
      mutationId: request.undoMutationId,
      actionType: mutationType == ShoppingMutationType.removeItem
          ? ActionType.removeShoppingItem
          : ActionType.updateShoppingItem,
      domain: domain,
      origin: ActionOrigin.explicitUserConfirmation,
      riskLevel: ActionRiskLevel.destructive,
      policyMode: request.policyMode,
      policyVersion: request.policyVersion,
      target: ActionTargetReference(
        domain: domain,
        entityType: 'shopping',
        entityId: value.entityId,
        operationType: strategy.name,
        revisionBefore: value.revision,
        tombstoneBefore: value.isTombstone,
        patchType: patch?.type ?? 'shoppingTombstone',
        undoStrategy: ActionUndoStrategy.irreversible,
      ),
      undoCapability: const ActionUndoCapability(
        type: ActionUndoCapabilityType.irreversible,
        strategy: ActionUndoStrategy.irreversible,
        reasonCode: 'undo_of_undo_not_supported',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: ActionLedgerDomain.shopping,
        riskLevel: ActionRiskLevel.destructive,
      ),
      correlationId: 'undo-${request.undoMutationId}',
      provenance: 'shopping_undo_adapter',
      parentLedgerEntryId: source.ledgerEntryId,
    );
    final dispatching = await _ledger.markDispatching(
      undoEntry,
      transitionMutationId: '${request.undoMutationId}:dispatch',
    );
    final result = await _sync.apply(
      request.accountScopeId,
      ShoppingMutation(
        mutationId: request.undoMutationId,
        targetId: value.entityId,
        expectedRevision: value.revision,
        createdAt: request.requestedAt,
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: mutationType,
        item: inverseItem,
        clearGeneration: value.clearGeneration,
      ),
    );
    await _ledger.recordResult(
      dispatching,
      outcome: _outcome(result.status),
      transitionMutationId: '${request.undoMutationId}:result',
      resultRevision: result.value?.revision,
    );
    await _ledger.recordUndoResult(
      dispatchingSource,
      outcome: _outcome(result.status),
      transitionMutationId: '${request.undoMutationId}:source-result',
    );
    return ActionUndoResult(
      type: result.isRealSuccess
          ? ActionUndoResultType.ready
          : result.status == RevisionedCloudWriteStatus.revisionConflict
              ? ActionUndoResultType.targetChanged
              : ActionUndoResultType.conflict,
      capability: source.undoCapability,
      reasonCode:
          result.isRealSuccess ? 'undo_completed' : 'undo_dispatch_failed',
    );
  }
}

final class ProfileActionUndoAdapter implements ActionUndoAdapter {
  const ProfileActionUndoAdapter({
    required ProfileRevisionSyncService sync,
    required ActionLedgerService ledger,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    ActionUndoEngine engine = const ActionUndoEngine(),
  })  : _sync = sync,
        _ledger = ledger,
        _local = local,
        _engine = engine;

  final ProfileRevisionSyncService _sync;
  final ActionLedgerService _ledger;
  final RevisionedDomainLocalRepository _local;
  final ActionUndoEngine _engine;

  @override
  ActionLedgerDomain get domain => ActionLedgerDomain.profile;

  @override
  Future<ActionUndoResult> execute({
    required ActionLedgerEntry source,
    required ActionUndoRequest request,
    required bool policyAllowsMutation,
    required bool domainPolicyAllowsMutation,
  }) async {
    final current = await _local.loadProfile(request.accountScopeId);
    final evaluation = _engine.evaluate(
      ActionUndoEvaluation(
        entry: source,
        request: request,
        policyAllowsMutation: policyAllowsMutation,
        domainPolicyAllowsMutation: domainPolicyAllowsMutation,
        now: request.requestedAt,
      ),
    );
    final patch = source.inversePatch;
    if (evaluation.type != ActionUndoResultType.ready) return evaluation;
    if (current == null ||
        current.revision != source.resultRevision ||
        patch is! ProfileInversePatch) {
      return ActionUndoResult(
        type: ActionUndoResultType.targetChanged,
        capability: source.undoCapability,
        reasonCode: 'undo_profile_target_changed',
      );
    }
    final restoredJson = current.profile.toJson();
    for (final entry in patch.entries) {
      restoredJson[entry.field.name] = entry.value.value;
    }
    final restored = UserProfile.fromJson(restoredJson);
    final requested = await _ledger.markUndoRequested(
      source,
      transitionMutationId: '${request.undoMutationId}:requested',
    );
    final sourceDispatching = await _ledger.markUndoDispatching(
      requested,
      transitionMutationId: '${request.undoMutationId}:source-dispatch',
    );
    final undoEntry = await _ledger.begin(
      mutationId: request.undoMutationId,
      actionType: ActionType.updateProfile,
      domain: domain,
      origin: ActionOrigin.explicitUserConfirmation,
      riskLevel: ActionRiskLevel.sensitiveMutation,
      policyMode: request.policyMode,
      policyVersion: request.policyVersion,
      target: ActionTargetReference(
        domain: domain,
        entityType: 'profile',
        entityId: RevisionedProfileState.entityId,
        operationType: 'undoProfilePatch',
        revisionBefore: current.revision,
        tombstoneBefore: false,
        patchType: 'profileOwnedPatch',
        undoStrategy: ActionUndoStrategy.irreversible,
      ),
      undoCapability: const ActionUndoCapability(
        type: ActionUndoCapabilityType.irreversible,
        strategy: ActionUndoStrategy.irreversible,
        reasonCode: 'undo_of_undo_not_supported',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: ActionLedgerDomain.profile,
        riskLevel: ActionRiskLevel.sensitiveMutation,
      ),
      correlationId: 'undo-${request.undoMutationId}',
      provenance: 'profile_undo_adapter',
      parentLedgerEntryId: source.ledgerEntryId,
    );
    final dispatching = await _ledger.markDispatching(
      undoEntry,
      transitionMutationId: '${request.undoMutationId}:dispatch',
    );
    final result = await _sync.apply(
      request.accountScopeId,
      ProfileMutation(
        mutationId: request.undoMutationId,
        targetId: RevisionedProfileState.entityId,
        expectedRevision: current.revision,
        createdAt: request.requestedAt,
        attempt: 0,
        nextRetryAt: null,
        state: RevisionedMutationState.queued,
        type: ProfileMutationType.updateProfileFields,
        changedFields: patch.entries.map((entry) => entry.field.name).toSet(),
        profile: restored,
      ),
    );
    final outcome = _outcome(result.status);
    await _ledger.recordResult(
      dispatching,
      outcome: outcome,
      transitionMutationId: '${request.undoMutationId}:result',
      resultRevision: result.value?.revision,
    );
    await _ledger.recordUndoResult(
      sourceDispatching,
      outcome: outcome,
      transitionMutationId: '${request.undoMutationId}:source-result',
    );
    return ActionUndoResult(
      type: result.isRealSuccess
          ? ActionUndoResultType.ready
          : result.status == RevisionedCloudWriteStatus.revisionConflict
              ? ActionUndoResultType.targetChanged
              : ActionUndoResultType.conflict,
      capability: source.undoCapability,
      reasonCode:
          result.isRealSuccess ? 'undo_completed' : 'undo_dispatch_failed',
    );
  }
}

final class MemoryActionUndoAdapter implements ActionUndoAdapter {
  const MemoryActionUndoAdapter({
    required MemoryLibraryService library,
    required ActionLedgerService ledger,
    ActionUndoEngine engine = const ActionUndoEngine(),
  })  : _library = library,
        _ledger = ledger,
        _engine = engine;

  final MemoryLibraryService _library;
  final ActionLedgerService _ledger;
  final ActionUndoEngine _engine;

  @override
  ActionLedgerDomain get domain => ActionLedgerDomain.memory;

  @override
  Future<ActionUndoResult> execute({
    required ActionLedgerEntry source,
    required ActionUndoRequest request,
    required bool policyAllowsMutation,
    required bool domainPolicyAllowsMutation,
  }) async {
    final snapshot = await _library.load();
    final matches = snapshot.memories.where(
      (memory) => memory.memoryId == source.targetReference.entityId,
    );
    final current = matches.isEmpty ? null : matches.single;
    final patch = source.inversePatch;
    final evaluation = _engine.evaluate(
      ActionUndoEvaluation(
        entry: source,
        request: ActionUndoRequest(
          undoMutationId: request.undoMutationId,
          sourceLedgerEntryId: request.sourceLedgerEntryId,
          accountScopeId: request.accountScopeId,
          currentRevision: current?.memoryRevision ?? -1,
          policyMode: request.policyMode,
          policyVersion: request.policyVersion,
          confirmed: request.confirmed,
          requestedAt: request.requestedAt,
        ),
        policyAllowsMutation: policyAllowsMutation,
        domainPolicyAllowsMutation: domainPolicyAllowsMutation &&
            !(patch is MemoryInversePatch &&
                patch.isHealth &&
                snapshot.policy.healthMode == MemoryHealthMode.disabled),
        now: request.requestedAt,
      ),
    );
    if (evaluation.type != ActionUndoResultType.ready) return evaluation;
    if (current == null || patch is! MemoryInversePatch) {
      return ActionUndoResult(
        type: ActionUndoResultType.notSupported,
        capability: source.undoCapability,
        reasonCode: 'undo_memory_patch_unavailable',
      );
    }
    final requested = await _ledger.markUndoRequested(
      source,
      transitionMutationId: '${request.undoMutationId}:requested',
    );
    final sourceDispatching = await _ledger.markUndoDispatching(
      requested,
      transitionMutationId: '${request.undoMutationId}:source-dispatch',
    );
    final undoEntry = await _ledger.begin(
      mutationId: request.undoMutationId,
      actionType: ActionType.correctMemory,
      domain: domain,
      origin: ActionOrigin.explicitUserConfirmation,
      riskLevel: ActionRiskLevel.sensitiveMutation,
      policyMode: request.policyMode,
      policyVersion: request.policyVersion,
      target: ActionTargetReference(
        domain: domain,
        entityType: 'memory',
        entityId: current.memoryId,
        operationType: source.undoCapability.strategy.name,
        revisionBefore: current.memoryRevision,
        tombstoneBefore: current.tombstone,
        patchType: 'memoryInverse',
        undoStrategy: ActionUndoStrategy.irreversible,
      ),
      undoCapability: const ActionUndoCapability(
        type: ActionUndoCapabilityType.irreversible,
        strategy: ActionUndoStrategy.irreversible,
        reasonCode: 'undo_of_undo_not_supported',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: ActionLedgerDomain.memory,
        riskLevel: ActionRiskLevel.sensitiveMutation,
      ),
      correlationId: 'undo-${request.undoMutationId}',
      provenance: 'memory_undo_adapter',
      parentLedgerEntryId: source.ledgerEntryId,
    );
    final dispatching = await _ledger.markDispatching(
      undoEntry,
      transitionMutationId: '${request.undoMutationId}:dispatch',
    );
    final result = await _library.applyInversePatch(
      memoryId: current.memoryId,
      patch: patch,
      mutationId: request.undoMutationId,
    );
    final outcome = switch (result.status) {
      MemoryLibraryActionStatus.synced => ActionOutcome.completed,
      MemoryLibraryActionStatus.pendingSync => ActionOutcome.pendingSync,
      MemoryLibraryActionStatus.conflict => ActionOutcome.conflict,
      MemoryLibraryActionStatus.blockedByPolicy => ActionOutcome.policyBlocked,
      _ => ActionOutcome.validationFailure,
    };
    await _ledger.recordResult(
      dispatching,
      outcome: outcome,
      transitionMutationId: '${request.undoMutationId}:result',
      resultRevision: outcome == ActionOutcome.completed
          ? current.memoryRevision + 1
          : null,
    );
    await _ledger.recordUndoResult(
      sourceDispatching,
      outcome: outcome,
      transitionMutationId: '${request.undoMutationId}:source-result',
    );
    return ActionUndoResult(
      type: outcome == ActionOutcome.completed
          ? ActionUndoResultType.ready
          : outcome == ActionOutcome.policyBlocked
              ? ActionUndoResultType.blockedByPolicy
              : ActionUndoResultType.conflict,
      capability: source.undoCapability,
      reasonCode: outcome == ActionOutcome.completed
          ? 'undo_completed'
          : 'undo_dispatch_failed',
    );
  }
}

ActionOutcome _outcome(RevisionedCloudWriteStatus status) => switch (status) {
      RevisionedCloudWriteStatus.success ||
      RevisionedCloudWriteStatus.idempotent =>
        ActionOutcome.completed,
      RevisionedCloudWriteStatus.unavailable => ActionOutcome.pendingSync,
      RevisionedCloudWriteStatus.revisionConflict ||
      RevisionedCloudWriteStatus.mutationConflict =>
        ActionOutcome.conflict,
      RevisionedCloudWriteStatus.accountMismatch ||
      RevisionedCloudWriteStatus.corrupted =>
        ActionOutcome.validationFailure,
      RevisionedCloudWriteStatus.notFound => ActionOutcome.rejected,
    };
