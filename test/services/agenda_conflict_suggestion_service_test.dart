import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/services/agenda_conflict_suggestion_service.dart';
import 'package:moms_ai/services/routine/routine_agenda_service.dart';

void main() {
  test('suggests a future slot outside events and protected routine time',
      () async {
    var routineLoads = 0;
    final target = EventModel(
      id: 'event-a',
      title: 'Coiffeur',
      date: '2026-08-06',
      time: '08:30',
      notes: '',
      createdAt: DateTime.utc(2026, 8, 1),
      startDateTimeIso: '2026-08-06T08:30:00',
      durationMinutes: 60,
      travelGoMinutes: 15,
      travelBackMinutes: 15,
      usesSeparateTravelTimes: true,
    );
    final routine = RoutineModel(
      id: 'routine-a',
      accountScopeId: 'account-a',
      logicalRequestId: 'request-a',
      title: 'École',
      recurrenceType: RoutineRecurrenceType.weekdays,
      days: const [],
      startTime: '08:00',
      durationMinutes: 60,
      travelGoMinutes: 0,
      travelBackMinutes: 0,
      marginMinutes: 0,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final service = AgendaConflictSuggestionService(
      loadEvents: () async => [target],
      routineAgendaService: RoutineAgendaService(
        loadRoutines: (_) async {
          routineLoads++;
          return [routine];
        },
      ),
      clock: () => DateTime(2026, 8, 6, 7),
    );

    final suggestion = await service.suggest(
      accountScopeId: 'account-a',
      eventId: 'event-a',
    );

    expect(suggestion, isNotNull);
    expect(suggestion!.dateIso, '2026-08-06');
    final proposedStart = DateTime.parse(
      '${suggestion.dateIso}T${suggestion.time}:00',
    );
    final protectedStart = proposedStart.subtract(const Duration(minutes: 15));
    expect(
      protectedStart.isBefore(DateTime(2026, 8, 6, 9)),
      isFalse,
    );
    expect(routineLoads, 1);
  });

  test('does not invent a suggestion for an unknown event', () async {
    final service = AgendaConflictSuggestionService(
      loadEvents: () async => const [],
      routineAgendaService: RoutineAgendaService(
        loadRoutines: (_) async => const [],
      ),
      clock: () => DateTime(2026, 8, 6, 7),
    );

    expect(
      await service.suggest(
        accountScopeId: 'account-a',
        eventId: 'missing',
      ),
      isNull,
    );
  });

  test('does not suggest moving an event that is already over', () async {
    final service = AgendaConflictSuggestionService(
      loadEvents: () async => [
        EventModel(
          id: 'past-event',
          title: 'Ancien rendez-vous',
          date: '2026-08-05',
          time: '08:00',
          notes: '',
          createdAt: DateTime.utc(2026, 8, 1),
          startDateTimeIso: '2026-08-05T08:00:00',
          durationMinutes: 60,
        ),
      ],
      routineAgendaService: RoutineAgendaService(
        loadRoutines: (_) async => const [],
      ),
      clock: () => DateTime(2026, 8, 6, 7),
    );

    expect(
      await service.suggest(
        accountScopeId: 'account-a',
        eventId: 'past-event',
      ),
      isNull,
    );
  });
}
