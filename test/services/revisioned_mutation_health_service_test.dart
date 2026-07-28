import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/revisioned_domain_models.dart';
import 'package:moms_ai/models/revisioned_sync_protocol.dart';
import 'package:moms_ai/models/task_model.dart';
import 'package:moms_ai/services/revisioned_mutation_health_service.dart';
import 'package:moms_ai/services/revisioned_offline_journal.dart';

void main() {
  const service = RevisionedMutationHealthService();

  test('distinguishes scheduled, exhausted and completed mutations', () {
    final journal = RevisionedJournalState(
      accountScopeId: 'scope-a',
      domain: RevisionedSyncDomain.task,
      mutations: [
        _mutation('retry', attempt: 2),
        _mutation(
          'exhausted',
          attempt: RevisionedJournalState.maxAttempts,
        ),
      ],
      receipts: const ['completed-mutation'],
    );
    final snapshot = service.inspect(journal);
    expect(snapshot.pendingCount, 2);
    expect(
      snapshot.stateCounts[RevisionedMutationHealthState.retryScheduled],
      1,
    );
    expect(
      snapshot.stateCounts[RevisionedMutationHealthState.permanentlyFailed],
      1,
    );
    expect(
      snapshot.stateCounts[RevisionedMutationHealthState.completed],
      1,
    );
  });

  test('distinguishes conflicts, account mismatch and invalid payload state',
      () {
    final now = DateTime.utc(2026, 7, 28);
    final journal = RevisionedJournalState(
      accountScopeId: 'scope-a',
      domain: RevisionedSyncDomain.task,
      mutations: [
        _mutation('conflict'),
        _mutation('account'),
        _mutation('corrupt', state: RevisionedMutationState.corrupted),
      ],
      conflicts: [
        RevisionedConflict(
          conflictId: 'conflict-1',
          domain: RevisionedSyncDomain.task,
          targetId: 'entity-conflict',
          mutationId: 'conflict',
          expectedRevision: 1,
          remoteRevision: 2,
          type: RevisionedConflictType.revisionConflict,
          createdAt: now,
          allowedResolutions: const [
            RevisionedConflictResolution.requireUserResolution,
          ],
        ),
        RevisionedConflict(
          conflictId: 'conflict-2',
          domain: RevisionedSyncDomain.task,
          targetId: 'entity-account',
          mutationId: 'account',
          expectedRevision: 1,
          remoteRevision: 1,
          type: RevisionedConflictType.accountMismatch,
          createdAt: now,
          allowedResolutions: const [
            RevisionedConflictResolution.discardLocalMutation,
          ],
        ),
      ],
    );
    final snapshot = service.inspect(journal);
    expect(
      snapshot.stateCounts[RevisionedMutationHealthState.blockedConflict],
      1,
    );
    expect(
      snapshot
          .stateCounts[RevisionedMutationHealthState.blockedAccountMismatch],
      1,
    );
    expect(
      snapshot.stateCounts[RevisionedMutationHealthState.blockedInvalidPayload],
      1,
    );
    expect(snapshot.toJson().toString(), isNot(contains('scope-a')));
  });
}

TaskMutation _mutation(
  String id, {
  int attempt = 0,
  RevisionedMutationState state = RevisionedMutationState.retryScheduled,
}) =>
    TaskMutation(
      mutationId: id,
      targetId: 'entity-$id',
      expectedRevision: 0,
      createdAt: DateTime.utc(2026, 7, 28),
      attempt: attempt,
      nextRetryAt: null,
      state: state,
      type: TaskMutationType.createTask,
      task: TaskModel(
        id: 'entity-$id',
        title: 'Synthetic task',
        category: 'To-do',
        isDone: false,
        createdAt: DateTime.utc(2026, 7, 28),
      ),
    );
