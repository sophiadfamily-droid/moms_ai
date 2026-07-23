import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import '../models/action_inverse_patch.dart';
import 'action_ledger_repository.dart';
import 'auth_service.dart';

final class ActionLedgerService {
  const ActionLedgerService({
    required ActionLedgerRepository local,
    ActionLedgerRepository? cloud,
    required String? Function() currentScope,
    DateTime Function()? now,
  })  : _local = local,
        _cloud = cloud,
        _currentScope = currentScope,
        _now = now;

  final ActionLedgerRepository _local;
  final ActionLedgerRepository? _cloud;
  final String? Function() _currentScope;
  final DateTime Function()? _now;

  static ActionLedgerService production() => ActionLedgerService(
        local: const LocalActionLedgerRepository(),
        cloud: FirestoreActionLedgerRepository(
          firestore: FirebaseFirestore.instance,
          currentUid: () => AuthService.currentUserId,
        ),
        currentScope: () => AuthService.currentUserId,
      );

  Future<ActionLedgerEntry> begin({
    required String mutationId,
    required ActionType actionType,
    required ActionLedgerDomain domain,
    required ActionOrigin origin,
    required ActionRiskLevel riskLevel,
    required ActionAutonomyMode policyMode,
    required int policyVersion,
    required ActionTargetReference target,
    required ActionUndoCapability undoCapability,
    ActionInversePatch? inversePatch,
    required String correlationId,
    required String provenance,
    int? sessionGeneration,
    String? requestId,
    String? pendingActionId,
    bool awaitingConfirmation = false,
    String? parentLedgerEntryId,
  }) async {
    final scope = _scope();
    final existing = await _local.findByMutationId(scope, mutationId);
    if (existing != null) {
      if (existing.actionType != actionType ||
          existing.actionDomain != domain ||
          existing.targetReference.entityId != target.entityId) {
        throw const FormatException('action_ledger_idempotency_conflict');
      }
      return existing;
    }
    final instant = (_now ?? DateTime.now)().toUtc();
    final entry = ActionLedgerEntry(
      ledgerEntryId: _ledgerId(mutationId),
      accountScopeId: scope,
      actionType: actionType,
      actionDomain: domain,
      actionOrigin: origin,
      riskLevel: riskLevel,
      policyModeObserved: policyMode,
      policyVersionObserved: policyVersion,
      sessionGeneration: sessionGeneration,
      requestId: requestId,
      pendingActionId: pendingActionId,
      mutationId: mutationId,
      targetReference: target,
      expectedRevision: target.revisionBefore,
      status: awaitingConfirmation
          ? ActionLedgerStatus.awaitingConfirmation
          : ActionLedgerStatus.authorized,
      outcome: ActionOutcome.unknownResult,
      createdAt: instant,
      authorizedAt: awaitingConfirmation ? null : instant,
      updatedAt: instant,
      undoCapability: undoCapability,
      inversePatch: inversePatch,
      parentLedgerEntryId: parentLedgerEntryId,
      causationLedgerEntryId: parentLedgerEntryId,
      correlationId: correlationId,
      provenance: provenance,
      lastMutationId: mutationId,
    );
    await _local.create(entry);
    try {
      await _cloud?.create(entry);
    } on Object {
      // The local authorized entry is the recovery anchor. It is reconciled
      // without replaying the domain mutation.
    }
    return entry;
  }

  Future<ActionLedgerEntry> markDispatching(
    ActionLedgerEntry entry, {
    required String transitionMutationId,
  }) =>
      _transition(
        entry,
        status: ActionLedgerStatus.dispatching,
        outcome: ActionOutcome.unknownResult,
        transitionMutationId: transitionMutationId,
      );

  Future<ActionLedgerEntry> recordResult(
    ActionLedgerEntry entry, {
    required ActionOutcome outcome,
    required String transitionMutationId,
    int? resultRevision,
    ActionUndoCapability? undoCapability,
  }) {
    final status = switch (outcome) {
      ActionOutcome.completed => ActionLedgerStatus.succeeded,
      ActionOutcome.pendingSync => ActionLedgerStatus.pendingSync,
      ActionOutcome.conflict => ActionLedgerStatus.conflict,
      ActionOutcome.policyBlocked => ActionLedgerStatus.blockedByPolicy,
      ActionOutcome.cancelled => ActionLedgerStatus.cancelled,
      ActionOutcome.rejected ||
      ActionOutcome.validationFailure ||
      ActionOutcome.technicalFailure =>
        ActionLedgerStatus.failed,
      ActionOutcome.unknownResult => ActionLedgerStatus.pendingSync,
    };
    return _transition(
      entry,
      status: status,
      outcome: outcome,
      transitionMutationId: transitionMutationId,
      resultRevision: resultRevision,
      undoCapability: undoCapability,
    );
  }

  Future<ActionLedgerEntry> exposeUndo(
    ActionLedgerEntry entry, {
    required String transitionMutationId,
  }) {
    final reversible =
        entry.undoCapability.type == ActionUndoCapabilityType.reversible ||
            entry.undoCapability.type ==
                ActionUndoCapabilityType.conditionallyReversible;
    return _transition(
      entry,
      status: reversible
          ? ActionLedgerStatus.undoAvailable
          : ActionLedgerStatus.notUndoable,
      outcome: entry.outcome,
      transitionMutationId: transitionMutationId,
    );
  }

  Future<ActionLedgerEntry> markUndoRequested(
    ActionLedgerEntry entry, {
    required String transitionMutationId,
  }) =>
      _transition(
        entry,
        status: ActionLedgerStatus.undoRequested,
        outcome: entry.outcome,
        transitionMutationId: transitionMutationId,
      );

  Future<ActionLedgerEntry> markUndoDispatching(
    ActionLedgerEntry entry, {
    required String transitionMutationId,
  }) =>
      _transition(
        entry,
        status: ActionLedgerStatus.undoDispatching,
        outcome: entry.outcome,
        transitionMutationId: transitionMutationId,
      );

  Future<ActionLedgerEntry> recordUndoResult(
    ActionLedgerEntry entry, {
    required ActionOutcome outcome,
    required String transitionMutationId,
  }) =>
      _transition(
        entry,
        status: switch (outcome) {
          ActionOutcome.completed => ActionLedgerStatus.undone,
          ActionOutcome.pendingSync ||
          ActionOutcome.unknownResult =>
            ActionLedgerStatus.undoPendingSync,
          ActionOutcome.conflict => ActionLedgerStatus.undoConflict,
          _ => ActionLedgerStatus.undoFailed,
        },
        outcome: outcome,
        transitionMutationId: transitionMutationId,
      );

  Future<ActionLedgerEntry> reconcileResult(
    ActionLedgerEntry entry, {
    required ActionOutcome outcome,
    required String transitionMutationId,
    int? resultRevision,
  }) {
    if (entry.status == ActionLedgerStatus.undoDispatching ||
        entry.status == ActionLedgerStatus.undoPendingSync) {
      return recordUndoResult(
        entry,
        outcome: outcome,
        transitionMutationId: transitionMutationId,
      );
    }
    return recordResult(
      entry,
      outcome: outcome,
      transitionMutationId: transitionMutationId,
      resultRevision: resultRevision,
    );
  }

  Future<ActionLedgerPage> history({int limit = 30, String? cursor}) =>
      _local.page(_scope(), limit: limit, cursor: cursor);

  Future<ActionLedgerPage> bootstrap({int limit = 50}) async {
    final scope = _scope();
    final local = await _local.page(scope, limit: limit);
    final cloudRepository = _cloud;
    if (cloudRepository == null) return local;
    try {
      final cloud = await cloudRepository.page(scope, limit: limit);
      for (final remote in cloud.entries) {
        final localEntry = await _local.findById(scope, remote.ledgerEntryId);
        if (localEntry == null ||
            remote.ledgerRevision > localEntry.ledgerRevision) {
          await _local.importBootstrapSnapshot(remote);
        }
      }
      // An incomplete ledger is never sufficient authority to replay a domain
      // mutation. Reconciliation only imports confirmed ledger revisions.
      return _local.page(scope, limit: limit);
    } on Object {
      return local;
    }
  }

  Future<ActionLedgerEntry> _transition(
    ActionLedgerEntry entry, {
    required ActionLedgerStatus status,
    required ActionOutcome outcome,
    required String transitionMutationId,
    int? resultRevision,
    ActionUndoCapability? undoCapability,
  }) async {
    if (entry.accountScopeId != _scope()) {
      throw const FormatException('action_ledger_account_mismatch');
    }
    final next = entry.transition(
      nextStatus: status,
      nextOutcome: outcome,
      at: (_now ?? DateTime.now)().toUtc(),
      transitionMutationId: transitionMutationId,
      resultRevision: resultRevision,
      undoCapability: undoCapability,
    );
    await _local.update(
      next,
      expectedLedgerRevision: entry.ledgerRevision,
    );
    try {
      await _cloud?.update(
        next,
        expectedLedgerRevision: entry.ledgerRevision,
      );
    } on Object {
      // The domain outcome remains authoritative. Bootstrap reconciles the
      // ledger record by mutationId without replaying the action.
    }
    return next;
  }

  String _scope() {
    final scope = _currentScope();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('action_ledger_auth_required');
    }
    return scope;
  }

  static String _ledgerId(String mutationId) => 'ledger-$mutationId';
}
