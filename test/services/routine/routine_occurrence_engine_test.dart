import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine/routine_occurrence_models.dart';
import 'package:moms_ai/models/routine/routine_occurrence_override.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/services/routine/routine_occurrence_engine.dart';

void main() {
  const engine = RoutineOccurrenceEngine();

  test('projects weekly and weekdays in deterministic date order', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 3),
      windowEndDateExclusive: DateTime.utc(2026, 8, 10),
      routines: [
        _routine(
          id: 'weekly',
          recurrenceType: RoutineRecurrenceType.weekly,
          days: const [DateTime.tuesday],
          startTime: '09:00',
        ),
        _routine(
          id: 'weekdays',
          recurrenceType: RoutineRecurrenceType.weekdays,
          days: const [],
          startTime: '08:00',
        ),
      ],
    );

    expect(output.occurrences, hasLength(6));
    expect(output.occurrences.first.occurrenceId, 'weekdays:2026-08-03');
    expect(
      output.occurrences.map((item) => item.occurrenceId),
      contains('weekly:2026-08-04'),
    );
  });

  test('projects only active biweekly anchor weeks', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 3),
      windowEndDateExclusive: DateTime.utc(2026, 8, 25),
      routines: [
        _routine(
          id: 'biweekly',
          recurrenceType: RoutineRecurrenceType.biweekly,
          days: const [DateTime.tuesday],
          anchorDateIso: '2026-08-04',
        ),
      ],
    );

    expect(
      output.occurrences.map((item) => item.dateIso),
      ['2026-08-04', '2026-08-18'],
    );
  });

  test('supports nth and last weekday monthly recurrence', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 1),
      windowEndDateExclusive: DateTime.utc(2026, 9, 1),
      routines: [
        _routine(
          id: 'second-tuesday',
          recurrenceType: RoutineRecurrenceType.monthlyNthWeekday,
          days: const [DateTime.tuesday],
          weekOfMonth: 2,
        ),
        _routine(
          id: 'last-friday',
          recurrenceType: RoutineRecurrenceType.monthlyNthWeekday,
          days: const [DateTime.friday],
          weekOfMonth: -1,
        ),
      ],
    );

    expect(
      output.occurrences.map((item) => item.occurrenceId),
      ['second-tuesday:2026-08-11', 'last-friday:2026-08-28'],
    );
  });

  test('excludes cancelled routines and fails closed across accounts', () {
    final cancelled = _routine(
      id: 'cancelled',
      recurrenceType: RoutineRecurrenceType.weekly,
      days: const [DateTime.monday],
      status: RoutineStatus.cancelled,
    );
    expect(
      engine.project(
        accountScopeId: 'account-a',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 4),
        routines: [cancelled],
      ).occurrences,
      isEmpty,
    );
    expect(
      () => engine.project(
        accountScopeId: 'account-b',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 4),
        routines: [cancelled],
      ),
      throwsA(isA<RoutineOccurrenceException>()),
    );
  });

  test('cancels one occurrence without cancelling the recurring routine', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 3),
      windowEndDateExclusive: DateTime.utc(2026, 8, 18),
      routines: [
        _routine(
          id: 'sport',
          recurrenceType: RoutineRecurrenceType.weekly,
          days: const [DateTime.tuesday],
        ),
      ],
      overrides: [
        _override(
          routineId: 'sport',
          sourceDateIso: '2026-08-04',
          type: RoutineOccurrenceOverrideType.cancelled,
        ),
      ],
    );

    expect(output.occurrences.map((item) => item.dateIso), ['2026-08-11']);
  });

  test('replaced occurrence disappears while the following one remains', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 3),
      windowEndDateExclusive: DateTime.utc(2026, 8, 18),
      routines: [
        _routine(
          id: 'sport',
          recurrenceType: RoutineRecurrenceType.weekly,
          days: const [DateTime.tuesday],
        ),
      ],
      overrides: [
        _override(
          routineId: 'sport',
          sourceDateIso: '2026-08-04',
          type: RoutineOccurrenceOverrideType.replaced,
          replacementEntityId: 'event-important',
        ),
      ],
    );

    expect(output.occurrences.map((item) => item.dateIso), ['2026-08-11']);
  });

  test('labelled replacement is visible only on the selected occurrence', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 3),
      windowEndDateExclusive: DateTime.utc(2026, 8, 18),
      routines: [
        _routine(
          id: 'sport',
          recurrenceType: RoutineRecurrenceType.weekly,
          days: const [DateTime.tuesday],
        ),
      ],
      overrides: [
        _override(
          routineId: 'sport',
          sourceDateIso: '2026-08-04',
          type: RoutineOccurrenceOverrideType.replaced,
          replacementLabel: 'Dentiste',
        ),
      ],
    );

    expect(output.occurrences, hasLength(2));
    expect(output.occurrences.first.dateIso, '2026-08-04');
    expect(output.occurrences.first.titleOverride, 'Dentiste');
    expect(output.occurrences.last.dateIso, '2026-08-11');
    expect(output.occurrences.last.titleOverride, isNull);
  });

  test('moves one occurrence even when its source is outside the window', () {
    final output = engine.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 5),
      windowEndDateExclusive: DateTime.utc(2026, 8, 7),
      routines: [
        _routine(
          id: 'sport',
          recurrenceType: RoutineRecurrenceType.weekly,
          days: const [DateTime.tuesday],
        ),
      ],
      overrides: [
        _override(
          routineId: 'sport',
          sourceDateIso: '2026-08-04',
          type: RoutineOccurrenceOverrideType.moved,
          replacementDateIso: '2026-08-06',
          replacementStartTime: '18:30',
        ),
      ],
    );

    final occurrence = output.occurrences.single;
    expect(occurrence.occurrenceId, 'sport:2026-08-04');
    expect(occurrence.originalDateIso, '2026-08-04');
    expect(occurrence.dateIso, '2026-08-06');
    expect(occurrence.startTime, '18:30');
    expect(occurrence.isMoved, isTrue);
  });

  test('fails closed when two moved occurrences land on the same routine day',
      () {
    final routine = _routine(
      id: 'sport',
      recurrenceType: RoutineRecurrenceType.weekly,
      days: const [DateTime.tuesday, DateTime.thursday],
    );
    expect(
      () => engine.project(
        accountScopeId: 'account-a',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 10),
        routines: [routine],
        overrides: [
          _override(
            routineId: 'sport',
            sourceDateIso: '2026-08-04',
            type: RoutineOccurrenceOverrideType.moved,
            replacementDateIso: '2026-08-06',
            replacementStartTime: '18:30',
          ),
        ],
      ),
      throwsA(
        isA<RoutineOccurrenceException>().having(
          (error) => error.code,
          'code',
          'routine_override_destination_conflict',
        ),
      ),
    );
  });

  test('fails closed for another-account or duplicate occurrence overrides',
      () {
    final routine = _routine(
      id: 'sport',
      recurrenceType: RoutineRecurrenceType.weekly,
      days: const [DateTime.tuesday],
    );
    final first = _override(
      routineId: 'sport',
      sourceDateIso: '2026-08-04',
      type: RoutineOccurrenceOverrideType.cancelled,
    );
    expect(
      () => engine.project(
        accountScopeId: 'account-a',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 10),
        routines: [routine],
        overrides: [first, first],
      ),
      throwsA(isA<RoutineOccurrenceException>()),
    );
    expect(
      () => engine.project(
        accountScopeId: 'account-a',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 10),
        routines: [routine],
        overrides: [
          _override(
            routineId: 'sport',
            sourceDateIso: '2026-08-04',
            type: RoutineOccurrenceOverrideType.cancelled,
            accountScopeId: 'account-b',
          ),
        ],
      ),
      throwsA(isA<RoutineOccurrenceException>()),
    );
  });

  test('rejects unbounded windows', () {
    expect(
      () => engine.project(
        accountScopeId: 'account-a',
        windowStartDate: DateTime.utc(2026, 1, 1),
        windowEndDateExclusive: DateTime.utc(2027, 1, 3),
        routines: const [],
      ),
      throwsA(isA<RoutineOccurrenceException>()),
    );
  });

  test('projection contract rejects impossible and out-of-window dates', () {
    expect(
      () => RoutineOccurrence(
        occurrenceId: 'routine:invalid',
        routineId: 'routine',
        accountScopeId: 'account-a',
        dateIso: '2026-02-31',
        startTime: '09:00',
        durationMinutes: 60,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
        sourceUpdatedAt: DateTime.utc(2026, 2, 1),
      ),
      throwsA(isA<RoutineOccurrenceException>()),
    );
  });
}

RoutineModel _routine({
  required String id,
  required RoutineRecurrenceType recurrenceType,
  required List<int> days,
  String startTime = '10:00',
  String? anchorDateIso,
  int? weekOfMonth,
  RoutineStatus status = RoutineStatus.active,
}) =>
    RoutineModel(
      id: id,
      accountScopeId: 'account-a',
      logicalRequestId: 'request-$id',
      title: 'Routine',
      recurrenceType: recurrenceType,
      days: days,
      startTime: startTime,
      durationMinutes: 60,
      anchorDateIso: anchorDateIso,
      weekOfMonth: weekOfMonth,
      travelGoMinutes: 10,
      travelBackMinutes: 5,
      marginMinutes: 5,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 2),
      status: status,
    );

RoutineOccurrenceOverride _override({
  required String routineId,
  required String sourceDateIso,
  required RoutineOccurrenceOverrideType type,
  String accountScopeId = 'account-a',
  String? replacementDateIso,
  String? replacementStartTime,
  String? replacementEntityId,
  String? replacementLabel,
}) =>
    RoutineOccurrenceOverride(
      overrideId: '$routineId-$sourceDateIso',
      accountScopeId: accountScopeId,
      routineId: routineId,
      sourceDateIso: sourceDateIso,
      type: type,
      replacementDateIso: replacementDateIso,
      replacementStartTime: replacementStartTime,
      replacementEntityId: replacementEntityId,
      replacementLabel: replacementLabel,
      overrideRevision: 1,
      lastMutationId: 'mutation-$routineId-$sourceDateIso',
      createdAt: DateTime.utc(2026, 8, 2),
      updatedAt: DateTime.utc(2026, 8, 2),
    );
