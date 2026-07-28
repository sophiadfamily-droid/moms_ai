import '../models/revisioned_domain_models.dart';
import '../models/revisioned_sync_protocol.dart';
import 'revisioned_offline_journal.dart';

enum RevisionedMutationHealthState {
  retryScheduled,
  blockedConflict,
  blockedInvalidPayload,
  blockedAccountMismatch,
  permanentlyFailed,
  completed,
}

final class RevisionedMutationHealthSnapshot {
  const RevisionedMutationHealthSnapshot({
    required this.domain,
    required this.pendingCount,
    required this.stateCounts,
    required this.maximumAttempts,
  });

  final RevisionedSyncDomain domain;
  final int pendingCount;
  final Map<RevisionedMutationHealthState, int> stateCounts;
  final int maximumAttempts;

  Map<String, Object> toJson() => {
        'domain': domain.name,
        'pendingCount': pendingCount,
        'stateCounts': {
          for (final entry in stateCounts.entries) entry.key.name: entry.value,
        },
        'maximumAttempts': maximumAttempts,
      };
}

final class RevisionedMutationHealthService {
  const RevisionedMutationHealthService();

  RevisionedMutationHealthSnapshot inspect(RevisionedJournalState journal) {
    final states = <RevisionedMutationHealthState, int>{};
    for (final mutation in journal.mutations) {
      final conflict = journal.conflicts
          .where((item) => item.mutationId == mutation.mutationId)
          .firstOrNull;
      final health = _stateFor(mutation, conflict);
      states[health] = (states[health] ?? 0) + 1;
    }
    if (journal.receipts.isNotEmpty) {
      states[RevisionedMutationHealthState.completed] = journal.receipts.length;
    }
    return RevisionedMutationHealthSnapshot(
      domain: journal.domain,
      pendingCount: journal.mutations.length,
      stateCounts: Map.unmodifiable(states),
      maximumAttempts: RevisionedJournalState.maxAttempts,
    );
  }

  RevisionedMutationHealthState _stateFor(
    RevisionedDomainMutation mutation,
    RevisionedConflict? conflict,
  ) {
    if (conflict != null) {
      return conflict.type == RevisionedConflictType.accountMismatch
          ? RevisionedMutationHealthState.blockedAccountMismatch
          : RevisionedMutationHealthState.blockedConflict;
    }
    if (mutation.state == RevisionedMutationState.corrupted) {
      return RevisionedMutationHealthState.blockedInvalidPayload;
    }
    if (mutation.state == RevisionedMutationState.abandoned ||
        mutation.attempt >= RevisionedJournalState.maxAttempts) {
      return RevisionedMutationHealthState.permanentlyFailed;
    }
    return RevisionedMutationHealthState.retryScheduled;
  }
}
