import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine/routine_occurrence_models.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/services/routine/routine_occurrence_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('loads the requested account and projects canonical occurrences',
      () async {
    String? loadedAccount;
    final service = RoutineOccurrenceService(
      loadRoutines: (accountScopeId) async {
        loadedAccount = accountScopeId;
        return [_routine(accountScopeId)];
      },
    );

    final projection = await service.project(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 3),
      windowEndDateExclusive: DateTime.utc(2026, 8, 12),
    );

    expect(loadedAccount, 'account-a');
    expect(
      projection.occurrences.map((item) => item.dateIso),
      ['2026-08-04', '2026-08-11'],
    );
  });

  test('fails closed when loaded routines belong to another account', () async {
    final service = RoutineOccurrenceService(
      loadRoutines: (_) async => [_routine('account-b')],
    );

    await expectLater(
      service.project(
        accountScopeId: 'account-a',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 12),
      ),
      throwsA(
        isA<RoutineOccurrenceException>().having(
          (error) => error.code,
          'code',
          'routine_account_mismatch',
        ),
      ),
    );
  });

  test('rejects an empty account before loading any data', () async {
    var loads = 0;
    final service = RoutineOccurrenceService(
      loadRoutines: (_) async {
        loads++;
        return const [];
      },
    );

    await expectLater(
      service.project(
        accountScopeId: ' ',
        windowStartDate: DateTime.utc(2026, 8, 3),
        windowEndDateExclusive: DateTime.utc(2026, 8, 12),
      ),
      throwsA(isA<RoutineOccurrenceException>()),
    );
    expect(loads, 0);
  });

  test('exposes a zoned protected projection without creating Events',
      () async {
    final service = RoutineOccurrenceService(
      loadRoutines: (_) async => [_routine('account-a')],
    );

    final result = await service.projectZoned(
      accountScopeId: 'account-a',
      windowStartDate: DateTime.utc(2026, 8, 4),
      windowEndDateExclusive: DateTime.utc(2026, 8, 5),
      timezoneId: 'Europe/Paris',
    );

    expect(result.occurrences.single.start, DateTime.utc(2026, 8, 4, 7));
    expect(
      result.occurrences.single.protectedStart,
      DateTime.utc(2026, 8, 4, 6, 50),
    );
    expect(
      result.occurrences.single.protectedEnd,
      DateTime.utc(2026, 8, 4, 8, 10),
    );
  });
}

RoutineModel _routine(String accountScopeId) => RoutineModel(
      id: 'routine-1',
      accountScopeId: accountScopeId,
      logicalRequestId: 'request-1',
      title: 'Sport',
      recurrenceType: RoutineRecurrenceType.weekly,
      days: const [DateTime.tuesday],
      startTime: '09:00',
      durationMinutes: 60,
      travelGoMinutes: 10,
      travelBackMinutes: 5,
      marginMinutes: 5,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 2),
    );
