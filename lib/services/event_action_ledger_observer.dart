import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import 'action_ledger_repository.dart';
import 'action_ledger_service.dart';
import 'action_autonomy_policy_service.dart';
import 'auth_service.dart';

enum EventLedgerDispatchStatus { succeeded, pendingSync, conflict, failed }

final class EventLedgerDispatchResult<T> {
  const EventLedgerDispatchResult(this.status, {this.value, this.revision});
  final EventLedgerDispatchStatus status;
  final T? value;
  final int? revision;
}

abstract final class EventActionLedgerObserver {
  static Future<T> trace<T>({
    required String mutationId,
    required String eventId,
    required int expectedRevision,
    required ActionType actionType,
    required String operationType,
    required ActionUndoStrategy undoStrategy,
    required Future<EventLedgerDispatchResult<T>> Function() dispatch,
  }) async {
    if (Firebase.apps.isEmpty) {
      final result = await dispatch();
      if (result.value == null) {
        throw const FormatException('event_mutation_failed');
      }
      return result.value as T;
    }
    final scope = AuthService.currentUserId;
    if (scope == null || scope.isEmpty) {
      final result = await dispatch();
      if (result.value == null) {
        throw const FormatException('event_mutation_failed');
      }
      return result.value as T;
    }
    final ledger = ActionLedgerService(
      local: const LocalActionLedgerRepository(),
      cloud: FirestoreActionLedgerRepository(
        firestore: FirebaseFirestore.instance,
        currentUid: () => AuthService.currentUserId,
      ),
      currentScope: () => AuthService.currentUserId,
    );
    final policyService = await ActionAutonomyPolicyService.local(
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    final policy = await policyService.load();
    if (policy.mode == ActionAutonomyMode.paused) {
      throw const FormatException('event_mutation_blocked_by_policy');
    }
    final entry = await ledger.begin(
      mutationId: mutationId,
      actionType: actionType,
      domain: ActionLedgerDomain.event,
      origin: ActionOrigin.explicitUserRequest,
      riskLevel: actionType == ActionType.deleteEvent
          ? ActionRiskLevel.destructive
          : ActionRiskLevel.mutation,
      policyMode: policy.mode,
      policyVersion: policy.schemaVersion,
      target: ActionTargetReference(
        domain: ActionLedgerDomain.event,
        entityType: 'event',
        entityId: eventId,
        operationType: operationType,
        revisionBefore: expectedRevision,
        tombstoneBefore: false,
        patchType: 'eventMutation',
        undoStrategy: undoStrategy,
      ),
      undoCapability: ActionUndoCapability(
        type: undoStrategy == ActionUndoStrategy.undoCreateEvent
            ? ActionUndoCapabilityType.conditionallyReversible
            : ActionUndoCapabilityType.unsupportedDomain,
        strategy: undoStrategy,
        reasonCode: undoStrategy == ActionUndoStrategy.undoCreateEvent
            ? 'undo_revision_required'
            : 'undo_event_inverse_unavailable',
        confirmationRequired: true,
        currentRevisionRequired: true,
        domain: ActionLedgerDomain.event,
        riskLevel: ActionRiskLevel.destructive,
      ),
      correlationId: 'ledger-$mutationId',
      provenance: 'event_service',
    );
    final dispatching = entry.status == ActionLedgerStatus.authorized
        ? await ledger.markDispatching(
            entry,
            transitionMutationId: '$mutationId:dispatch',
          )
        : entry;
    final result = await dispatch();
    final outcome = switch (result.status) {
      EventLedgerDispatchStatus.succeeded => ActionOutcome.completed,
      EventLedgerDispatchStatus.pendingSync => ActionOutcome.pendingSync,
      EventLedgerDispatchStatus.conflict => ActionOutcome.conflict,
      EventLedgerDispatchStatus.failed => ActionOutcome.technicalFailure,
    };
    final recorded = await ledger.recordResult(
      dispatching,
      outcome: outcome,
      transitionMutationId: '$mutationId:result',
      resultRevision: result.revision,
    );
    if (outcome == ActionOutcome.completed) {
      await ledger.exposeUndo(
        recorded,
        transitionMutationId: '$mutationId:undo-capability',
      );
    }
    if (result.value == null) {
      throw const FormatException('event_mutation_failed');
    }
    return result.value as T;
  }
}
