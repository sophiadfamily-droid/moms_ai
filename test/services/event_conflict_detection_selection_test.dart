import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/services/event_service.dart';

void main() {
  test('conflict detection keeps the nearest events before applying its limit',
      () {
    final now = DateTime.utc(2026, 8, 9, 12);
    final farEvents = List.generate(
      120,
      (index) => _event(
        id: 'far-$index',
        start: DateTime.utc(2026, 9, 1).add(Duration(hours: index)),
      ),
    );
    final firstConflict = _event(
      id: 'qaaa-one',
      start: DateTime.utc(2026, 8, 12, 12),
    );
    final secondConflict = _event(
      id: 'qaaa-two',
      start: DateTime.utc(2026, 8, 12, 12),
    );

    final selected = EventService.selectUpcomingEventsForConflictDetection(
      [...farEvents, firstConflict, secondConflict],
      observedAt: now,
      maximumEvents: 100,
    );

    expect(selected.map((event) => event.id),
        containsAll(['qaaa-one', 'qaaa-two']));
    expect(selected, hasLength(100));
  });
}

EventModel _event({required String id, required DateTime start}) => EventModel(
      id: id,
      title: 'qaaa',
      notes: '',
      date: start.toIso8601String().substring(0, 10),
      time:
          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
      startDateTimeIso: start.toIso8601String(),
      endDateTimeIso: start.add(const Duration(hours: 1)).toIso8601String(),
      createdAt: DateTime.utc(2026, 8, 1),
    );
