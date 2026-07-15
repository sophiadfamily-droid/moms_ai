import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/services/selected_slot_schedule_service.dart';

void main() {
  group('SelectedSlotScheduleService', () {
    test('separates protected range from appointment range', () {
      final schedule = SelectedSlotScheduleService.build(
        protectedStart: DateTime(2026, 7, 20, 10),
        durationMinutes: 45,
        travelGoMinutes: 15,
        travelBackMinutes: 30,
        marginMinutes: 10,
      );

      expect(schedule, isNotNull);
      expect(schedule!.protectedStart, DateTime(2026, 7, 20, 10));
      expect(schedule.appointmentStart, DateTime(2026, 7, 20, 10, 15));
      expect(schedule.appointmentEnd, DateTime(2026, 7, 20, 11));
      expect(schedule.protectedEnd, DateTime(2026, 7, 20, 11, 40));
    });

    test('preserves an explicit zero return travel', () {
      final schedule = SelectedSlotScheduleService.build(
        protectedStart: DateTime(2026, 7, 20, 14),
        durationMinutes: 45,
        travelGoMinutes: 15,
        travelBackMinutes: 0,
        marginMinutes: 10,
      );

      expect(schedule, isNotNull);
      expect(schedule!.appointmentStart, DateTime(2026, 7, 20, 14, 15));
      expect(schedule.appointmentEnd, DateTime(2026, 7, 20, 15));
      expect(schedule.protectedEnd, DateTime(2026, 7, 20, 15, 10));
    });

    test('supports an appointment without travel or margin', () {
      final schedule = SelectedSlotScheduleService.build(
        protectedStart: DateTime(2026, 7, 20, 9),
        durationMinutes: 30,
        travelGoMinutes: 0,
        travelBackMinutes: 0,
        marginMinutes: 0,
      );

      expect(schedule, isNotNull);
      expect(schedule!.appointmentStart, DateTime(2026, 7, 20, 9));
      expect(schedule.appointmentEnd, DateTime(2026, 7, 20, 9, 30));
      expect(schedule.protectedEnd, DateTime(2026, 7, 20, 9, 30));
    });

    test('rejects an invalid appointment duration', () {
      final schedule = SelectedSlotScheduleService.build(
        protectedStart: DateTime(2026, 7, 20, 9),
        durationMinutes: 0,
        travelGoMinutes: 15,
        travelBackMinutes: 15,
        marginMinutes: 10,
      );

      expect(schedule, isNull);
    });
  });
}
