import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/proactive_detection.dart';
import 'package:moms_ai/services/life_context/event_life_context_conflict_engine.dart';

void main() {
  const engine = EventLifeContextConflictEngine();
  final now = DateTime.utc(2026, 8, 25, 8);

  test('proves an Event conflict from one Life Context section', () {
    final section = _section([
      _event(
        id: 'event-a',
        start: DateTime.utc(2026, 8, 25, 10),
        end: DateTime.utc(2026, 8, 25, 11),
        travelGo: 15,
        revision: 2,
      ),
      _event(
        id: 'event-b',
        start: DateTime.utc(2026, 8, 25, 9, 50),
        end: DateTime.utc(2026, 8, 25, 10, 10),
        travelBack: 5,
        margin: 5,
        revision: 7,
      ),
    ]);

    final conflict =
        engine.evaluate(eventSection: section, observedAt: now).single;

    expect(conflict.conflictId, 'event-a:event-b:protected-v1');
    expect(conflict.firstRevision, 2);
    expect(conflict.secondRevision, 7);
    expect(conflict.confirmedByCanonicalEngine, true);
    expect(
      conflict.evidence.first.intervalStart,
      DateTime.utc(2026, 8, 25, 9, 50),
    );
    expect(
      conflict.evidence.first.intervalEnd,
      DateTime.utc(2026, 8, 25, 10, 20),
    );
    expect(
      conflict.evidence.map((item) => item.sourceType),
      everyElement(DetectionEvidenceSource.confirmedConflictResult),
    );
  });

  test('does not report adjacent, invalid or already finished ranges', () {
    final conflicts = engine.evaluate(
      eventSection: _section([
        _event(
          id: 'finished',
          start: DateTime.utc(2026, 8, 25, 6),
          end: DateTime.utc(2026, 8, 25, 7),
        ),
        _event(
          id: 'first',
          start: DateTime.utc(2026, 8, 25, 9),
          end: DateTime.utc(2026, 8, 25, 10),
        ),
        _event(
          id: 'second',
          start: DateTime.utc(2026, 8, 25, 10),
          end: DateTime.utc(2026, 8, 25, 11),
        ),
        const EventContextItem(
          id: 'invalid',
          title: 'Invalid',
          startDateTimeIso: 'not-a-date',
          endDateTimeIso: 'not-a-date',
          durationMinutes: 60,
          travelGoMinutes: 0,
          travelBackMinutes: 0,
          marginMinutes: 0,
          isRecurring: false,
          recurringType: 'none',
          revision: 0,
          syncStatus: 'synced',
        ),
      ]),
      observedAt: now,
    );

    expect(conflicts, isEmpty);
  });

  test('keeps event and result limits bounded', () {
    expect(
      () => engine.evaluate(
        eventSection: _section(const []),
        observedAt: now,
        maximumEvents: 201,
      ),
      throwsFormatException,
    );
    expect(
      () => engine.evaluate(
        eventSection: _section(const []),
        observedAt: now,
        maximumConflicts: 101,
      ),
      throwsFormatException,
    );
  });

  test('fails closed when the Event section is unavailable', () {
    expect(
      () => engine.evaluate(
        eventSection: EventDomainSection(
          metadata: _metadata(
            itemCount: 0,
            availability: LifeContextAvailability.unavailable,
          ),
        ),
        observedAt: now,
      ),
      throwsFormatException,
    );
  });
}

EventDomainSection _section(List<EventContextItem> events) =>
    EventDomainSection(
      metadata: _metadata(itemCount: events.length),
      events: events,
    );

LifeContextSourceMetadata _metadata({
  required int itemCount,
  LifeContextAvailability availability = LifeContextAvailability.available,
}) =>
    LifeContextSourceMetadata(
      domain: LifeContextDomain.event,
      source: LifeContextSourceKind.eventService,
      readAt: DateTime.utc(2026, 8, 25, 8),
      availability: availability,
      freshness: LifeContextFreshness.current,
      isLocal: false,
      itemCount: itemCount,
      revision: 8,
      syncStatus: 'synced',
    );

EventContextItem _event({
  required String id,
  required DateTime start,
  required DateTime end,
  int travelGo = 0,
  int travelBack = 0,
  int margin = 0,
  int revision = 1,
}) =>
    EventContextItem(
      id: id,
      title: 'Private',
      startDateTimeIso: start.toIso8601String(),
      endDateTimeIso: end.toIso8601String(),
      durationMinutes: end.difference(start).inMinutes,
      travelGoMinutes: travelGo,
      travelBackMinutes: travelBack,
      marginMinutes: margin,
      isRecurring: false,
      recurringType: 'none',
      revision: revision,
      syncStatus: 'synced',
    );
