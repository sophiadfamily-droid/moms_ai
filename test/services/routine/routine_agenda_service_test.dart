import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/routine_model.dart';
import 'package:moms_ai/services/routine/routine_agenda_service.dart';

void main() {
  RoutineModel routine({
    required String account,
    RoutineStatus status = RoutineStatus.active,
  }) =>
      RoutineModel(
        id: 'routine-1',
        accountScopeId: account,
        logicalRequestId: 'request-1',
        title: 'Préparer les enfants',
        recurrenceType: RoutineRecurrenceType.weekly,
        days: const [3],
        startTime: '07:30',
        durationMinutes: 45,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        status: status,
      );

  test('shows a named read-only projection on the requested day', () async {
    final service = RoutineAgendaService(
      loadRoutines: (_) async => [routine(account: 'account-a')],
    );

    final items = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 5),
    );

    expect(items, hasLength(1));
    expect(items.single.title, 'Préparer les enfants');
    expect(items.single.dateIso, '2026-08-05');
    expect(items.single.startTime, '07:30');
    expect(items.single.endTime, '08:15');
    expect(items.single.protectedStart, DateTime(2026, 8, 5, 7, 30));
    expect(items.single.protectedEnd, DateTime(2026, 8, 5, 8, 15));
  });

  test('does not show a cancelled routine', () async {
    final service = RoutineAgendaService(
      loadRoutines: (_) async => [
        routine(account: 'account-a', status: RoutineStatus.cancelled),
      ],
    );

    final items = await service.forDay(
      accountScopeId: 'account-a',
      day: DateTime(2026, 8, 5),
    );

    expect(items, isEmpty);
  });

  test('guest agenda does not query the routine repository', () async {
    var queried = false;
    final service = RoutineAgendaService(loadRoutines: (_) async {
      queried = true;
      return const [];
    });

    expect(
      await service.forDay(
        accountScopeId: 'guest',
        day: DateTime(2026, 8, 5),
      ),
      isEmpty,
    );
    expect(queried, isFalse);
  });
}
