import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_mutation_models.dart';
import 'package:moms_ai/services/event_target_selector.dart';

void main() {
  test('selects exactly by date and time', () {
    final result = EventTargetSelector.select(
      events: [_event('a', 'Médecin', '10:00'), _event('b', 'École', '11:00')],
      target: EventMutationTarget(date: '2026-07-23', time: '10:00'),
    );
    expect(result.status, EventTargetSelectionStatus.selected);
    expect(result.selected?.id, 'a');
  });

  test('normalizes title and combines title date and time', () {
    final result = EventTargetSelector.select(
      events: [_event('a', 'Rendez-vous Médecin', '10:00')],
      target: EventMutationTarget(
        title: 'medecin',
        date: '2026-07-23',
        time: '10:00',
      ),
    );
    expect(result.selected?.id, 'a');
  });

  test('returns notFound and never selects an ambiguous partial title', () {
    final events = [
      _event('b', 'Rendez-vous école', '11:00'),
      _event('a', 'Rendez-vous médecin', '10:00'),
    ];
    final none = EventTargetSelector.select(
      events: events,
      target: EventMutationTarget(title: 'dentiste'),
    );
    expect(none.status, EventTargetSelectionStatus.notFound);
    final ambiguous = EventTargetSelector.select(
      events: events,
      target: EventMutationTarget(title: 'rendez-vous'),
    );
    expect(ambiguous.status, EventTargetSelectionStatus.ambiguous);
    expect(ambiguous.candidates.map((event) => event.id), ['a', 'b']);
  });

  test('selection is independent from input order', () {
    final first = _event('a', 'Médecin', '10:00');
    final second = _event('b', 'Médecin', '11:00');
    final target = EventMutationTarget(title: 'Médecin');
    final normal = EventTargetSelector.select(
      events: [first, second],
      target: target,
    );
    final reversed = EventTargetSelector.select(
      events: [second, first],
      target: target,
    );
    expect(normal.candidates.map((event) => event.id),
        reversed.candidates.map((event) => event.id));
  });

  test('historical candidate without stable ID is never selected', () {
    final result = EventTargetSelector.select(
      events: [_event(null, 'Médecin', '10:00')],
      target: EventMutationTarget(title: 'Médecin'),
    );
    expect(result.status, EventTargetSelectionStatus.invalid);
  });
}

EventModel _event(String? id, String title, String time) => EventModel(
      id: id,
      title: title,
      date: '2026-07-23',
      time: time,
      notes: '',
      category: 'Personnel',
      createdAt: DateTime.utc(2026, 7, 20),
      startDateTimeIso: '2026-07-23T$time:00.000Z',
      durationMinutes: 30,
    );
