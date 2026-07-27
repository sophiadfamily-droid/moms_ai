import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_mutation_models.dart';
import 'package:moms_ai/models/event_participant_identity_link.dart';
import 'package:moms_ai/services/event_conversation_mutation_service.dart';
import 'package:moms_ai/services/event_mutation_service.dart';
import 'package:moms_ai/services/event_mutation_result.dart';
import 'package:moms_ai/services/event_target_selector.dart';

void main() {
  test('proposes every allowed change while preserving Identity', () {
    final original = _event();
    final service =
        EventConversationMutationService(loadEvents: () async => []);
    final proposed = service.propose(
      original,
      EventMutationChanges(
        title: 'Nouveau titre',
        date: '2026-07-24',
        time: '11:00',
        durationMinutes: 60,
        travelGoMinutes: 15,
        travelBackMinutes: 20,
        marginMinutes: 10,
        notes: 'Note',
        category: 'Travail',
      ),
    );
    expect(proposed.title, 'Nouveau titre');
    expect(proposed.date, '2026-07-24');
    expect(proposed.time, '11:00');
    expect(proposed.durationMinutes, 60);
    expect(proposed.travelGoMinutes, 15);
    expect(proposed.travelBackMinutes, 20);
    expect(proposed.marginMinutes, 10);
    expect(proposed.notes, 'Note');
    expect(proposed.category, 'Travail');
    expect(proposed.participantIdentity, original.participantIdentity);
    expect(proposed.participantIdentityRevision, 1);
  });

  test('executes once with PreserveEventParticipant', () async {
    final original = _event();
    var writes = 0;
    EventParticipantMutationIntent? intent;
    final service = EventConversationMutationService(
      loadEvents: () async => [original],
      write: (
          {required existing,
          required proposed,
          required expectedEventRevision,
          required participantIntent}) async {
        writes++;
        intent = participantIntent;
        return EventMutationResult.success(
          proposed.copyWith(eventRevision: expectedEventRevision + 1),
        );
      },
    );
    final result = await service.execute(
      original: original,
      proposed: service.propose(original, EventMutationChanges(time: '11:00')),
    );
    expect(result.status, EventMutationExecutionStatus.updated);
    expect(writes, 1);
    expect(intent, isA<PreserveEventParticipant>());
  });

  test('blocks disappearance, concurrent changes and conflicts', () async {
    final original = _event();
    final proposed =
        EventConversationMutationService(loadEvents: () async => [])
            .propose(original, EventMutationChanges(time: '11:00'));
    final missing =
        EventConversationMutationService(loadEvents: () async => []);
    expect(
        (await missing.execute(original: original, proposed: proposed)).status,
        EventMutationExecutionStatus.notFound);
    final changed = EventConversationMutationService(
      loadEvents: () async => [original.copyWith(title: 'Changed')],
    );
    expect(
        (await changed.execute(original: original, proposed: proposed)).status,
        EventMutationExecutionStatus.concurrentChange);
    final conflict = EventConversationMutationService(
      loadEvents: () async => [original, proposed.copyWith(id: 'other')],
      write: ({
        required existing,
        required proposed,
        required expectedEventRevision,
        required participantIntent,
      }) async =>
          fail('conflicting mutation must not write'),
    );
    expect(
        (await conflict.execute(original: original, proposed: proposed)).status,
        EventMutationExecutionStatus.conflict);
  });

  test('locally revalidates stable event IDs from conversation state',
      () async {
    final service = EventConversationMutationService(
      loadEvents: () async => [_event(), _event(id: 'event-2')],
    );

    final selected = await service.selectVerifiedIds(['event-1']);
    final ambiguous = await service.selectVerifiedIds(['event-2', 'event-1']);
    final forged = await service.selectVerifiedIds(['backend-only']);

    expect(selected.selected?.id, 'event-1');
    expect(ambiguous.status, EventTargetSelectionStatus.ambiguous);
    expect(
      ambiguous.candidates.map((event) => event.id),
      ['event-1', 'event-2'],
    );
    expect(forged.status, EventTargetSelectionStatus.notFound);
  });
}

EventModel _event({String id = 'event-1'}) => EventModel(
      id: id,
      title: 'Médecin',
      date: '2026-07-23',
      time: '10:00',
      notes: '',
      category: 'Personnel',
      createdAt: DateTime.utc(2026, 7, 20),
      startDateTimeIso: '2026-07-23T10:00:00.000Z',
      durationMinutes: 30,
      participantIdentity: EventParticipantIdentityLink(
        identity: PersistedIdentityLink(
          entityId: 'identity-1',
          entityType: EntityType.person,
        ),
        accountScopeId: 'account-a',
      ),
    );
