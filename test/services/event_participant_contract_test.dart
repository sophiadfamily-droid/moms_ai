import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_participant.dart';
import 'package:moms_ai/services/action_handler_service.dart';
import 'package:moms_ai/services/planning_draft_service.dart';
import 'package:moms_ai/services/zelia_action_guard_service.dart';

void main() {
  const rawParticipant = {
    'label': '  Person   A  ',
    'entityType': 'person',
    'evidence': 'explicit_user_input',
  };

  test('guard converts the closed map to a typed participant', () {
    final result = ZeliaActionGuardService.guard({
      'type': 'event',
      'title': 'Rendez-vous',
      'participant': rawParticipant,
    });

    expect(result.isAccepted, true);
    expect(result.action!['participant'], isA<EventParticipant>());
    final participant = result.action!['participant'] as EventParticipant;
    expect(participant.label, 'Person A');
    expect(participant.entityType, EventParticipantEntityType.person);
    expect(participant.evidence, EventParticipantEvidence.explicitUserInput);
  });

  test('invalid participant is removed with a stable diagnostic', () {
    for (final participant in [
      {...rawParticipant, 'entityType': 'place'},
      {...rawParticipant, 'evidence': 'model_inference'},
      {...rawParticipant, 'alias': 'forbidden'},
      {...rawParticipant, 'label': ''},
      'Person A',
    ]) {
      final result = ZeliaActionGuardService.guard({
        'type': 'event',
        'title': 'Rendez-vous',
        'participant': participant,
      });
      expect(result.isAccepted, true);
      expect(result.action!.containsKey('participant'), false);
      expect(result.corrections, contains('invalid_event_participant_removed'));
    }
  });

  test('non-event action cannot retain a participant', () {
    final result = ZeliaActionGuardService.guard({
      'type': 'task',
      'title': 'Appeler',
      'participant': rawParticipant,
    });
    expect(result.isAccepted, true);
    expect(result.action!.containsKey('participant'), false);
  });

  test('participant survives planning-draft conversion', () {
    final participant = EventParticipant(
      label: 'Person A',
      entityType: EventParticipantEntityType.person,
      evidence: EventParticipantEvidence.explicitUserInput,
    );
    final draft = PlanningDraftService.buildFromAction(
      action: {
        'type': 'event',
        'title': 'Rendez-vous',
        'date': '2026-07-23',
        'participant': participant,
      },
      sourceMessage: 'Action structurée',
      needsTravel: false,
    );
    final pending = PlanningDraftService.toPendingTimeEvent(
      draft,
      participant: participant,
    );
    expect(pending['participant'], same(participant));
  });

  test('participant survives date, time, and duration collection drafts',
      () async {
    final participant = EventParticipant(
      label: 'Person A',
      entityType: EventParticipantEntityType.person,
      evidence: EventParticipantEvidence.explicitUserInput,
    );

    Future<ActionHandlerResult> handle(Map<String, dynamic> action) {
      return ActionHandlerService.handleAction(
        action: action,
        currentUserMessage: 'Action structurée',
        normalizeTime: (value) => value,
        parseDurationMinutes: (_) => 0,
        weekdayFromText: () => 0,
        messageLooksRecurringWeekly: () => false,
        nextDateForWeekday: (_) => '',
        eventNeedsTravel: (_) => false,
        buildStartDateTimeIso: ({required date, required time}) =>
            '${date}T$time:00',
        buildEndDateTimeIso: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '${date}T$time:00',
        endTimeFromDuration: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            time,
      );
    }

    final base = <String, dynamic>{
      'type': 'event',
      'title': 'Rendez-vous',
      'participant': participant,
    };
    final date = await handle(base);
    final time = await handle({...base, 'date': '2026-07-23'});
    final duration = await handle({
      ...base,
      'date': '2026-07-23',
      'time': '10:00',
    });

    expect(date.pendingDateEvent!['participant'], same(participant));
    expect(time.pendingTimeEvent!['participant'], same(participant));
    expect(duration.pendingDurationEvent!['participant'], same(participant));
  });

  test('participant survives event confirmation without entering EventModel',
      () {
    final participant = EventParticipant(
      label: 'Person A',
      entityType: EventParticipantEntityType.person,
      evidence: EventParticipantEvidence.explicitUserInput,
    );
    final event = EventModel(
      title: 'Rendez-vous',
      date: '2026-07-23',
      time: '10:00',
      notes: '',
      createdAt: DateTime.utc(2026, 7, 22),
      startDateTimeIso: '2026-07-23T10:00:00',
    );
    final pending = PendingConversationAction.eventConfirmation(
      event,
      eventParticipant: participant,
    );
    expect(pending.eventParticipant, same(participant));
    expect(event.toJson().containsKey('participant'), false);
  });

  test('participant value has structural equality and safe debug output', () {
    final first = EventParticipant(
      label: 'Person A',
      entityType: EventParticipantEntityType.person,
      evidence: EventParticipantEvidence.explicitUserInput,
    );
    final second = EventParticipant(
      label: 'Person A',
      entityType: EventParticipantEntityType.person,
      evidence: EventParticipantEvidence.explicitUserInput,
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.toString(), isNot(contains('Person A')));
  });
}
