import '../models/action_ledger.dart';
import '../models/revisioned_sync_protocol.dart';
import 'action_ledger_reconciliation_service.dart';
import 'revisioned_domain_local_repository.dart';
import 'revisioned_offline_journal.dart';

final class RevisionedActionReceiptProbe implements ActionMutationReceiptProbe {
  const RevisionedActionReceiptProbe({
    required this.domain,
    required RevisionedSyncDomain syncDomain,
    RevisionedDomainLocalRepository local =
        const RevisionedDomainLocalRepository(),
    RevisionedOfflineJournal journal = const RevisionedOfflineJournal(),
  })  : _syncDomain = syncDomain,
        _local = local,
        _journal = journal;

  @override
  final ActionLedgerDomain domain;
  final RevisionedSyncDomain _syncDomain;
  final RevisionedDomainLocalRepository _local;
  final RevisionedOfflineJournal _journal;

  @override
  Future<ActionMutationObservation> observe(ActionLedgerEntry entry) async {
    final state = await _journal.load(
      accountScopeId: entry.accountScopeId,
      domain: _syncDomain,
    );
    if (state.receipts.contains(entry.mutationId)) {
      return ActionMutationObservation.applied;
    }
    if (state.conflicts.any(
      (conflict) =>
          conflict.mutationId == entry.mutationId &&
          conflict.status == RevisionedConflictStatus.unresolved,
    )) {
      return ActionMutationObservation.conflict;
    }
    if (state.mutations.any(
      (mutation) => mutation.mutationId == entry.mutationId,
    )) {
      return ActionMutationObservation.pending;
    }
    final applied = switch (_syncDomain) {
      RevisionedSyncDomain.task =>
        (await _local.loadTasks(entry.accountScopeId))
            .any((value) => value.lastMutationId == entry.mutationId),
      RevisionedSyncDomain.shopping =>
        (await _local.loadShopping(entry.accountScopeId))
            .any((value) => value.lastMutationId == entry.mutationId),
      RevisionedSyncDomain.profile =>
        (await _local.loadProfile(entry.accountScopeId))?.lastMutationId ==
            entry.mutationId,
    };
    return applied
        ? ActionMutationObservation.applied
        : ActionMutationObservation.stillUnknown;
  }
}
