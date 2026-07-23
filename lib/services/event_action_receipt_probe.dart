import '../models/action_ledger.dart';
import '../models/event_sync_models.dart';
import 'action_ledger_reconciliation_service.dart';
import 'event_sync_journal.dart';

final class EventActionReceiptProbe implements ActionMutationReceiptProbe {
  const EventActionReceiptProbe({
    EventSyncJournal? journal,
  }) : _journal = journal;

  final EventSyncJournal? _journal;

  @override
  ActionLedgerDomain get domain => ActionLedgerDomain.event;

  @override
  Future<ActionMutationObservation> observe(ActionLedgerEntry entry) async {
    final journal = _journal ?? EventSyncJournal();
    final operations = [
      ...await journal.load(),
      ...await journal.loadReceipts(),
    ];
    final matches = operations.where(
      (operation) =>
          operation.operationId == entry.mutationId &&
          (operation.accountScopeId == null ||
              operation.accountScopeId == entry.accountScopeId),
    );
    if (matches.isEmpty) return ActionMutationObservation.stillUnknown;
    return switch (matches.single.state) {
      EventSyncOperationState.applied ||
      EventSyncOperationState.resolved =>
        ActionMutationObservation.applied,
      EventSyncOperationState.pending ||
      EventSyncOperationState.inFlight ||
      EventSyncOperationState.failed =>
        ActionMutationObservation.pending,
      EventSyncOperationState.conflict => ActionMutationObservation.conflict,
      EventSyncOperationState.cancelled ||
      EventSyncOperationState.discarded =>
        ActionMutationObservation.notApplied,
    };
  }
}
