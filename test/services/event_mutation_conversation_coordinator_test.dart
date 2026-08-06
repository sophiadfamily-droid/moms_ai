import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/conversation_reference_resolution.dart';
import 'package:moms_ai/models/conversation_session_models.dart';
import 'package:moms_ai/models/agenda_conflict_move_suggestion.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_mutation_models.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/conversation_reference_resolver.dart';
import 'package:moms_ai/services/conversation_reference_history_store.dart';
import 'package:moms_ai/services/conversation_session_controller.dart';
import 'package:moms_ai/services/event_conversation_mutation_service.dart';
import 'package:moms_ai/services/event_mutation_result.dart';
import 'package:moms_ai/services/routine_conversation_service.dart';
import 'package:moms_ai/services/routine_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('proactive suggestion waits for yes before moving the exact event',
      () async {
    final fixture = _fixture([_event('event-1', '10:00')]);

    final proposal = await fixture.coordinator.beginSuggestedEventMove(
      eventId: 'event-1',
      dateIso: '2026-07-23',
      time: '14:00',
    );

    expect(proposal.message, contains('14 h'));
    expect(proposal.message, contains('Est-ce que ça te va ?'));
    expect(fixture.writes, 0);
    expect(
      fixture.coordinator.state.pendingAction?.type,
      PendingConversationActionType.eventMutationConfirmation,
    );

    await fixture.coordinator.send(
      input: ConversationInput(message: 'oui', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(fixture.writes, 1);
    expect(fixture.written?.time, '14:00');
  });

  test('proactive move confirmation cannot be stolen by an older flow',
      () async {
    final fixture = _fixture([_event('event-1', '10:00')]);
    var olderFlowCalls = 0;
    final controller = ConversationSessionController(
      profile: _profile(),
      coordinator: fixture.coordinator,
      executeAction: (_, __, ___) async => const ConversationActionOutcome(),
      resolvePending: (_, __) async {
        olderFlowCalls++;
        return const ConversationOutcome(
          reply: 'C’est fait. La routine est maintenant prise en compte.',
        );
      },
      messageStore: _NoopMessageStore(),
      accountScopeId: 'conversation-local',
      idGenerator: () => 'proactive-session',
    );

    await controller.beginProactiveEventMove(
      const AgendaConflictMoveSuggestion(
        eventId: 'event-1',
        eventTitle: 'Médecin',
        dateIso: '2026-07-23',
        time: '14:00',
        label: '14 h',
      ),
    );
    await controller.submitText('oui');

    expect(olderFlowCalls, 0);
    expect(fixture.writes, 1);
    expect(fixture.written?.time, '14:00');
    expect(controller.state.messages.last.text, isNot(contains('routine')));
    controller.dispose();
  });

  test('event move yes takes priority over a retained routine confirmation',
      () async {
    final repository = _RoutineRepository();
    final routineService = RoutineConversationService(
      repository: repository,
      currentAccountScopeId: () => 'conversation-local',
      clock: () => DateTime.utc(2026, 7, 22, 10),
    );
    await routineService.process(
      'Tous les mardis de 9 h à 10 h, je vais au sport.',
      logicalRequestId: 'old-routine',
    );
    expect(routineService.hasPending, isTrue);
    final fixture = _fixture(
      [_event('event-1', '10:00')],
      routineConversationService: routineService,
    );

    await fixture.coordinator.beginSuggestedEventMove(
      eventId: 'event-1',
      dateIso: '2026-07-23',
      time: '14:00',
    );
    final result = await fixture.coordinator.send(
      input: ConversationInput(message: 'oui', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );

    expect(result?.reply, 'C’est fait, l’événement a été modifié.');
    expect(fixture.writes, 1);
    expect(fixture.written?.time, '14:00');
    expect(repository.commits, 0);
  });

  test('backend mutation selects one target and waits for confirmation',
      () async {
    final fixture = _fixture([_event('event-1', '10:00')]);
    final outcome = await fixture.coordinator.send(
      input: ConversationInput(message: 'Décale à 11 h', profile: _profile()),
      executeAction: (_) async {
        fixture.actionExecutions++;
        return const ConversationActionOutcome();
      },
    );
    expect(outcome?.reply, contains('Est-ce que ça te va ?'));
    expect(
      outcome?.referenceResolution?.status,
      ConversationReferenceResolutionStatus.resolved,
    );
    expect(outcome?.referenceResolution?.entityId, 'event-1');
    expect(fixture.actionExecutions, 0);
    expect(fixture.writes, 0);
    expect(fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventMutationConfirmation);
  });

  test('ambiguous target requires selection then a separate confirmation',
      () async {
    final fixture = _fixture([
      _event('event-2', '11:00'),
      _event('event-1', '10:00'),
    ], target: EventMutationTarget(title: 'Médecin'));
    final initial = await fixture.coordinator.send(
      input:
          ConversationInput(message: 'Décale le médecin', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(initial?.reply, contains('1.'));
    expect(
      initial?.referenceResolution?.status,
      ConversationReferenceResolutionStatus.ambiguous,
    );
    expect(
      initial?.referenceResolution?.candidateIds,
      ['event-1', 'event-2'],
    );
    expect(fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventTargetClarification);
    final invalid = await fixture.coordinator.send(
      input: ConversationInput(message: 'peut-être', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(invalid?.reply, contains('numéro'));
    final selected = await fixture.coordinator.send(
      input: ConversationInput(message: '2', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(selected?.reply, contains('Est-ce que ça te va ?'));
    expect(
      selected?.referenceResolution?.source,
      ConversationReferenceSource.pendingAction,
    );
    expect(selected?.referenceResolution?.entityId, 'event-2');
    expect(fixture.writes, 0);
    expect(fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventMutationConfirmation);
  });

  test('positive confirmation writes once and repeated answer does not retry',
      () async {
    final fixture = _fixture([_event('event-1', '10:00')]);
    await fixture.start();
    final confirmed = await fixture.coordinator.send(
      input: ConversationInput(message: 'oui', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(confirmed?.reply, contains('modifié'));
    expect(fixture.writes, 1);
    expect(fixture.written?.time, '11:00');
    final repeated = await fixture.coordinator.send(
      input: ConversationInput(message: 'oui', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(fixture.writes, 1);
    expect(repeated, isNotNull);
  });

  test('negative and ambiguous confirmation never write', () async {
    final fixture = _fixture([_event('event-1', '10:00')]);
    await fixture.start();
    final ambiguous = await fixture.coordinator.send(
      input: ConversationInput(message: 'peut-être', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(ambiguous?.reply, contains('oui'));
    expect(fixture.writes, 0);
    await fixture.coordinator.send(
      input: ConversationInput(message: 'non', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(fixture.writes, 0);
    expect(fixture.coordinator.state.pendingAction, isNull);
  });

  test('not found and expired clarification perform no mutation', () async {
    final fixture = _fixture([]);
    final notFound = await fixture.start();
    expect(notFound?.reply, contains('ne trouve pas'));
    expect(
      notFound?.referenceResolution?.status,
      ConversationReferenceResolutionStatus.unresolved,
    );
    expect(fixture.writes, 0);

    final expiring = _fixture([
      _event('event-1', '10:00'),
      _event('event-2', '11:00'),
    ], target: EventMutationTarget(title: 'Médecin'));
    await expiring.start();
    expiring.now = expiring.now.add(const Duration(minutes: 16));
    final expired = await expiring.coordinator.send(
      input: ConversationInput(message: '1', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(expired?.reply, contains('expiré'));
    expect(expiring.writes, 0);
  });

  test('validated event reference survives coordinator reconstruction',
      () async {
    final events = [
      _event('event-1', '10:00'),
      _event('event-2', '11:00'),
    ];
    final first = _fixture(events);
    await first.start();
    await first.coordinator.send(
      input: ConversationInput(message: 'non', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );

    final reconstructed = _fixture(
      events,
      target: EventMutationTarget(title: 'celui-ci'),
      validatedReferenceHistory: first.coordinator.validatedReferenceHistory,
    );
    final result = await reconstructed.start();

    expect(result?.referenceResolution?.entityId, 'event-1');
    expect(
      result?.referenceResolution?.source,
      ConversationReferenceSource.validatedConversationHistory,
    );
    expect(reconstructed.writes, 0);
    expect(
      reconstructed.coordinator.state.pendingAction?.type,
      PendingConversationActionType.eventMutationConfirmation,
    );
  });

  test('implicit target without antecedent never selects account events',
      () async {
    for (final events in [
      <EventModel>[],
      [_event('event-1', '10:00')],
      [_event('event-1', '10:00'), _event('event-2', '11:00')],
    ]) {
      final fixture = _fixture(
        events,
        target: EventMutationTarget(title: 'le'),
      );
      final result = await fixture.start();

      expect(result?.reply, 'De quel événement parles-tu ?');
      expect(
        result?.referenceResolution?.status,
        ConversationReferenceResolutionStatus.unresolved,
      );
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.writes, 0);
    }
  });

  test('expired or deleted historical antecedent never falls back globally',
      () async {
    final expiredAt = DateTime.utc(2026, 7, 22, 10);
    final expired = _fixture(
      [_event('event-1', '10:00')],
      target: EventMutationTarget(title: 'celui-ci'),
      validatedReferenceHistory: [
        ValidatedConversationReference(
          entityId: 'event-1',
          entityType: ConversationReferenceEntityType.event,
          accountScopeId: 'conversation-local',
          validatedAt: expiredAt.subtract(const Duration(minutes: 15)),
          expiresAt: expiredAt,
        ),
      ],
    );
    final expiredResult = await expired.start();
    expect(expiredResult?.reply, 'De quel événement parles-tu ?');
    expect(expired.coordinator.state.pendingAction, isNull);
    expect(expired.writes, 0);

    final deleted = _fixture(
      [_event('other-event', '11:00')],
      target: EventMutationTarget(title: 'celui-ci'),
      validatedReferenceHistory: [
        ValidatedConversationReference(
          entityId: 'deleted-event',
          entityType: ConversationReferenceEntityType.event,
          accountScopeId: 'conversation-local',
          validatedAt: expiredAt.subtract(const Duration(minutes: 1)),
          expiresAt: expiredAt.add(const Duration(minutes: 14)),
        ),
      ],
    );
    final deletedResult = await deleted.start();
    expect(
      deletedResult?.referenceResolution?.status,
      ConversationReferenceResolutionStatus.unresolved,
    );
    expect(deleted.coordinator.state.pendingAction, isNull);
    expect(deleted.writes, 0);
  });

  test('clarification reloads candidate and refuses deleted or changed event',
      () async {
    for (final mutation in ['deleted', 'other-scope', 'inactive', 'changed']) {
      final events = [
        _event('event-1', '10:00'),
        _event('event-2', '11:00'),
      ];
      final fixture = _fixture(
        events,
        target: EventMutationTarget(title: 'Médecin'),
      );
      await fixture.start();
      if (mutation == 'changed') {
        events[0] = events[0].copyWith(time: '12:00', eventRevision: 2);
      } else {
        // Repository scoping and active/deleted filtering make the candidate
        // absent from the authenticated repository view.
        events.removeAt(0);
      }

      final result = await fixture.coordinator.send(
        input: ConversationInput(message: '1', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(result?.reply, contains('plus disponible'), reason: mutation);
      expect(fixture.coordinator.state.pendingAction, isNull, reason: mutation);
      expect(fixture.writes, 0, reason: mutation);
    }
  });

  test('valid clarification retry creates one confirmation and still needs oui',
      () async {
    final fixture = _fixture([
      _event('event-1', '10:00'),
      _event('event-2', '11:00'),
    ], target: EventMutationTarget(title: 'Médecin'));
    await fixture.start();
    final selected = await fixture.coordinator.send(
      input: ConversationInput(message: '1', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    final retry = await fixture.coordinator.send(
      input: ConversationInput(message: '1', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );

    expect(selected?.reply, contains('Est-ce que ça te va ?'));
    expect(retry?.reply, contains('oui'));
    expect(fixture.writes, 0);
    expect(
      fixture.coordinator.state.pendingAction?.type,
      PendingConversationActionType.eventMutationConfirmation,
    );
  });

  group('production session reference history', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('real controllers persist, reload and revalidate a stable event ID',
        () async {
      var now = DateTime.utc(2026, 7, 22, 10);
      final events = [_event('event-1', '10:00')];
      final first = _productionController(
        events: events,
        target: EventMutationTarget(date: '2026-07-23', time: '10:00'),
        now: () => now,
        accountScopeId: 'account-a',
      );
      await first.submitText('Décale à 11 h');
      await first.submitText('non');
      first.dispose();

      final reconstructed = _productionController(
        events: List.of(events),
        target: EventMutationTarget(title: 'le'),
        now: () => now,
        accountScopeId: 'account-a',
      );
      await reconstructed.submitText('Mets-le à 11 h');

      expect(
        reconstructed.activeActionConfirmation,
        isNotNull,
      );
      expect(reconstructed.state.hasPendingAction, isTrue);
      reconstructed.dispose();
    });

    test('restart rejects expired, deleted, foreign and corrupted history',
        () async {
      var now = DateTime.utc(2026, 7, 22, 10);
      final events = [_event('event-1', '10:00')];
      final first = _productionController(
        events: events,
        target: EventMutationTarget(date: '2026-07-23', time: '10:00'),
        now: () => now,
        accountScopeId: 'account-a',
      );
      await first.submitText('Décale à 11 h');
      first.dispose();

      for (final scenario in ['expired', 'deleted', 'other-account']) {
        final scenarioEvents =
            scenario == 'deleted' ? <EventModel>[] : List.of(events);
        final controller = _productionController(
          events: scenarioEvents,
          target: EventMutationTarget(title: 'le'),
          now: () => scenario == 'expired'
              ? now.add(const Duration(minutes: 15))
              : now,
          accountScopeId:
              scenario == 'other-account' ? 'account-b' : 'account-a',
        );
        await controller.submitText('Mets-le à 11 h');
        expect(controller.activeActionConfirmation, isNull, reason: scenario);
        expect(controller.state.hasPendingAction, isFalse, reason: scenario);
        controller.dispose();
      }

      SharedPreferences.setMockInitialValues({
        'conversation_reference_history_v1:account-a': [
          '{"schemaVersion":1,"entityType":"event","entityId":"event-1",'
              '"validatedAt":"2099-01-01T00:00:00.000Z",'
              '"expiresAt":"2099-01-01T00:15:00.000Z",'
              '"source":"validatedConversationHistory"}',
          'private user text and title',
        ],
      });
      final corrupted = _productionController(
        events: events,
        target: EventMutationTarget(title: 'le'),
        now: () => now,
        accountScopeId: 'account-a',
      );
      await corrupted.submitText('Mets-le à 11 h');
      expect(corrupted.activeActionConfirmation, isNull);
      expect(corrupted.state.hasPendingAction, isFalse);
      corrupted.dispose();
    });

    test('durable payload is bounded and contains no private event content',
        () async {
      final now = DateTime.utc(2026, 7, 22, 10);
      const store = SharedPreferencesConversationReferenceHistoryStore();
      await store.save(
        accountScopeId: 'account-a',
        referenceDate: now,
        references: List.generate(
          25,
          (index) => ValidatedConversationReference(
            entityId: 'event-$index',
            entityType: ConversationReferenceEntityType.event,
            accountScopeId: 'account-a',
            validatedAt: now,
            expiresAt: now.add(const Duration(minutes: 15)),
          ),
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      final payload = preferences
          .getStringList('conversation_reference_history_v1:account-a')!;

      expect(payload, hasLength(20));
      expect(payload.join(), isNot(contains('Médecin')));
      expect(payload.join(), isNot(contains('Mets-le')));
      expect(payload.join(), isNot(contains('title')));
      expect(payload.join(), isNot(contains('name')));
      expect(
        payload.first,
        contains(
          '"schemaVersion":1,"entityType":"event","entityId":"event-0"',
        ),
      );
    });
  });
}

ConversationSessionController _productionController({
  required List<EventModel> events,
  required EventMutationTarget target,
  required DateTime Function() now,
  required String accountScopeId,
}) {
  var id = 0;
  return ConversationSessionController.production(
    profile: _profile(),
    backendClient: _Backend(
      EventMutationRequest.update(
        target: target,
        changes: EventMutationChanges(time: '11:00'),
      ),
    ),
    contextProvider: _Context(),
    eventConversationMutationService: EventConversationMutationService(
      loadEvents: () async => List.of(events),
      write: (
          {required existing,
          required proposed,
          required expectedEventRevision,
          required participantIntent}) async {
        throw StateError('confirmation must remain separate in this test');
      },
    ),
    referenceHistoryStore:
        const SharedPreferencesConversationReferenceHistoryStore(),
    messageStore: _NoopMessageStore(),
    clock: now,
    idGenerator: () => 'session-${++id}',
    accountScopeId: accountScopeId,
    initialAssistantMessage: '',
  );
}

final class _NoopMessageStore implements ConversationMessageStore {
  @override
  Future<void> save({
    required String sessionId,
    required ConversationMessageRole role,
    required String text,
  }) async {}
}

final class _Fixture {
  final ConversationCoordinator coordinator;
  final List<EventModel> events;
  int writes = 0;
  int actionExecutions = 0;
  EventModel? written;
  DateTime now;

  _Fixture._(this.coordinator, this.events, this.now);

  Future<ConversationOutcome?> start() => coordinator.send(
        input: ConversationInput(message: 'Décale à 11 h', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
}

_Fixture _fixture(
  List<EventModel> events, {
  EventMutationTarget? target,
  List<ValidatedConversationReference> validatedReferenceHistory = const [],
  RoutineConversationService? routineConversationService,
}) {
  final nowBox = [DateTime.utc(2026, 7, 22, 10)];
  late _Fixture fixture;
  final backend = _Backend(
    EventMutationRequest.update(
      target: target ?? EventMutationTarget(date: '2026-07-23', time: '10:00'),
      changes: EventMutationChanges(time: '11:00'),
    ),
  );
  final service = EventConversationMutationService(
    loadEvents: () async => List.of(events),
    write: (
        {required existing,
        required proposed,
        required expectedEventRevision,
        required participantIntent}) async {
      fixture.writes++;
      fixture.written = proposed;
      final index = events.indexWhere((event) => event.id == existing.id);
      if (index >= 0) events[index] = proposed;
      return EventMutationResult.success(
        proposed.copyWith(eventRevision: expectedEventRevision + 1),
      );
    },
  );
  final coordinator = ConversationCoordinator(
    backend: backend,
    contextProvider: _Context(),
    eventConversationMutationService: service,
    routineConversationService: routineConversationService,
    actionDraftIdGenerator: _Ids(),
    validatedReferenceHistory: validatedReferenceHistory,
    clock: () => fixture.now,
  );
  fixture = _Fixture._(coordinator, events, nowBox.single);
  return fixture;
}

final class _RoutineRepository implements RoutineRepository {
  RoutineProposal? proposal;
  int commits = 0;

  @override
  Future<RoutineProposal?> createOrVerifyProposal(
          RoutineProposal value) async =>
      proposal ??= value;

  @override
  Future<RoutineProposal?> findActiveProposal(String accountScopeId) async =>
      proposal;

  @override
  Future<RoutineProposal?> findLatestProposal(String accountScopeId) async =>
      proposal;

  @override
  Future<RoutineProposal?> findProposal({
    required String accountScopeId,
    required String proposalId,
  }) async =>
      proposal?.proposalId == proposalId ? proposal : null;

  @override
  Future<RoutineProposal?> updateProposal(RoutineProposal value) async =>
      proposal = value;

  @override
  Future<RoutineCommitResult> commitProposal(
    RoutineProposal value,
    DateTime committedAt,
  ) async {
    commits++;
    return const RoutineCommitResult(RoutineCommitCode.committed);
  }

  @override
  Future<RoutineModel?> createOrVerify(RoutineModel routine) async => routine;

  @override
  Future<List<RoutineModel>> listForAccount(String accountScopeId) async =>
      const [];
}

class _Backend implements ChatBackendClient {
  final EventMutationRequest request;
  _Backend(this.request);

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    final target = this.request.target;
    final changes = this.request.changes!;
    return ChatBackendResponse(
      reply: 'Mutation',
      actions: [
        {
          'type': 'event_mutation',
          'operation': 'update',
          'target': {
            if (target.title != null) 'title': target.title,
            if (target.date != null) 'date': target.date,
            if (target.time != null) 'time': target.time,
          },
          'changes': {if (changes.time != null) 'time': changes.time},
        }
      ],
      memories: const [],
    );
  }
}

class _Context implements ConversationContextProvider {
  @override
  Future<ChatBackendRequest> buildRequest(
          {required message, required profile}) async =>
      const ChatBackendRequest(
        message: '',
        profile: {},
        profileContext: {},
        memories: [],
        memoryReasoning: [],
        events: [],
      );

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

class _Ids implements EntityIdGenerator {
  int value = 0;
  @override
  String generate() => 'event-mutation-${++value}';
}

EventModel _event(String id, String time) => EventModel(
      id: id,
      title: 'Médecin',
      date: '2026-07-23',
      time: time,
      notes: '',
      category: 'Personnel',
      createdAt: DateTime.utc(2026, 7, 20),
      startDateTimeIso: '2026-07-23T$time:00.000Z',
      durationMinutes: 30,
    );

UserProfile _profile() => UserProfile(
      firstName: 'Person',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
