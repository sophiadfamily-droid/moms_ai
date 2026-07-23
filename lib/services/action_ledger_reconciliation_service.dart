import '../models/action_ledger.dart';
import 'action_ledger_repository.dart';
import 'action_ledger_service.dart';

enum ActionMutationObservation {
  applied,
  notApplied,
  pending,
  conflict,
  stillUnknown,
}

abstract interface class ActionMutationReceiptProbe {
  ActionLedgerDomain get domain;
  Future<ActionMutationObservation> observe(ActionLedgerEntry entry);
}

final class CallbackActionMutationReceiptProbe
    implements ActionMutationReceiptProbe {
  const CallbackActionMutationReceiptProbe({
    required this.domain,
    required Future<ActionMutationObservation> Function(ActionLedgerEntry)
        observe,
  }) : _observe = observe;

  @override
  final ActionLedgerDomain domain;
  final Future<ActionMutationObservation> Function(ActionLedgerEntry) _observe;

  @override
  Future<ActionMutationObservation> observe(ActionLedgerEntry entry) =>
      _observe(entry);
}

final class ActionLedgerReconciliationResult {
  const ActionLedgerReconciliationResult({
    required this.inspected,
    required this.updated,
    required this.stillUnknown,
  });

  final int inspected;
  final int updated;
  final int stillUnknown;
}

final class ActionLedgerReconciliationService {
  static const maxEntriesPerPass = 25;

  ActionLedgerReconciliationService({
    required ActionLedgerRepository repository,
    required ActionLedgerService ledger,
    required String? Function() currentScope,
    required Iterable<ActionMutationReceiptProbe> probes,
  })  : _repository = repository,
        _ledger = ledger,
        _currentScope = currentScope,
        _probes = Map.unmodifiable({
          for (final probe in probes) probe.domain: probe,
        });

  final ActionLedgerRepository _repository;
  final ActionLedgerService _ledger;
  final String? Function() _currentScope;
  final Map<ActionLedgerDomain, ActionMutationReceiptProbe> _probes;

  Future<ActionLedgerReconciliationResult> reconcile({
    int limit = maxEntriesPerPass,
  }) async {
    if (limit < 1 || limit > maxEntriesPerPass) {
      throw const FormatException('action_reconciliation_limit');
    }
    final scope = _currentScope();
    if (scope == null || scope.trim().isEmpty) {
      throw const FormatException('action_ledger_auth_required');
    }
    final page = await _repository.page(scope, limit: limit);
    final candidates = page.entries.where(_needsReconciliation).take(limit);
    var inspected = 0;
    var updated = 0;
    var unknown = 0;
    for (final entry in candidates) {
      if (_currentScope() != scope) {
        throw const FormatException('action_ledger_account_changed');
      }
      inspected++;
      final observation = await _probes[entry.actionDomain]?.observe(entry) ??
          ActionMutationObservation.stillUnknown;
      if (observation == ActionMutationObservation.stillUnknown ||
          observation == ActionMutationObservation.notApplied ||
          observation == ActionMutationObservation.pending) {
        unknown++;
        continue;
      }
      final outcome = switch (observation) {
        ActionMutationObservation.applied => ActionOutcome.completed,
        ActionMutationObservation.pending => ActionOutcome.pendingSync,
        ActionMutationObservation.conflict => ActionOutcome.conflict,
        _ => ActionOutcome.unknownResult,
      };
      final reconciled = await _ledger.reconcileResult(
        entry,
        outcome: outcome,
        transitionMutationId:
            'reconcile:${entry.mutationId}:${entry.ledgerRevision}',
      );
      if (outcome == ActionOutcome.completed &&
          reconciled.status == ActionLedgerStatus.succeeded) {
        await _ledger.exposeUndo(
          reconciled,
          transitionMutationId:
              'reconcile:${entry.mutationId}:undo:${reconciled.ledgerRevision}',
        );
      }
      updated++;
    }
    return ActionLedgerReconciliationResult(
      inspected: inspected,
      updated: updated,
      stillUnknown: unknown,
    );
  }

  static bool _needsReconciliation(ActionLedgerEntry entry) =>
      entry.status == ActionLedgerStatus.dispatching ||
      entry.status == ActionLedgerStatus.pendingSync ||
      entry.status == ActionLedgerStatus.undoDispatching ||
      entry.status == ActionLedgerStatus.undoPendingSync;
}
