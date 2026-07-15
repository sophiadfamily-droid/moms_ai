class SelectedSlotSchedule {
  final DateTime protectedStart;
  final DateTime appointmentStart;
  final DateTime appointmentEnd;
  final DateTime protectedEnd;

  const SelectedSlotSchedule({
    required this.protectedStart,
    required this.appointmentStart,
    required this.appointmentEnd,
    required this.protectedEnd,
  });
}

class SelectedSlotScheduleService {
  static SelectedSlotSchedule? build({
    required DateTime? protectedStart,
    required int durationMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required int marginMinutes,
  }) {
    if (protectedStart == null || durationMinutes <= 0) {
      return null;
    }

    final safeTravelGo = travelGoMinutes < 0 ? 0 : travelGoMinutes;
    final safeTravelBack = travelBackMinutes < 0 ? 0 : travelBackMinutes;
    final safeMargin = marginMinutes < 0 ? 0 : marginMinutes;

    final appointmentStart = protectedStart.add(
      Duration(minutes: safeTravelGo),
    );

    final appointmentEnd = appointmentStart.add(
      Duration(minutes: durationMinutes),
    );

    final protectedEnd = appointmentEnd.add(
      Duration(minutes: safeTravelBack + safeMargin),
    );

    return SelectedSlotSchedule(
      protectedStart: protectedStart,
      appointmentStart: appointmentStart,
      appointmentEnd: appointmentEnd,
      protectedEnd: protectedEnd,
    );
  }
}
