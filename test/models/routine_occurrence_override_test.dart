import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine/routine_occurrence_override.dart';

void main() {
  test('durable occurrence override round-trips without free text', () {
    final override = RoutineOccurrenceOverride(
      overrideId: 'routine-a-2026-08-04',
      accountScopeId: 'account-a',
      routineId: 'routine-a',
      sourceDateIso: '2026-08-04',
      type: RoutineOccurrenceOverrideType.moved,
      replacementDateIso: '2026-08-06',
      replacementStartTime: '18:30',
      overrideRevision: 1,
      lastMutationId: 'mutation-a',
      createdAt: DateTime.utc(2026, 8, 2),
      updatedAt: DateTime.utc(2026, 8, 2),
    );

    final json = override.toJson();
    expect(RoutineOccurrenceOverride.fromJson(json).toJson(), json);
    expect(json, isNot(contains('reason')));
    expect(json, isNot(contains('rawText')));
  });

  test('moved override requires a valid destination date and time', () {
    expect(
      () => RoutineOccurrenceOverride(
        overrideId: 'override-a',
        accountScopeId: 'account-a',
        routineId: 'routine-a',
        sourceDateIso: '2026-08-04',
        type: RoutineOccurrenceOverrideType.moved,
        replacementDateIso: '2026-02-31',
        replacementStartTime: '9h30',
        overrideRevision: 1,
        lastMutationId: 'mutation-a',
        createdAt: DateTime.utc(2026, 8, 2),
        updatedAt: DateTime.utc(2026, 8, 2),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('cancelled override cannot silently contain replacement coordinates',
      () {
    expect(
      () => RoutineOccurrenceOverride(
        overrideId: 'override-a',
        accountScopeId: 'account-a',
        routineId: 'routine-a',
        sourceDateIso: '2026-08-04',
        type: RoutineOccurrenceOverrideType.cancelled,
        replacementDateIso: '2026-08-06',
        replacementStartTime: '18:30',
        overrideRevision: 1,
        lastMutationId: 'mutation-a',
        createdAt: DateTime.utc(2026, 8, 2),
        updatedAt: DateTime.utc(2026, 8, 2),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
