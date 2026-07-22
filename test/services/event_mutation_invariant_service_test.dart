import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/event_mutation_invariant_service.dart';

void main() {
  test('descriptive mutation does not invoke planning constraints', () {
    final existing = _event('event', '10:00');
    final result = EventMutationInvariantService.validate(
      existing: existing,
      proposed: existing.copyWith(title: 'Nouveau titre'),
      events: [_event('other', '10:00')],
      blockedReasoning: const [
        {
          'type': 'blocked_period',
          'days': ['jeudi'],
          'startTime': '09:00',
          'endTime': '12:00',
        }
      ],
    );
    expect(result.status, EventMutationInvariantStatus.valid);
  });

  test('temporal rebase detects overlap including travel and margin', () {
    final existing = _event('event', '08:00');
    final proposed = _event('event', '10:00').copyWith(
      travelGoMinutes: 15,
      travelBackMinutes: 15,
      usesSeparateTravelTimes: true,
      marginMinutes: 10,
    );
    final other = _event('other', '09:30');
    final result = EventMutationInvariantService.validate(
      existing: existing,
      proposed: proposed,
      events: [other],
    );
    expect(result.status, EventMutationInvariantStatus.planningConflict);
  });

  test('temporal rebase detects protected school or routine period', () {
    final existing = _event('event', '08:00');
    final proposed = _event('event', '10:00');
    final result = EventMutationInvariantService.validate(
      existing: existing,
      proposed: proposed,
      events: const [],
      blockedReasoning: const [
        {
          'type': 'blocked_period',
          'days': ['jeudi'],
          'startTime': '09:00',
          'endTime': '12:00',
        }
      ],
    );
    expect(result.status, EventMutationInvariantStatus.planningConflict);
  });

  test('series scope cannot be silently rebased', () {
    final existing = _event('event', '10:00');
    final result = EventMutationInvariantService.validate(
      existing: existing,
      proposed: existing.copyWith(isRecurring: true, recurringType: 'weekly'),
      events: const [],
    );
    expect(result.status, EventMutationInvariantStatus.unsupportedRebase);
  });
}

EventModel _event(String id, String time) => EventModel(
      id: id,
      title: 'Synthétique',
      date: '2026-07-23',
      time: time,
      notes: '',
      createdAt: DateTime.utc(2026, 7, 22),
      startDateTimeIso: '2026-07-23T$time:00',
      durationMinutes: 60,
      eventRevision: 2,
    );
