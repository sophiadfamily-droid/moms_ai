import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_sync_models.dart';
import 'package:moms_ai/services/event_mutation_result.dart';
import 'package:moms_ai/services/event_sync_journal.dart';
import 'package:moms_ai/services/event_sync_service.dart';
import 'package:moms_ai/services/event_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_entity_id_generator.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('journal round trips create, update and delete deterministically',
      () async {
    final journal = EventSyncJournal();
    final operations = [
      _operation('op-2', EventSyncOperationType.update, revision: 1),
      _operation('op-1', EventSyncOperationType.create),
      _operation('op-3', EventSyncOperationType.delete, revision: 2),
    ];
    await journal.save(operations);
    final restored = await journal.load();
    expect(restored.map((operation) => operation.operationId),
        ['op-1', 'op-2', 'op-3']);
    expect(restored.map((operation) => operation.type),
        EventSyncOperationType.values);
  });

  test('unknown versions, types and duplicate operation IDs are rejected',
      () async {
    final valid = _operation('duplicate', EventSyncOperationType.create);
    SharedPreferences.setMockInitialValues({
      EventSyncJournal.storageKey: [
        jsonEncode(valid.toJson()),
        jsonEncode(valid.toJson()),
      ],
    });
    expect(EventSyncJournal().load(), throwsFormatException);

    final unknown = valid.toJson()..['schemaVersion'] = 2;
    expect(
      () => PendingEventSyncOperation.fromJson(unknown),
      throwsFormatException,
    );
    final unknownType = valid.toJson()..['type'] = 'merge';
    expect(
      () => PendingEventSyncOperation.fromJson(unknownType),
      throwsFormatException,
    );
  });

  test('update and delete require an expected revision', () {
    for (final type in [
      EventSyncOperationType.update,
      EventSyncOperationType.delete,
    ]) {
      expect(
        () => _operation('op-${type.name}', type),
        throwsFormatException,
      );
    }
  });

  test('successful replay is removed and repeated synchronization is idle',
      () async {
    final journal = EventSyncJournal();
    await journal.append(_operation('op-1', EventSyncOperationType.create));
    var executions = 0;
    final service = EventSyncService(
      journal: journal,
      execute: (operation) async {
        executions++;
        return EventMutationResult.success(operation.event!);
      },
    );
    final first = await service.synchronize();
    final second = await service.synchronize();
    expect(first.appliedCount, 1);
    expect(first.status, EventSyncStatus.synchronized);
    expect(second.appliedCount, 0);
    expect(executions, 1);
  });

  test('conflict retains the local proposal without replaying automatically',
      () async {
    final journal = EventSyncJournal();
    final operation = _operation(
      'op-update',
      EventSyncOperationType.update,
      revision: 1,
    );
    await journal.append(operation);
    var executions = 0;
    final service = EventSyncService(
      journal: journal,
      execute: (_) async {
        executions++;
        return const EventMutationResult.revisionConflict();
      },
    );
    final first = await service.synchronize();
    final second = await service.synchronize();
    expect(first.status, EventSyncStatus.conflicts);
    expect(first.remaining.single.event?.title, 'Event');
    expect(first.remaining.single.conflictType,
        EventSyncConflictType.revisionConflict);
    expect(second.remaining.single.state, EventSyncOperationState.conflict);
    expect(second.status, EventSyncStatus.conflicts);
    expect(second.conflictCount, 1);
    expect(executions, 1);
  });

  test('journal is closed, scoped and bounded', () async {
    final scoped = _operation(
      'scoped',
      EventSyncOperationType.create,
      accountScopeId: 'account-1',
    );
    expect(
      PendingEventSyncOperation.fromJson(scoped.toJson()).accountScopeId,
      'account-1',
    );
    final unknownField = scoped.toJson()..['unexpected'] = true;
    expect(
      () => PendingEventSyncOperation.fromJson(unknownField),
      throwsFormatException,
    );
    final journal = EventSyncJournal();
    expect(
      () => journal.save(
        List.generate(
          EventSyncJournal.maxOperations + 1,
          (index) =>
              _operation('bounded-$index', EventSyncOperationType.create),
        ),
      ),
      throwsFormatException,
    );
  });

  test('missing delete is idempotent and two local starts share one replay',
      () async {
    final journal = EventSyncJournal();
    await journal.append(
      _operation('op-delete', EventSyncOperationType.delete, revision: 1),
    );
    var executions = 0;
    final service = EventSyncService(
      journal: journal,
      execute: (_) async {
        executions++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return const EventMutationResult.notFound();
      },
    );
    final results = await Future.wait([
      service.synchronize(),
      service.synchronize(),
    ]);
    expect(
        results
            .every((result) => result.status == EventSyncStatus.synchronized),
        isTrue);
    expect(executions, 1);
  });

  test('batch has one explicit identity and cannot hide unrelated operations',
      () {
    final operations = [
      _operation('op-1', EventSyncOperationType.create, batchId: 'batch-1'),
      _operation('op-2', EventSyncOperationType.create, batchId: 'batch-1'),
    ];
    final batch = EventSyncBatch(batchId: 'batch-1', operations: operations);
    expect(batch.policy, EventSyncBatchPolicy.explicitPartial);
    expect(batch.operations, hasLength(2));
    final restored = EventSyncBatch.fromJson(batch.toJson());
    expect(restored.batchId, 'batch-1');
    expect(restored.operations.map((operation) => operation.operationId), [
      'op-1',
      'op-2',
    ]);
    expect(
      () => EventSyncBatch(batchId: 'other', operations: operations),
      throwsFormatException,
    );
  });

  test('offline creation persists locally and records one create operation',
      () async {
    await EventService.addEvent(
      _event(id: null),
      idGenerator: FakeEntityIdGenerator(['offline-event']),
    );
    final operations = await EventSyncJournal().load();
    expect(operations, hasLength(1));
    expect(operations.single.type, EventSyncOperationType.create);
    expect(operations.single.eventId, 'offline-event');
    expect(operations.single.event?.eventRevision, 1);
  });

  test(
      'offline update records expected revision and preserves participant data',
      () async {
    final existing = _event(id: 'event-update');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      EventService.eventsKey,
      [jsonEncode(existing.toJson())],
    );
    final result = await EventService.mutateEvent(
      existing: existing,
      proposed: existing.copyWith(title: 'Offline update'),
      expectedEventRevision: 1,
      cloudMutate: ({
        required existing,
        required proposed,
        required expectedEventRevision,
      }) async =>
          const EventMutationResult.persistenceFailure(),
    );
    expect(result.status, EventMutationStatus.success);
    final operation = (await EventSyncJournal().load()).single;
    expect(operation.type, EventSyncOperationType.update);
    expect(operation.expectedEventRevision, 1);
    expect(operation.event?.eventRevision, 2);
  });

  test('offline delete uses an explicit tombstone operation', () async {
    final existing = _event(id: 'event-delete');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      EventService.eventsKey,
      [jsonEncode(existing.toJson())],
    );
    final result = await EventService.deleteEvent(
      existing: existing,
      expectedEventRevision: 1,
      cloudDelete: (
              {required existing, required expectedEventRevision}) async =>
          const EventMutationResult.persistenceFailure(),
    );
    expect(result.status, EventMutationStatus.success);
    final operation = (await EventSyncJournal().load()).single;
    expect(operation.type, EventSyncOperationType.delete);
    expect(operation.event, isNull);
    expect(operation.expectedEventRevision, 1);
  });

  test('offline recurring creation records one explicit logical batch',
      () async {
    await EventService.addEvents(
      [_event(id: null), _event(id: null)],
      idGenerator: FakeEntityIdGenerator(['occurrence-1', 'occurrence-2']),
    );
    final operations = await EventSyncJournal().load();
    expect(operations, hasLength(2));
    expect(
        operations.map((operation) => operation.batchId).toSet(), hasLength(1));
    expect(
        operations.every(
            (operation) => operation.type == EventSyncOperationType.create),
        isTrue);
    expect(operations.every((operation) => operation.event?.eventRevision == 1),
        isTrue);
  });

  test('batch mutation result never hides partial completion', () {
    final result = EventBatchMutationResult([
      EventMutationResult.success(_event(id: 'event-1')),
      const EventMutationResult.revisionConflict(),
      const EventMutationResult.persistenceFailure(),
    ]);
    expect(result.isComplete, isFalse);
    expect(result.successCount, 1);
    expect(result.conflictCount, 1);
    expect(result.failureCount, 1);
  });
}

PendingEventSyncOperation _operation(
  String id,
  EventSyncOperationType type, {
  int? revision,
  String batchId = 'batch',
  String? accountScopeId,
}) {
  final event = type == EventSyncOperationType.delete
      ? null
      : _event(
          id: 'event-${type.name}',
          revision: type == EventSyncOperationType.update ? 2 : 1,
        );
  return PendingEventSyncOperation(
    operationId: id,
    eventId: event?.id ?? 'event-delete',
    accountScopeId: accountScopeId,
    type: type,
    expectedEventRevision: revision,
    event: event,
    batchId: batchId,
    createdAt: DateTime.utc(2026, 7, 22, 10),
    state: EventSyncOperationState.pending,
  );
}

EventModel _event({String? id, int revision = 1}) => EventModel(
      id: id,
      title: 'Event',
      date: '2026-07-23',
      time: '10:00',
      notes: '',
      createdAt: DateTime.utc(2026, 7, 22),
      startDateTimeIso: '2026-07-23T10:00:00.000Z',
      eventRevision: revision,
    );
