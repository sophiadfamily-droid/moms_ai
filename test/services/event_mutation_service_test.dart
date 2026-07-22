import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_participant_identity_link.dart';
import 'package:moms_ai/services/event_mutation_service.dart';
import 'package:moms_ai/services/event_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final originalLink = _link('identity-1');
  final replacementLink = _link('identity-2');

  test('standard business mutations preserve the exact participant link', () {
    final existing = _event(link: originalLink);
    final proposals = [
      existing.copyWith(title: 'Updated'),
      existing.copyWith(date: '2026-08-01'),
      existing.copyWith(time: '11:00'),
      existing.copyWith(durationMinutes: 60),
      existing.copyWith(travelGoMinutes: 20, travelBackMinutes: 25),
      existing.copyWith(marginMinutes: 15),
      existing.copyWith(notes: 'Updated notes'),
      existing.copyWith(category: 'Work'),
      existing.copyWith(isRecurring: true, recurringType: 'weekly'),
    ];
    for (final proposed in proposals) {
      final result = EventMutationService.apply(
        existing: existing,
        proposed: proposed,
      );
      expect(result.participantIdentity, originalLink);
      expect(result.participantIdentityRevision, 1);
    }
  });

  test('historical reconstruction cannot erase a linked participant', () {
    final existing = _event(link: originalLink);
    final reconstructed = _event(link: null).copyWith(title: 'Legacy edit');
    final reconciled = EventMutationService.reconcileFullRewrite(
      existing: [existing],
      proposed: [reconstructed],
    );
    expect(reconciled.single.title, 'Legacy edit');
    expect(reconciled.single.participantIdentity, originalLink);
    expect(reconciled.single.participantIdentityRevision, 1);
  });

  test('replacement is explicit, revisioned, and scope-safe', () {
    final existing = _event(link: originalLink);
    final replacement = EventMutationService.apply(
      existing: existing,
      proposed: existing.copyWith(title: 'Updated'),
      participantIntent: ReplaceEventParticipant(replacementLink),
    );
    expect(existing.participantIdentity, originalLink);
    expect(replacement.participantIdentity, replacementLink);
    expect(replacement.participantIdentityRevision, 2);
    expect(
      () => EventMutationService.apply(
        existing: existing,
        proposed: existing,
        participantIntent: ReplaceEventParticipant(
          _link('identity-2', scope: 'account-b'),
        ),
      ),
      throwsFormatException,
    );
  });

  test('explicit removal clears only the link and increments its revision', () {
    final existing = _event(link: originalLink);
    final removed = EventMutationService.apply(
      existing: existing,
      proposed: existing.copyWith(title: 'Still here'),
      participantIntent: const RemoveEventParticipant(),
    );
    expect(removed.participantIdentity, isNull);
    expect(removed.participantIdentityRevision, 2);
    expect(removed.title, 'Still here');
    expect(removed.date, existing.date);
  });

  test('user duplication strips link and stable event identity', () {
    final duplicate = EventMutationService.duplicate(
      _event(link: originalLink),
    );
    expect(duplicate.id, isNull);
    expect(duplicate.participantIdentity, isNull);
    expect(duplicate.participantIdentityRevision, 0);
  });

  test('technical recurrence preserves the participant link', () {
    final occurrences = EventService.buildWeeklyOccurrences(
      baseEvent: _event(link: originalLink).copyWith(
        isRecurring: true,
        recurringType: 'weekly',
      ),
      count: 2,
    );
    expect(occurrences.every((event) => event.id == null), true);
    expect(
      occurrences.every((event) => event.participantIdentity == originalLink),
      true,
    );
  });

  test('local full rewrites preserve old links and explicit removals',
      () async {
    final existing = _event(link: originalLink);
    SharedPreferences.setMockInitialValues({
      EventService.eventsKey: [jsonEncode(existing.toJson())],
    });
    await EventService.saveEvents([
      _event(link: null).copyWith(title: 'Legacy edit'),
    ]);
    var stored = await _storedEvents();
    expect(stored.single.participantIdentity, originalLink);

    final removed = EventMutationService.apply(
      existing: stored.single,
      proposed: stored.single,
      participantIntent: const RemoveEventParticipant(),
    );
    await EventService.saveEvents([removed]);
    stored = await _storedEvents();
    expect(stored.single.participantIdentity, isNull);
    expect(stored.single.participantIdentityRevision, 2);
  });

  test('event deletion and retry remove no other event or Identity data',
      () async {
    final linked = _event(link: originalLink);
    final other = _event(id: 'event-2', link: originalLink);
    SharedPreferences.setMockInitialValues({
      EventService.eventsKey: [
        jsonEncode(linked.toJson()),
        jsonEncode(other.toJson()),
      ],
    });
    await EventService.updateEvents([other]);
    expect((await _storedEvents()).map((event) => event.id), ['event-2']);
    await EventService.updateEvents([other]);
    expect((await _storedEvents()).map((event) => event.id), ['event-2']);
    expect(originalLink.identity.entityId, 'identity-1');
  });
}

EventParticipantIdentityLink _link(
  String entityId, {
  String scope = 'account-a',
}) =>
    EventParticipantIdentityLink(
      identity: PersistedIdentityLink(
        entityId: entityId,
        entityType: EntityType.person,
      ),
      accountScopeId: scope,
    );

EventModel _event({
  String id = 'event-1',
  EventParticipantIdentityLink? link,
}) =>
    EventModel(
      id: id,
      title: 'Event',
      date: '2026-07-23',
      time: '10:00',
      notes: 'Notes',
      category: 'Personal',
      createdAt: DateTime.utc(2026, 7, 22),
      startDateTimeIso: '2026-07-23T10:00:00.000Z',
      durationMinutes: 45,
      travelGoMinutes: 10,
      travelBackMinutes: 20,
      usesSeparateTravelTimes: true,
      marginMinutes: 5,
      participantIdentity: link,
    );

Future<List<EventModel>> _storedEvents() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(EventService.eventsKey) ?? const [])
      .map(
        (value) => EventModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(value) as Map),
        ),
      )
      .toList();
}
