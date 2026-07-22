import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_sync_conflict.dart';
import 'package:moms_ai/models/event_sync_models.dart';
import 'package:moms_ai/models/event_participant_identity_link.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/services/event_conflict_resolution_service.dart';
import 'package:moms_ai/services/event_mutation_result.dart';
import 'package:moms_ai/services/event_mutation_invariant_service.dart';
import 'package:moms_ai/services/event_sync_journal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_entity_id_generator.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('closed decision matrix differs for create, update and delete', () {
    expect(_conflict(EventSyncOperationType.create).decisions,
        contains(EventConflictResolutionDecision.recreateAsNew));
    expect(_conflict(EventSyncOperationType.update).decisions,
        contains(EventConflictResolutionDecision.retryAgainstLatest));
    expect(_conflict(EventSyncOperationType.delete).decisions,
        contains(EventConflictResolutionDecision.retryDeletion));
    expect(
        _conflict(EventSyncOperationType.delete)
            .allows(EventConflictResolutionDecision.recreateAsNew),
        isFalse);
  });

  test('scope mismatch cannot produce a write decision', () {
    final conflict = EventSyncConflict.fromOperation(
      _operation(EventSyncOperationType.update,
          conflictType: EventSyncConflictType.scopeMismatch),
    );
    expect(conflict.allows(EventConflictResolutionDecision.retryAgainstLatest),
        isFalse);
  });

  test('keep cloud reconciles locally without writing and is idempotent',
      () async {
    final fixture = await _Fixture.create(EventSyncOperationType.update);
    final first = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.keepCloud,
    );
    final second = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.keepCloud,
    );
    expect(first.status, EventConflictResolutionStatus.success);
    expect(second.status, EventConflictResolutionStatus.alreadyResolved);
    expect(fixture.cloudWrites, 0);
    expect(fixture.reconciled.single.title, 'Cloud');
  });

  test('cloud-writing decisions require explicit confirmation', () async {
    final fixture = await _Fixture.create(EventSyncOperationType.delete);
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryDeletion,
    );
    expect(result.status, EventConflictResolutionStatus.confirmationRequired);
    expect(fixture.cloudWrites, 0);
  });

  test('retry update rebases only the local delta onto latest cloud', () async {
    final fixture = await _Fixture.create(EventSyncOperationType.update);
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryAgainstLatest,
      confirmed: true,
    );
    expect(result.status, EventConflictResolutionStatus.success);
    expect(fixture.written?.title, 'Local');
    expect(fixture.written?.notes, 'changed elsewhere');
    expect(fixture.written?.eventRevision, 3);
  });

  test('retry update keeps conflict visible when planning validation blocks',
      () async {
    final fixture = await _Fixture.create(
      EventSyncOperationType.update,
      validation: const EventMutationInvariantResult.planningConflict(),
    );
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryAgainstLatest,
      confirmed: true,
    );

    expect(result.status, EventConflictResolutionStatus.planningConflict);
    expect(fixture.cloudWrites, 0);
    final journalEntry = (await EventSyncJournal().load()).single;
    expect(journalEntry.state, EventSyncOperationState.conflict);
    expect(journalEntry.resolutionState, EventConflictResolutionState.failed);
  });

  test('retry update reports a second revision conflict without overwriting',
      () async {
    final fixture = await _Fixture.create(
      EventSyncOperationType.update,
      mutationResult: const EventMutationResult.revisionConflict(),
    );
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryAgainstLatest,
      confirmed: true,
    );

    expect(result.status, EventConflictResolutionStatus.cloudChangedAgain);
    expect(fixture.cloudWrites, 1);
    expect(fixture.reconciled, isEmpty);
  });

  test('retry preserves a participant changed only in the cloud', () async {
    final cloudLink = EventParticipantIdentityLink(
      identity: PersistedIdentityLink(
        entityId: 'cloud-person',
        entityType: EntityType.person,
      ),
      accountScopeId: 'account',
    );
    final fixture = await _Fixture.create(
      EventSyncOperationType.update,
      cloudEvent: _event(title: 'Cloud', revision: 2).copyWith(
        participantIdentity: cloudLink,
        participantIdentityRevision: 2,
      ),
    );
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryAgainstLatest,
      confirmed: true,
    );

    expect(result.status, EventConflictResolutionStatus.success);
    expect(fixture.written?.participantIdentity, same(cloudLink));
    expect(fixture.written?.participantIdentityRevision, 2);
  });

  test('series-scope rebase fails closed before cloud persistence', () async {
    final fixture = await _Fixture.create(
      EventSyncOperationType.update,
      localEvent: _event(title: 'Local', revision: 2).copyWith(
        isRecurring: true,
        recurringType: 'weekly',
      ),
      validation: const EventMutationInvariantResult.unsupportedRebase(),
    );
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryAgainstLatest,
      confirmed: true,
    );

    expect(result.status, EventConflictResolutionStatus.unsupportedRebase);
    expect(fixture.cloudWrites, 0);
  });

  test('legacy update without a base snapshot cannot be force-rebased',
      () async {
    final fixture = await _Fixture.create(EventSyncOperationType.update,
        includeBase: false);
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryAgainstLatest,
      confirmed: true,
    );
    expect(result.status, EventConflictResolutionStatus.invalidDecision);
    expect(fixture.cloudWrites, 0);
  });

  test(
      'recreate uses a new ID, revision one and duplication participant policy',
      () async {
    final fixture = await _Fixture.create(EventSyncOperationType.create);
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.recreateAsNew,
      confirmed: true,
    );
    expect(result.status, EventConflictResolutionStatus.success);
    expect(fixture.created.single.id, 'new-event');
    expect(fixture.created.single.eventRevision, 1);
    expect(fixture.created.single.participantIdentity, isNull);
    final receipt = (await EventSyncJournal().load()).single;
    expect(receipt.resolutionEventId, 'new-event');
    expect(receipt.state, EventSyncOperationState.resolved);
  });

  test('retry deletion uses latest revision and never touches Identity',
      () async {
    final fixture = await _Fixture.create(EventSyncOperationType.delete);
    final result = await fixture.service.resolve(
      conflictId: 'operation',
      accountScopeId: 'account',
      decision: EventConflictResolutionDecision.retryDeletion,
      confirmed: true,
    );
    expect(result.status, EventConflictResolutionStatus.success);
    expect(fixture.deletedRevision, 2);
    expect(fixture.cloudWrites, 1);
  });
}

EventSyncConflict _conflict(EventSyncOperationType type) =>
    EventSyncConflict.fromOperation(_operation(type));

PendingEventSyncOperation _operation(
  EventSyncOperationType type, {
  EventSyncConflictType conflictType = EventSyncConflictType.revisionConflict,
  bool includeBase = true,
  EventModel? localEvent,
}) {
  final base = _event(title: 'Base', revision: 1);
  final local = type == EventSyncOperationType.create
      ? _event(title: 'Local', revision: 1)
      : type == EventSyncOperationType.update
          ? localEvent ?? _event(title: 'Local', revision: 2)
          : null;
  return PendingEventSyncOperation(
    operationId: 'operation',
    eventId: 'event',
    accountScopeId: 'account',
    type: type,
    expectedEventRevision: type == EventSyncOperationType.create ? null : 1,
    event: local,
    baseEvent:
        type == EventSyncOperationType.update && includeBase ? base : null,
    batchId: 'batch',
    createdAt: DateTime.utc(2026, 7, 22),
    state: EventSyncOperationState.conflict,
    conflictType: conflictType,
  );
}

EventModel _event(
        {required String title, required int revision, String notes = ''}) =>
    EventModel(
      id: 'event',
      title: title,
      date: '2026-07-23',
      time: '10:00',
      notes: notes,
      createdAt: DateTime.utc(2026, 7, 22),
      startDateTimeIso: '2026-07-23T10:00:00.000Z',
      eventRevision: revision,
    );

final class _Fixture {
  final EventConflictResolutionService service;
  final List<EventModel> reconciled;
  final List<EventModel> created;
  int cloudWrites = 0;
  int? deletedRevision;
  EventModel? written;

  _Fixture(this.service, this.reconciled, this.created);

  static Future<_Fixture> create(EventSyncOperationType type,
      {bool includeBase = true,
      EventMutationInvariantResult validation =
          const EventMutationInvariantResult.valid(),
      EventMutationResult? mutationResult,
      EventModel? localEvent,
      EventModel? cloudEvent}) async {
    final journal = EventSyncJournal();
    await journal.append(_operation(
      type,
      includeBase: includeBase,
      localEvent: localEvent,
    ));
    final reconciled = <EventModel>[];
    final created = <EventModel>[];
    late _Fixture fixture;
    final service = EventConflictResolutionService(
      journal: journal,
      readCloud: (_) async =>
          cloudEvent ??
          _event(title: 'Cloud', revision: 2, notes: 'changed elsewhere'),
      mutateCloud: (
          {required existing,
          required proposed,
          required expectedEventRevision}) async {
        fixture.cloudWrites++;
        fixture.written = proposed;
        return mutationResult ?? EventMutationResult.success(proposed);
      },
      deleteCloud: ({required existing, required expectedEventRevision}) async {
        fixture.cloudWrites++;
        fixture.deletedRevision = expectedEventRevision;
        return EventMutationResult.success(existing);
      },
      reconcileLocal: (_, event) async {
        if (event != null) reconciled.add(event);
      },
      createLocal: (event) async => created.add(event),
      validateMutation: ({required existing, required proposed}) async =>
          validation,
      idGenerator: FakeEntityIdGenerator(['new-event']),
    );
    fixture = _Fixture(service, reconciled, created);
    return fixture;
  }
}
