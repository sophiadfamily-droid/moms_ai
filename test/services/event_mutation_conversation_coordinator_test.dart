import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_mutation_models.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/event_conversation_mutation_service.dart';
import 'package:moms_ai/services/event_mutation_result.dart';

void main() {
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
    expect(outcome?.reply, contains('Confirmer'));
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
    expect(selected?.reply, contains('Confirmer'));
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
    actionDraftIdGenerator: _Ids(),
    clock: () => fixture.now,
  );
  fixture = _Fixture._(coordinator, events, nowBox.single);
  return fixture;
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
