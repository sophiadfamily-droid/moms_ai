import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import '../models/action_inverse_patch.dart';
import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'action_ledger_repository.dart';
import 'action_ledger_service.dart';
import 'auth_service.dart';
import 'revisioned_domain_sync_service.dart';
import 'revisioned_domain_local_repository.dart';

abstract final class RevisionedActionLedgerObserver {
  static Future<RevisionedSyncResult<RevisionedTask>> task(
    String scope,
    TaskMutation mutation,
    Future<RevisionedSyncResult<RevisionedTask>> Function() dispatch,
  ) =>
      _trace(
        scope: scope,
        mutation: mutation,
        actionType: _taskAction(mutation.type),
        domain: ActionLedgerDomain.task,
        risk: mutation.type == TaskMutationType.deleteTask
            ? ActionRiskLevel.destructive
            : ActionRiskLevel.reversibleLowRisk,
        strategy: _taskUndo(mutation.type),
        dispatch: dispatch,
        revisionOf: (value) => value.revision,
      );

  static Future<RevisionedSyncResult<RevisionedShoppingItem>> shopping(
    String scope,
    ShoppingMutation mutation,
    Future<RevisionedSyncResult<RevisionedShoppingItem>> Function() dispatch,
  ) =>
      _trace(
        scope: scope,
        mutation: mutation,
        actionType: _shoppingAction(mutation.type),
        domain: ActionLedgerDomain.shopping,
        risk: mutation.type == ShoppingMutationType.removeItem ||
                mutation.type == ShoppingMutationType.clearList
            ? ActionRiskLevel.destructive
            : ActionRiskLevel.reversibleLowRisk,
        strategy: _shoppingUndo(mutation.type),
        dispatch: dispatch,
        revisionOf: (value) => value.revision,
      );

  static Future<RevisionedSyncResult<RevisionedProfileState>> profile(
    String scope,
    ProfileMutation mutation,
    Future<RevisionedSyncResult<RevisionedProfileState>> Function() dispatch,
  ) =>
      _trace(
        scope: scope,
        mutation: mutation,
        actionType: ActionType.updateProfile,
        domain: ActionLedgerDomain.profile,
        risk: ActionRiskLevel.sensitiveMutation,
        strategy: ActionUndoStrategy.undoProfilePatch,
        dispatch: dispatch,
        revisionOf: (value) => value.revision,
      );

  static Future<RevisionedSyncResult<T>> _trace<T>({
    required String scope,
    required RevisionedDomainMutation mutation,
    required ActionType actionType,
    required ActionLedgerDomain domain,
    required ActionRiskLevel risk,
    required ActionUndoStrategy strategy,
    required Future<RevisionedSyncResult<T>> Function() dispatch,
    required int Function(T value) revisionOf,
  }) async {
    if (AuthService.currentUserId != scope) {
      throw const FormatException('action_ledger_account_mismatch');
    }
    final reference = mutation.actionReference;
    final inversePatch = await _inversePatch(scope, mutation);
    final policyMode = _enumOr(
      ActionAutonomyMode.values,
      reference?.policyMode,
      ActionAutonomyMode.normal,
    );
    final origin = _enumOr(
      ActionOrigin.values,
      reference?.origin,
      ActionOrigin.explicitUserRequest,
    );
    final reversible = strategy == ActionUndoStrategy.undoCreateTask ||
        strategy == ActionUndoStrategy.undoAddShoppingItem ||
        inversePatch != null;
    final service = ActionLedgerService(
      local: const LocalActionLedgerRepository(),
      cloud: FirestoreActionLedgerRepository(
        firestore: FirebaseFirestore.instance,
        currentUid: () => AuthService.currentUserId,
      ),
      currentScope: () => AuthService.currentUserId,
    );
    final entry = await service.begin(
      mutationId: mutation.mutationId,
      actionType: actionType,
      domain: domain,
      origin: origin,
      riskLevel: risk,
      policyMode: policyMode,
      policyVersion: reference?.policyVersion ?? 1,
      sessionGeneration: reference?.sessionGeneration,
      pendingActionId: reference?.pendingActionId,
      target: ActionTargetReference(
        domain: domain,
        entityType: domain.name,
        entityId: mutation.targetId,
        operationType: _operationName(mutation),
        revisionBefore: mutation.expectedRevision,
        tombstoneBefore: false,
        patchType: '${domain.name}Mutation',
        undoStrategy: strategy,
      ),
      undoCapability: ActionUndoCapability(
        type: strategy == ActionUndoStrategy.irreversible
            ? ActionUndoCapabilityType.irreversible
            : reversible
                ? ActionUndoCapabilityType.conditionallyReversible
                : ActionUndoCapabilityType.unsupportedDomain,
        strategy: strategy,
        reasonCode: strategy == ActionUndoStrategy.irreversible
            ? 'undo_irreversible'
            : reversible
                ? 'undo_revision_required'
                : 'undo_inverse_patch_unavailable',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: domain,
        riskLevel: risk,
      ),
      inversePatch: inversePatch,
      correlationId: 'ledger-${mutation.mutationId}',
      provenance: 'revisioned_sync',
    );
    final dispatching = entry.status == ActionLedgerStatus.authorized
        ? await service.markDispatching(
            entry,
            transitionMutationId: '${mutation.mutationId}:dispatch',
          )
        : entry;
    final result = await dispatch();
    final outcome = switch (result.status) {
      RevisionedCloudWriteStatus.success ||
      RevisionedCloudWriteStatus.idempotent =>
        ActionOutcome.completed,
      RevisionedCloudWriteStatus.revisionConflict ||
      RevisionedCloudWriteStatus.mutationConflict =>
        ActionOutcome.conflict,
      RevisionedCloudWriteStatus.unavailable => ActionOutcome.pendingSync,
      RevisionedCloudWriteStatus.corrupted ||
      RevisionedCloudWriteStatus.accountMismatch =>
        ActionOutcome.validationFailure,
      RevisionedCloudWriteStatus.notFound => ActionOutcome.rejected,
    };
    final recorded = await service.recordResult(
      dispatching,
      outcome: outcome,
      transitionMutationId: '${mutation.mutationId}:result',
      resultRevision:
          result.value == null ? null : revisionOf(result.value as T),
    );
    if (outcome == ActionOutcome.completed) {
      await service.exposeUndo(
        recorded,
        transitionMutationId: '${mutation.mutationId}:undo-capability',
      );
    }
    return result;
  }

  static T _enumOr<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) =>
      values.where((value) => value.name == name).firstOrNull ?? fallback;

  static String _operationName(RevisionedDomainMutation mutation) =>
      switch (mutation) {
        TaskMutation(:final type) => type.name,
        ShoppingMutation(:final type) => type.name,
        ProfileMutation(:final type) => type.name,
      };

  static Future<ActionInversePatch?> _inversePatch(
    String scope,
    RevisionedDomainMutation mutation,
  ) async {
    const local = RevisionedDomainLocalRepository();
    return switch (mutation) {
      TaskMutation() => () {
          final matches = <RevisionedTask>[];
          return local.loadTasks(scope).then((values) {
            matches.addAll(
              values.where((value) => value.entityId == mutation.targetId),
            );
            if (matches.isEmpty) return null;
            final value = matches.single;
            final task = value.task;
            return TaskInversePatch(
              title: task.title,
              category: task.category,
              isDone: task.isDone,
              createdAt: task.createdAt,
              isImportant: task.isImportant,
              dueDate: task.dueDate,
              notes: task.notes,
              planning: task.planning,
              priority: task.priority,
              wasTombstone: value.isTombstone,
            );
          });
        }(),
      ShoppingMutation() => local.loadShopping(scope).then((values) {
          final matches =
              values.where((value) => value.entityId == mutation.targetId);
          if (matches.isEmpty) return null;
          final value = matches.single;
          final item = value.item;
          return ShoppingInversePatch(
            title: item.title,
            isBought: item.isBought,
            createdAt: item.createdAt,
            category: item.category,
            notes: item.notes,
            isUrgent: item.isUrgent,
            section: item.section,
            wasTombstone: value.isTombstone,
            clearGeneration: value.clearGeneration,
          );
        }),
      ProfileMutation() => local.loadProfile(scope).then((value) {
          if (value == null) return null;
          final payload = ProfileFieldOwnership.ownedPayload(value.profile);
          try {
            return ProfileInversePatch(
              mutation.changedFields
                  .map(
                    (field) => ProfileInversePatchEntry(
                      field: ProfileOwnedPatchField.values.byName(field),
                      value: ProfilePatchValue.fromOwnedValue(payload[field]),
                    ),
                  )
                  .toList(growable: false),
            );
          } on Object {
            return null;
          }
        }),
    };
  }

  static ActionType _taskAction(TaskMutationType type) => switch (type) {
        TaskMutationType.createTask => ActionType.createTask,
        TaskMutationType.completeTask => ActionType.completeTask,
        TaskMutationType.deleteTask ||
        TaskMutationType.archiveTask =>
          ActionType.deleteTask,
        TaskMutationType.restoreTask => ActionType.updateTask,
        _ => ActionType.updateTask,
      };

  static ActionUndoStrategy _taskUndo(TaskMutationType type) => switch (type) {
        TaskMutationType.createTask => ActionUndoStrategy.undoCreateTask,
        TaskMutationType.completeTask => ActionUndoStrategy.undoCompleteTask,
        TaskMutationType.reopenTask => ActionUndoStrategy.undoReopenTask,
        TaskMutationType.deleteTask ||
        TaskMutationType.archiveTask =>
          ActionUndoStrategy.undoDeleteTask,
        TaskMutationType.restoreTask => ActionUndoStrategy.undoDeleteTask,
        TaskMutationType.updateTask => ActionUndoStrategy.undoUpdateTask,
      };

  static ActionType _shoppingAction(ShoppingMutationType type) =>
      switch (type) {
        ShoppingMutationType.addItem => ActionType.addShoppingItem,
        ShoppingMutationType.removeItem => ActionType.removeShoppingItem,
        ShoppingMutationType.clearList => ActionType.clearShoppingList,
        _ => ActionType.updateShoppingItem,
      };

  static ActionUndoStrategy _shoppingUndo(ShoppingMutationType type) =>
      switch (type) {
        ShoppingMutationType.addItem => ActionUndoStrategy.undoAddShoppingItem,
        ShoppingMutationType.updateItem ||
        ShoppingMutationType.restoreItem =>
          ActionUndoStrategy.undoUpdateShoppingItem,
        ShoppingMutationType.removeItem =>
          ActionUndoStrategy.undoRemoveShoppingItem,
        ShoppingMutationType.clearList => ActionUndoStrategy.irreversible,
      };
}
