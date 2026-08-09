import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/entity_id_generator.dart';
import '../core/identity/entity_identity.dart';
import '../core/identity/entity_matcher.dart';
import '../core/identity/uuid_v7_entity_id_generator.dart';
import '../models/event_model.dart';
import '../models/action_autonomy_policy.dart';
import '../models/action_ledger.dart';
import '../models/event_sync_models.dart';
import '../models/event_sync_conflict.dart';
import '../models/event_account_isolation_snapshot.dart';
import 'cloud_event_service.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';
import 'event_mutation_service.dart';
import 'event_mutation_result.dart';
import 'event_mutation_invariant_service.dart';
import 'event_sync_journal.dart';
import 'event_sync_service.dart';
import 'event_conflict_resolution_service.dart';
import 'event_action_ledger_observer.dart';
import 'profile_reasoning_service.dart';
import 'storage_service.dart';

typedef EventCloudMutation = Future<EventMutationResult?> Function({
  required EventModel existing,
  required EventModel proposed,
  required int expectedEventRevision,
});

typedef EventCloudDeletion = Future<EventMutationResult?> Function({
  required EventModel existing,
  required int expectedEventRevision,
});

final class EventProtectedConflictReference {
  const EventProtectedConflictReference({
    required this.firstEventId,
    required this.secondEventId,
    required this.firstRevision,
    required this.secondRevision,
    required this.protectedStart,
    required this.protectedEnd,
  });

  final String firstEventId;
  final String secondEventId;
  final int firstRevision;
  final int secondRevision;
  final DateTime protectedStart;
  final DateTime protectedEnd;
}

class EventService {
  static const String eventsKey = "zelia_events";
  static const Duration cloudMutationTimeout = Duration(seconds: 15);
  static const String guestScopeKey = "guest";
  static const String guestEventsKey = "$eventsKey:$guestScopeKey";
  static final EventSyncJournal _syncJournal = EventSyncJournal();
  static final EventSyncService _syncService = EventSyncService(
    journal: _syncJournal,
    execute: CloudEventService.executeSyncOperation,
  );
  static const EntityIdGenerator _syncIdGenerator = UuidV7EntityIdGenerator();
  static final EventConflictResolutionService _conflictResolutionService =
      EventConflictResolutionService(
    journal: _syncJournal,
    readCloud: CloudEventService.getEventById,
    mutateCloud: CloudEventService.mutateEvent,
    deleteCloud: CloudEventService.deleteEvent,
    reconcileLocal: _reconcileLocalEvent,
    createLocal: addEvent,
    validateMutation: _validateConflictMutation,
    idGenerator: _syncIdGenerator,
    ledgerObserver: _traceConflictResolution,
  );

  static final EntityMatcher<EventModel> _eventMatcher = EntityMatcher(
    idOf: (event) => event.id,
    legacyEquals: (first, second) {
      return first.title == second.title &&
          first.createdAt == second.createdAt &&
          first.date == second.date &&
          first.time == second.time;
    },
  );

  static final ValueNotifier<int> eventsVersion = ValueNotifier<int>(0);
  static int _loadGeneration = 0;
  static int _activeAccountGeneration = 0;
  static String _activeScopeKey = guestScopeKey;

  static final ValueNotifier<EventAccountIsolationSnapshot>
      accountIsolationSnapshot = ValueNotifier(
    const EventAccountIsolationSnapshot(
      authScopeType: EventAuthScopeType.guest,
      eventServiceScopeType: EventAuthScopeType.guest,
      localCacheScopeType: EventAuthScopeType.guest,
      activeListenerScopeMatch: true,
      eventCount: 0,
      loadGeneration: 0,
      activeAccountGeneration: 0,
      staleResultDiscarded: false,
      sourceType: EventLoadSourceType.local,
      screenInstanceGeneration: 0,
    ),
  );

  static void notifyEventsChanged() {
    eventsVersion.value++;
  }

  static String localEventsKeyForAccountScope(String? scope) {
    final normalized = scope?.trim();
    return '$eventsKey:${normalized == null || normalized.isEmpty ? guestScopeKey : normalized}';
  }

  static String _scopeKey(String? scope) {
    final normalized = scope?.trim();
    return normalized == null || normalized.isEmpty
        ? guestScopeKey
        : normalized;
  }

  static EventAuthScopeType _scopeType(String scopeKey) =>
      scopeKey == guestScopeKey
          ? EventAuthScopeType.guest
          : EventAuthScopeType.authenticated;

  static void handleAccountScopeChanged(String? accountScopeId) {
    final nextScopeKey = _scopeKey(accountScopeId);
    if (nextScopeKey == _activeScopeKey) return;
    _activeScopeKey = nextScopeKey;
    _activeAccountGeneration++;
    _loadGeneration++;
    final scopeType = _scopeType(nextScopeKey);
    accountIsolationSnapshot.value = EventAccountIsolationSnapshot(
      authScopeType: scopeType,
      eventServiceScopeType: scopeType,
      localCacheScopeType: scopeType,
      activeListenerScopeMatch: true,
      eventCount: 0,
      loadGeneration: _loadGeneration,
      activeAccountGeneration: _activeAccountGeneration,
      staleResultDiscarded: false,
      sourceType: EventLoadSourceType.memory,
      screenInstanceGeneration:
          accountIsolationSnapshot.value.screenInstanceGeneration,
    );
    notifyEventsChanged();
  }

  static bool _isCurrentLoad({
    required String scopeKey,
    required int accountGeneration,
  }) {
    return _scopeKey(_currentAccountScope()) == scopeKey &&
        _activeScopeKey == scopeKey &&
        _activeAccountGeneration == accountGeneration;
  }

  static void updateScreenInstanceGeneration(int generation) {
    accountIsolationSnapshot.value = accountIsolationSnapshot.value.copyWith(
      screenInstanceGeneration: generation,
    );
  }

  static String? _currentAccountScope() {
    try {
      return AuthService.currentUserId;
    } on Object {
      return null;
    }
  }

  static Future<void> saveEvents(
    List<EventModel> events,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = localEventsKeyForAccountScope(_currentAccountScope());
    final stored = prefs.getStringList(key) ?? const [];
    final existing = stored
        .map(
          (event) => EventModel.fromJson(
            Map<String, dynamic>.from(jsonDecode(event) as Map),
          ),
        )
        .toList(growable: false);
    final reconciled = EventMutationService.reconcileFullRewrite(
      existing: existing,
      proposed: events,
    );
    _validateFullRewriteRevisions(existing: existing, proposed: reconciled);

    final encoded = reconciled
        .map(
          (event) => jsonEncode(event.toJson()),
        )
        .toList();

    await prefs.setStringList(
      key,
      encoded,
    );

    try {
      await CloudEventService.saveEvents(reconciled);
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'event_storage',
        domain: 'event',
        operation: 'save',
        step: 'cloud_sync',
        code: descriptor.code,
        severity: AppErrorSeverity.warning,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }

    notifyEventsChanged();
  }

  static Future<List<EventModel>> getEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final scopeKey = _scopeKey(_currentAccountScope());
    if (_activeScopeKey != scopeKey) {
      handleAccountScopeChanged(
        scopeKey == guestScopeKey ? null : scopeKey,
      );
    }
    final accountGeneration = _activeAccountGeneration;
    final loadGeneration = ++_loadGeneration;
    final key = localEventsKeyForAccountScope(
      scopeKey == guestScopeKey ? null : scopeKey,
    );

    final data = prefs.getStringList(key);

    final localEvents = data == null
        ? <EventModel>[]
        : data
            .map(
              (event) => EventModel.fromJson(
                jsonDecode(event),
              ),
            )
            .toList();
    accountIsolationSnapshot.value = accountIsolationSnapshot.value.copyWith(
      authScopeType: _scopeType(scopeKey),
      eventServiceScopeType: _scopeType(scopeKey),
      localCacheScopeType: _scopeType(scopeKey),
      activeListenerScopeMatch: true,
      eventCount: localEvents.length,
      loadGeneration: loadGeneration,
      activeAccountGeneration: accountGeneration,
      staleResultDiscarded: false,
      sourceType: EventLoadSourceType.local,
    );

    try {
      final sync = await synchronizePendingEvents();
      if (!_isCurrentLoad(
        scopeKey: scopeKey,
        accountGeneration: accountGeneration,
      )) {
        accountIsolationSnapshot.value =
            accountIsolationSnapshot.value.copyWith(
          staleResultDiscarded: true,
          eventCount: 0,
          loadGeneration: loadGeneration,
        );
        return [];
      }
      if (sync.status == EventSyncStatus.conflicts ||
          sync.status == EventSyncStatus.failed) {
        return localEvents;
      }
      final cloudEvents = await CloudEventService.getEvents();
      if (!_isCurrentLoad(
        scopeKey: scopeKey,
        accountGeneration: accountGeneration,
      )) {
        accountIsolationSnapshot.value =
            accountIsolationSnapshot.value.copyWith(
          staleResultDiscarded: true,
          eventCount: 0,
          loadGeneration: loadGeneration,
        );
        return [];
      }

      if (cloudEvents.isNotEmpty) {
        final encoded = cloudEvents
            .map(
              (event) => jsonEncode(event.toJson()),
            )
            .toList();

        await prefs.setStringList(
          key,
          encoded,
        );
        if (!_isCurrentLoad(
          scopeKey: scopeKey,
          accountGeneration: accountGeneration,
        )) {
          accountIsolationSnapshot.value =
              accountIsolationSnapshot.value.copyWith(
            staleResultDiscarded: true,
            eventCount: 0,
            loadGeneration: loadGeneration,
          );
          return [];
        }
        accountIsolationSnapshot.value =
            accountIsolationSnapshot.value.copyWith(
          eventCount: cloudEvents.length,
          sourceType: EventLoadSourceType.cloud,
        );

        return cloudEvents;
      }
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'event_storage',
        domain: 'event',
        operation: 'load',
        step: 'cloud_fallback',
        code: descriptor.code,
        severity: AppErrorSeverity.warning,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }

    accountIsolationSnapshot.value = accountIsolationSnapshot.value.copyWith(
      eventCount: localEvents.length,
      sourceType: EventLoadSourceType.local,
    );
    return localEvents;
  }

  /// Read-only, account-bound source for Life Context projections.
  ///
  /// Deliberately avoids the legacy unscoped local cache and every sync/write
  /// side effect. Offline callers receive an explicit unavailable section from
  /// the adapter rather than data that could belong to a previous account.
  static Future<List<EventModel>> getEventsForLifeContext(
    String accountScopeId,
  ) async {
    if (accountScopeId.trim().isEmpty ||
        AuthService.currentUserId != accountScopeId) {
      throw const FormatException('event_account_scope_mismatch');
    }
    return CloudEventService.getEvents();
  }

  static Future<Map<String, String>> getEventSyncStatesForLifeContext(
    String accountScopeId,
  ) async {
    if (accountScopeId.trim().isEmpty ||
        AuthService.currentUserId != accountScopeId) {
      throw const FormatException('event_account_scope_mismatch');
    }
    final conflicts = await getSyncConflicts();
    return {
      for (final conflict in conflicts)
        conflict.eventId:
            conflict.resolutionState == EventConflictResolutionState.resolved ||
                    conflict.resolutionState ==
                        EventConflictResolutionState.discarded
                ? 'resolved'
                : 'conflict',
    };
  }

  /// Bounded read-only projection of conflicts already defined by the
  /// canonical protected-interval rule. N.2 consumes these references without
  /// copying Event content or implementing another overlap engine.
  static Future<List<EventProtectedConflictReference>>
      getProtectedConflictsForDetection(
    String accountScopeId, {
    int maximumEvents = 100,
    int maximumConflicts = 50,
    DateTime? observedAt,
  }) async {
    if (maximumEvents < 1 ||
        maximumEvents > 200 ||
        maximumConflicts < 1 ||
        maximumConflicts > 100) {
      throw const FormatException('event_conflict_detection_limit_invalid');
    }
    final current = (observedAt ?? DateTime.now()).toUtc();
    final events = selectUpcomingEventsForConflictDetection(
      await getEventsForLifeContext(accountScopeId),
      observedAt: current,
      maximumEvents: maximumEvents,
    );
    final conflicts = <EventProtectedConflictReference>[];
    for (var first = 0; first < events.length; first++) {
      for (var second = first + 1; second < events.length; second++) {
        if (!eventsProtectedOverlap(events[first], events[second])) continue;
        final firstStart = parseProtectedStart(events[first]);
        final secondStart = parseProtectedStart(events[second]);
        final firstEnd = parseProtectedEnd(events[first]);
        final secondEnd = parseProtectedEnd(events[second]);
        if (firstStart == null ||
            secondStart == null ||
            firstEnd == null ||
            secondEnd == null) {
          continue;
        }
        conflicts.add(EventProtectedConflictReference(
          firstEventId: events[first].id!,
          secondEventId: events[second].id!,
          firstRevision: events[first].eventRevision,
          secondRevision: events[second].eventRevision,
          protectedStart:
              firstStart.isAfter(secondStart) ? firstStart : secondStart,
          protectedEnd: firstEnd.isBefore(secondEnd) ? firstEnd : secondEnd,
        ));
        if (conflicts.length >= maximumConflicts) return conflicts;
      }
    }
    return conflicts;
  }

  @visibleForTesting
  static List<EventModel> selectUpcomingEventsForConflictDetection(
    List<EventModel> source, {
    required DateTime observedAt,
    required int maximumEvents,
  }) {
    final current = observedAt.toUtc();
    final upcoming = source
        .where(
          (event) =>
              event.id != null &&
              event.id!.trim().isNotEmpty &&
              parseProtectedStart(event) != null &&
              (parseProtectedEnd(event)?.toUtc().isAfter(current) ?? false),
        )
        .toList(growable: false)
      ..sort((first, second) {
        final firstStart = parseProtectedStart(first)!.toUtc();
        final secondStart = parseProtectedStart(second)!.toUtc();
        final byStart = firstStart.compareTo(secondStart);
        return byStart != 0 ? byStart : first.id!.compareTo(second.id!);
      });
    return upcoming.take(maximumEvents).toList(growable: false);
  }

  static Future<void> addEvent(
    EventModel event, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
    String? mutationId,
    String? batchId,
  }) async {
    final events = await getEvents();

    final created = _withIdForCreation(event, idGenerator);
    final logicalMutationId = mutationId ?? _syncIdGenerator.generate();
    await EventActionLedgerObserver.trace<bool>(
      mutationId: logicalMutationId,
      eventId: created.id!,
      expectedRevision: 0,
      actionType: ActionType.createEvent,
      operationType: 'createEvent',
      undoStrategy: ActionUndoStrategy.undoCreateEvent,
      dispatch: () async {
        events.add(created);
        await _writeLocalEvents(events);
        final result = await _syncCreation(
          created,
          operationId: logicalMutationId,
          batchId: batchId,
        );
        return EventLedgerDispatchResult(
          result.status == EventMutationStatus.success
              ? EventLedgerDispatchStatus.succeeded
              : EventLedgerDispatchStatus.pendingSync,
          value: true,
          revision: created.eventRevision,
        );
      },
    );
    notifyEventsChanged();
  }

  static Future<void> addEvents(
    List<EventModel> newEvents, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) async {
    final batchId = _syncIdGenerator.generate();
    for (final event in newEvents) {
      await addEvent(
        event,
        idGenerator: idGenerator,
        mutationId: _syncIdGenerator.generate(),
        batchId: batchId,
      );
    }
  }

  static Future<void> updateEvents(
    List<EventModel> events,
  ) async {
    await saveEvents(events);
  }

  static Future<EventMutationResult> mutateEvent({
    required EventModel existing,
    required EventModel proposed,
    required int expectedEventRevision,
    EventParticipantMutationIntent participantIntent =
        const PreserveEventParticipant(),
    EventCloudMutation cloudMutate = CloudEventService.mutateEvent,
    String? mutationId,
  }) {
    final logicalMutationId = mutationId ?? _syncIdGenerator.generate();
    final changesParticipant = participantIntent is! PreserveEventParticipant;
    final changesRecurrence =
        !changesParticipant && _recurrenceChanged(existing, proposed);
    return EventActionLedgerObserver.trace<EventMutationResult>(
      mutationId: logicalMutationId,
      eventId: existing.id ?? proposed.id ?? '',
      expectedRevision: expectedEventRevision,
      actionType: changesParticipant
          ? ActionType.modifyParticipant
          : changesRecurrence
              ? ActionType.modifyRecurrence
              : ActionType.updateEvent,
      operationType: changesParticipant
          ? 'modifyParticipant'
          : changesRecurrence
              ? 'modifyRecurrence'
              : 'updateEvent',
      undoStrategy: changesParticipant
          ? ActionUndoStrategy.undoParticipantChange
          : changesRecurrence
              ? ActionUndoStrategy.irreversible
              : ActionUndoStrategy.undoUpdateEvent,
      dispatch: () async {
        final result = await _mutateEvent(
          existing: existing,
          proposed: proposed,
          expectedEventRevision: expectedEventRevision,
          participantIntent: participantIntent,
          cloudMutate: cloudMutate,
          mutationId: logicalMutationId,
        );
        return EventLedgerDispatchResult(
          _ledgerStatus(result.status),
          value: result,
          revision: result.event?.eventRevision,
        );
      },
    );
  }

  static bool _recurrenceChanged(EventModel existing, EventModel proposed) =>
      existing.isRecurring != proposed.isRecurring ||
      existing.recurringType != proposed.recurringType ||
      existing.recurringWeekday != proposed.recurringWeekday ||
      existing.recurringUntil != proposed.recurringUntil ||
      existing.parentRecurringId != proposed.parentRecurringId;

  static Future<EventConflictResolutionResult> _traceConflictResolution({
    required PendingEventSyncOperation operation,
    required EventConflictResolutionDecision decision,
    required Future<EventConflictResolutionResult> Function() dispatch,
  }) async {
    final recreate = decision == EventConflictResolutionDecision.recreateAsNew;
    final remote = recreate
        ? null
        : await CloudEventService.getEventById(operation.eventId);
    final mutationId = 'resolve:${operation.operationId}:${decision.name}';
    return EventActionLedgerObserver.trace<EventConflictResolutionResult>(
      mutationId: mutationId,
      eventId: recreate
          ? operation.resolutionEventId ?? operation.eventId
          : operation.eventId,
      expectedRevision: remote?.eventRevision ?? 0,
      actionType:
          recreate ? ActionType.createEvent : ActionType.resolveEventConflict,
      operationType: 'resolveEventConflict',
      undoStrategy: recreate
          ? ActionUndoStrategy.undoCreateEvent
          : ActionUndoStrategy.irreversible,
      dispatch: () async {
        final result = await dispatch();
        final status = switch (result.status) {
          EventConflictResolutionStatus.success =>
            EventLedgerDispatchStatus.succeeded,
          EventConflictResolutionStatus.cloudChangedAgain ||
          EventConflictResolutionStatus.planningConflict =>
            EventLedgerDispatchStatus.conflict,
          EventConflictResolutionStatus.persistenceFailure =>
            EventLedgerDispatchStatus.pendingSync,
          _ => EventLedgerDispatchStatus.failed,
        };
        return EventLedgerDispatchResult(
          status,
          value: result,
          revision: result.event?.eventRevision,
        );
      },
    );
  }

  static Future<EventMutationResult> _mutateEvent({
    required EventModel existing,
    required EventModel proposed,
    required int expectedEventRevision,
    required EventParticipantMutationIntent participantIntent,
    required EventCloudMutation cloudMutate,
    required String mutationId,
  }) async {
    final events = await getEvents();
    final index = events.indexWhere(
      (event) => areSameEvent(event, existing),
    );
    if (index < 0) return const EventMutationResult.notFound();
    final current = events[index];
    if (expectedEventRevision < 0 ||
        current.eventRevision != expectedEventRevision) {
      return const EventMutationResult.revisionConflict();
    }
    try {
      final next = EventMutationService.apply(
        existing: current,
        proposed: proposed,
        participantIntent: participantIntent,
      ).copyWith(eventRevision: current.eventRevision + 1);
      final cloudResult = await cloudMutate(
        existing: current,
        proposed: next,
        expectedEventRevision: expectedEventRevision,
      ).timeout(cloudMutationTimeout);
      if (cloudResult != null &&
          cloudResult.status != EventMutationStatus.success &&
          cloudResult.status != EventMutationStatus.persistenceFailure) {
        return cloudResult;
      }
      events[index] = next;
      await _writeLocalEvents(events);
      if (cloudResult == null ||
          cloudResult.status == EventMutationStatus.persistenceFailure) {
        await _enqueue(
          type: EventSyncOperationType.update,
          event: next,
          baseEvent: current,
          expectedEventRevision: expectedEventRevision,
          operationId: mutationId,
        );
      }
      notifyEventsChanged();
      if (cloudResult != null &&
          cloudResult.status == EventMutationStatus.success) {
        await _enqueue(
          type: EventSyncOperationType.update,
          event: next,
          baseEvent: current,
          expectedEventRevision: expectedEventRevision,
          operationId: mutationId,
          state: EventSyncOperationState.applied,
        );
      }
      return EventMutationResult.success(next);
    } on FormatException {
      return const EventMutationResult.invalid();
    } catch (_) {
      return const EventMutationResult.persistenceFailure();
    }
  }

  static Future<EventMutationResult> deleteEvent({
    required EventModel existing,
    required int expectedEventRevision,
    EventCloudDeletion cloudDelete = CloudEventService.deleteEvent,
    String? batchId,
    String? mutationId,
  }) {
    final logicalMutationId = mutationId ?? _syncIdGenerator.generate();
    return EventActionLedgerObserver.trace<EventMutationResult>(
      mutationId: logicalMutationId,
      eventId: existing.id ?? '',
      expectedRevision: expectedEventRevision,
      actionType: ActionType.deleteEvent,
      operationType: 'deleteEvent',
      undoStrategy: ActionUndoStrategy.undoDeleteEvent,
      dispatch: () async {
        final result = await _deleteEvent(
          existing: existing,
          expectedEventRevision: expectedEventRevision,
          cloudDelete: cloudDelete,
          batchId: batchId,
          mutationId: logicalMutationId,
        );
        return EventLedgerDispatchResult(
          _ledgerStatus(result.status),
          value: result,
          revision: result.event?.eventRevision,
        );
      },
    );
  }

  static Future<EventMutationResult> _deleteEvent({
    required EventModel existing,
    required int expectedEventRevision,
    required EventCloudDeletion cloudDelete,
    required String? batchId,
    required String mutationId,
  }) async {
    final events = await getEvents();
    final index = events.indexWhere((event) => areSameEvent(event, existing));
    if (index < 0) return const EventMutationResult.notFound();
    if (events[index].eventRevision != expectedEventRevision) {
      return const EventMutationResult.revisionConflict();
    }
    try {
      final cloudResult = await cloudDelete(
        existing: events[index],
        expectedEventRevision: expectedEventRevision,
      ).timeout(cloudMutationTimeout);
      if (cloudResult != null &&
          cloudResult.status != EventMutationStatus.success &&
          cloudResult.status != EventMutationStatus.persistenceFailure) {
        return cloudResult;
      }
      final removed = events.removeAt(index);
      await _writeLocalEvents(events);
      if (cloudResult == null ||
          cloudResult.status == EventMutationStatus.persistenceFailure) {
        await _enqueue(
          type: EventSyncOperationType.delete,
          eventId: removed.id,
          expectedEventRevision: expectedEventRevision,
          batchId: batchId,
          operationId: mutationId,
        );
      }
      notifyEventsChanged();
      if (cloudResult != null &&
          cloudResult.status == EventMutationStatus.success) {
        await _enqueue(
          type: EventSyncOperationType.delete,
          eventId: removed.id,
          expectedEventRevision: expectedEventRevision,
          operationId: mutationId,
          state: EventSyncOperationState.applied,
        );
      }
      return EventMutationResult.success(removed);
    } catch (_) {
      return const EventMutationResult.persistenceFailure();
    }
  }

  static Future<EventBatchMutationResult> deleteEvents(
    List<EventModel> targets,
  ) async {
    if (targets.isEmpty) return EventBatchMutationResult(const []);
    final batchId = _syncIdGenerator.generate();
    final results = <EventMutationResult>[];
    for (final target in targets) {
      results.add(
        await deleteEvent(
          existing: target,
          expectedEventRevision: target.eventRevision,
          batchId: batchId,
        ),
      );
    }
    return EventBatchMutationResult(results);
  }

  static Future<void> _writeLocalEvents(List<EventModel> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      localEventsKeyForAccountScope(_currentAccountScope()),
      events.map((event) => jsonEncode(event.toJson())).toList(),
    );
  }

  static EventLedgerDispatchStatus _ledgerStatus(
    EventMutationStatus status,
  ) =>
      switch (status) {
        EventMutationStatus.success => EventLedgerDispatchStatus.succeeded,
        EventMutationStatus.persistenceFailure =>
          EventLedgerDispatchStatus.pendingSync,
        EventMutationStatus.revisionConflict ||
        EventMutationStatus.alreadyExists ||
        EventMutationStatus.scopeMismatch =>
          EventLedgerDispatchStatus.conflict,
        EventMutationStatus.notFound ||
        EventMutationStatus.invalidMutation =>
          EventLedgerDispatchStatus.failed,
      };

  static Future<EventSyncResult> synchronizePendingEvents() {
    return _syncService.synchronize();
  }

  static Future<List<EventSyncConflict>> getSyncConflicts() {
    final scope = AuthService.currentUserId;
    if (scope == null || scope.isEmpty) return Future.value(const []);
    return _conflictResolutionService.conflictsForScope(scope);
  }

  static Future<EventConflictResolutionResult> resolveSyncConflict({
    required String conflictId,
    required EventConflictResolutionDecision decision,
    bool confirmed = false,
  }) {
    final scope = AuthService.currentUserId;
    if (scope == null || scope.isEmpty) {
      return Future.value(const EventConflictResolutionResult.scopeMismatch());
    }
    return _conflictResolutionService.resolve(
      conflictId: conflictId,
      accountScopeId: scope,
      decision: decision,
      confirmed: confirmed,
    );
  }

  static Future<void> _reconcileLocalEvent(
    String eventId,
    EventModel? event,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(
          localEventsKeyForAccountScope(_currentAccountScope()),
        ) ??
        const [];
    final events =
        stored.map((item) => EventModel.fromJson(jsonDecode(item))).toList();
    final index = events.indexWhere((item) => item.id == eventId);
    if (event == null) {
      if (index >= 0) events.removeAt(index);
    } else if (index < 0) {
      events.add(event);
    } else {
      events[index] = event;
    }
    await _writeLocalEvents(events);
    notifyEventsChanged();
  }

  static Future<EventMutationInvariantResult> _validateConflictMutation({
    required EventModel existing,
    required EventModel proposed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(
          localEventsKeyForAccountScope(_currentAccountScope()),
        ) ??
        const [];
    final events = stored
        .map((item) => EventModel.fromJson(jsonDecode(item)))
        .toList(growable: false);
    List<Map<String, dynamic>> reasoning = const [];
    try {
      final profile = await StorageService.getUserProfile();
      if (profile != null) {
        reasoning = ProfileReasoningService.buildReasoning(profile);
      }
    } catch (_) {
      // An unavailable profile must not bypass Event-to-Event validation.
    }
    return EventMutationInvariantService.validate(
      existing: existing,
      proposed: proposed,
      events: events,
      blockedReasoning: reasoning,
    );
  }

  static Future<EventMutationResult> _syncCreation(
    EventModel event, {
    String? batchId,
    String? operationId,
  }) async {
    EventMutationResult? result;
    try {
      result = await CloudEventService.createEvent(event)
          .timeout(cloudMutationTimeout);
    } catch (_) {
      result = const EventMutationResult.persistenceFailure();
    }
    if (result == null ||
        result.status == EventMutationStatus.persistenceFailure) {
      await _enqueue(
        type: EventSyncOperationType.create,
        event: event,
        batchId: batchId,
        operationId: operationId,
      );
      return result ?? const EventMutationResult.persistenceFailure();
    }
    if (result.status != EventMutationStatus.success) {
      throw const FormatException('event_sync_creation_conflict');
    }
    await _enqueue(
      type: EventSyncOperationType.create,
      event: event,
      batchId: batchId,
      operationId: operationId,
      state: EventSyncOperationState.applied,
    );
    return result;
  }

  static Future<void> _enqueue({
    required EventSyncOperationType type,
    EventModel? event,
    EventModel? baseEvent,
    String? eventId,
    int? expectedEventRevision,
    String? batchId,
    String? operationId,
    EventSyncOperationState state = EventSyncOperationState.pending,
  }) {
    final resolvedOperationId = operationId ?? _syncIdGenerator.generate();
    String? accountScopeId;
    try {
      accountScopeId = AuthService.currentUserId;
    } catch (_) {
      accountScopeId = null;
    }
    return _syncJournal.append(
      PendingEventSyncOperation(
        operationId: resolvedOperationId,
        eventId: event?.id ?? eventId ?? '',
        accountScopeId: accountScopeId,
        type: type,
        expectedEventRevision: expectedEventRevision,
        event: event,
        baseEvent: baseEvent,
        batchId: batchId ?? resolvedOperationId,
        createdAt: DateTime.now().toUtc(),
        state: state,
      ),
    );
  }

  static void _validateFullRewriteRevisions({
    required List<EventModel> existing,
    required List<EventModel> proposed,
  }) {
    final proposedById = {
      for (final event in proposed)
        if (EntityIdentity.isValid(event.id)) event.id!: event,
    };
    for (final current in existing) {
      if (!EntityIdentity.isValid(current.id)) continue;
      final next = proposedById[current.id];
      if (next == null) {
        throw const FormatException('event_deletion_precondition_required');
      }
      if (jsonEncode(current.toJson()) == jsonEncode(next.toJson())) continue;
      if (next.eventRevision != current.eventRevision + 1) {
        throw const FormatException('event_mutation_revision_required');
      }
    }
  }

  static Future<void> duplicateEvent(
    EventModel source, {
    EntityIdGenerator idGenerator = const UuidV7EntityIdGenerator(),
  }) {
    return addEvent(
      EventMutationService.duplicate(source),
      idGenerator: idGenerator,
    );
  }

  static EventModel _withIdForCreation(
    EventModel event,
    EntityIdGenerator idGenerator,
  ) {
    final creation =
        event.eventRevision == 1 ? event : event.copyWith(eventRevision: 1);
    if (EntityIdentity.isValid(creation.id)) return creation;
    final generatedId = idGenerator.generate();
    return creation.copyWith(id: generatedId);
  }

  static bool areSameEvent(EventModel first, EventModel second) {
    return _eventMatcher.matches(first, second);
  }

  static DateTime? parseStart(EventModel event) {
    if (event.startDateTimeIso.isNotEmpty) {
      return DateTime.tryParse(event.startDateTimeIso);
    }

    if (event.date.isEmpty || event.time.isEmpty) {
      return null;
    }

    return DateTime.tryParse(
      "${event.date}T${event.time}:00",
    );
  }

  static DateTime? parseEnd(EventModel event) {
    if (event.endDateTimeIso.isNotEmpty) {
      return DateTime.tryParse(event.endDateTimeIso);
    }

    final start = parseStart(event);

    if (start == null) {
      return null;
    }

    final minutes = event.durationMinutes > 0 ? event.durationMinutes : 60;

    return start.add(
      Duration(minutes: minutes),
    );
  }

  static DateTime? parseProtectedStart(EventModel event) {
    final start = parseStart(event);

    if (start == null) {
      return null;
    }

    return start.subtract(
      Duration(minutes: event.resolvedTravelGoMinutes),
    );
  }

  static DateTime? parseProtectedEnd(EventModel event) {
    final end = parseEnd(event);

    if (end == null) {
      return null;
    }

    return end.add(
      Duration(
        minutes: event.resolvedTravelBackMinutes + event.marginMinutes,
      ),
    );
  }

  static bool eventsOverlap(
    EventModel first,
    EventModel second,
  ) {
    final firstStart = parseStart(first);
    final firstEnd = parseEnd(first);
    final secondStart = parseStart(second);
    final secondEnd = parseEnd(second);

    if (firstStart == null ||
        firstEnd == null ||
        secondStart == null ||
        secondEnd == null) {
      return false;
    }

    return firstStart.isBefore(secondEnd) && secondStart.isBefore(firstEnd);
  }

  static bool eventsProtectedOverlap(
    EventModel first,
    EventModel second,
  ) {
    final firstStart = parseProtectedStart(first);
    final firstEnd = parseProtectedEnd(first);
    final secondStart = parseProtectedStart(second);
    final secondEnd = parseProtectedEnd(second);

    if (firstStart == null ||
        firstEnd == null ||
        secondStart == null ||
        secondEnd == null) {
      return false;
    }

    return firstStart.isBefore(secondEnd) && secondStart.isBefore(firstEnd);
  }

  static Future<bool> hasConflict({
    required String startDateTimeIso,
  }) async {
    final events = await getEvents();

    for (final event in events) {
      if (event.startDateTimeIso == startDateTimeIso) {
        return true;
      }
    }

    return false;
  }

  static Future<EventModel?> getConflictEvent({
    required String startDateTimeIso,
  }) async {
    final events = await getEvents();

    for (final event in events) {
      if (event.startDateTimeIso == startDateTimeIso) {
        return event;
      }
    }

    return null;
  }

  static Future<EventModel?> getOverlapConflict({
    required EventModel candidate,
  }) async {
    final events = await getEvents();

    for (final event in events) {
      if (eventsProtectedOverlap(event, candidate)) {
        return event;
      }
    }

    return null;
  }

  static String formatIsoDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, "0");
    final d = date.day.toString().padLeft(2, "0");

    return "$y-$m-$d";
  }

  static String formatIsoTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, "0");
    final m = date.minute.toString().padLeft(2, "0");

    return "$h:$m";
  }

  static List<EventModel> buildWeeklyOccurrences({
    required EventModel baseEvent,
    required int count,
  }) {
    final start = parseStart(baseEvent);

    if (start == null) {
      return [baseEvent];
    }

    final occurrences = <EventModel>[];

    final safeCount = count <= 0 ? 52 : count;

    final parentId = DateTime.now().microsecondsSinceEpoch.toString();

    for (var index = 0; index < safeCount; index++) {
      final occurrenceStart = start.add(
        Duration(days: index * 7),
      );

      final duration =
          baseEvent.durationMinutes > 0 ? baseEvent.durationMinutes : 60;

      final occurrenceEnd = occurrenceStart.add(
        Duration(minutes: duration),
      );

      final date = formatIsoDate(occurrenceStart);
      final time = formatIsoTime(occurrenceStart);
      final endDate = formatIsoDate(occurrenceEnd);
      final endTime = formatIsoTime(occurrenceEnd);

      occurrences.add(
        baseEvent.copyWith(
          clearId: true,
          eventRevision: 1,
          date: date,
          time: time,
          startDateTimeIso: "${date}T$time:00",
          endTime: endTime,
          endDateTimeIso: "${endDate}T$endTime:00",
          durationMinutes: duration,
          isRecurring: true,
          recurringType: "weekly",
          recurringWeekday: occurrenceStart.weekday,
          parentRecurringId: parentId,
        ),
      );
    }

    return occurrences;
  }
}
