import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/models/routine/routine_zoned_occurrence_models.dart';
import 'package:moms_ai/services/routine/routine_event_conflict_engine.dart';

void main() {
  const engine = RoutineEventConflictEngine();

  test('proves one conflict from complete protected ranges', () {
    final conflicts = engine.evaluate(
      routineProjection: _routines(
        start: DateTime.utc(2026, 8, 4, 8),
        end: DateTime.utc(2026, 8, 4, 9),
        protectedStart: DateTime.utc(2026, 8, 4, 7, 50),
        protectedEnd: DateTime.utc(2026, 8, 4, 9, 10),
      ),
      routineSection: _routineSection(),
      eventSection: _eventSection(
        start: DateTime.utc(2026, 8, 4, 9),
        end: DateTime.utc(2026, 8, 4, 10),
        travelGoMinutes: 5,
      ),
      observedAt: DateTime.utc(2026, 8, 4),
    );

    final conflict = conflicts.single;
    expect(conflict.confirmedByCanonicalEngine, true);
    expect(conflict.firstSourceId, 'event-a');
    expect(conflict.secondSourceId, 'routine-a:2026-08-04');
    expect(
      conflict.evidence.map((item) => item.sourceType),
      [
        DetectionEvidenceSource.fixedEventInterval,
        DetectionEvidenceSource.structuredRoutineOccurrence,
      ],
    );
    expect(
      conflict.evidence.first.intervalStart,
      DateTime.utc(2026, 8, 4, 8, 55),
    );
    expect(
      conflict.evidence.first.intervalEnd,
      DateTime.utc(2026, 8, 4, 9, 10),
    );
  });

  test('does not report adjacent or out-of-horizon ranges', () {
    final routine = _routines(
      start: DateTime.utc(2026, 8, 4, 8),
      end: DateTime.utc(2026, 8, 4, 9),
      protectedStart: DateTime.utc(2026, 8, 4, 8),
      protectedEnd: DateTime.utc(2026, 8, 4, 9),
    );
    expect(
      engine.evaluate(
        routineProjection: routine,
        routineSection: _routineSection(),
        eventSection: _eventSection(
          start: DateTime.utc(2026, 8, 4, 9),
          end: DateTime.utc(2026, 8, 4, 10),
        ),
        observedAt: DateTime.utc(2026, 8, 4),
      ),
      isEmpty,
    );
    expect(
      engine.evaluate(
        routineProjection: routine,
        routineSection: _routineSection(),
        eventSection: _eventSection(
          start: DateTime.utc(2026, 8, 4, 8, 30),
          end: DateTime.utc(2026, 8, 4, 9, 30),
        ),
        observedAt: DateTime.utc(2026, 9, 1),
      ),
      isEmpty,
    );
  });

  test('rejects an unbounded conflict request', () {
    expect(
      () => engine.evaluate(
        routineProjection: _routines(
          start: DateTime.utc(2026, 8, 4, 8),
          end: DateTime.utc(2026, 8, 4, 9),
          protectedStart: DateTime.utc(2026, 8, 4, 8),
          protectedEnd: DateTime.utc(2026, 8, 4, 9),
        ),
        routineSection: _routineSection(),
        eventSection: _eventSection(
          start: DateTime.utc(2026, 8, 4, 8),
          end: DateTime.utc(2026, 8, 4, 9),
        ),
        observedAt: DateTime.utc(2026, 8, 4),
        horizon: const Duration(days: 32),
      ),
      throwsFormatException,
    );
  });
}

RoutineZonedOccurrenceProjection _routines({
  required DateTime start,
  required DateTime end,
  required DateTime protectedStart,
  required DateTime protectedEnd,
}) =>
    RoutineZonedOccurrenceProjection(
      accountScopeId: 'account-a',
      timezoneId: 'Europe/Paris',
      occurrences: [
        RoutineZonedOccurrence(
          occurrenceId: 'routine-a:2026-08-04',
          routineId: 'routine-a',
          accountScopeId: 'account-a',
          timezoneId: 'Europe/Paris',
          start: start,
          end: end,
          protectedStart: protectedStart,
          protectedEnd: protectedEnd,
          sourceUpdatedAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );

RoutineDomainSection _routineSection() => RoutineDomainSection(
      metadata: _metadata(LifeContextDomain.routine),
    );

EventDomainSection _eventSection({
  required DateTime start,
  required DateTime end,
  int travelGoMinutes = 0,
}) =>
    EventDomainSection(
      metadata: _metadata(LifeContextDomain.event),
      events: [
        EventContextItem(
          id: 'event-a',
          title: 'Private',
          startDateTimeIso: start.toIso8601String(),
          endDateTimeIso: end.toIso8601String(),
          durationMinutes: end.difference(start).inMinutes,
          travelGoMinutes: travelGoMinutes,
          travelBackMinutes: 0,
          marginMinutes: 0,
          isRecurring: false,
          recurringType: 'none',
          revision: 3,
          syncStatus: 'synced',
        ),
      ],
    );

LifeContextSourceMetadata _metadata(LifeContextDomain domain) =>
    LifeContextSourceMetadata(
      domain: domain,
      source: domain == LifeContextDomain.event
          ? LifeContextSourceKind.eventService
          : LifeContextSourceKind.legacyProfileRoutine,
      readAt: DateTime.utc(2026, 8, 4),
      availability: LifeContextAvailability.available,
      freshness: LifeContextFreshness.current,
      isLocal: false,
      itemCount: 1,
      syncStatus: 'synced',
      revision: 3,
    );
