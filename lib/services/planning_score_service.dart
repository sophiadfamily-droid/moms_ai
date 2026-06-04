import '../models/event_model.dart';

class PlanningScoreService {
  static int scoreSlot({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
    int? preferredStartHour,
    int? preferredEndHour,
  }) {
    var score = 50;

    score += _preferredPeriodScore(
      start: start,
      preferredStartHour: preferredStartHour,
      preferredEndHour: preferredEndHour,
    );

    score += _spacingScore(
      start: start,
      end: end,
      events: events,
    );

    score += _dayComfortScore(start);

    return score.clamp(0, 100);
  }

  static int _preferredPeriodScore({
    required DateTime start,
    int? preferredStartHour,
    int? preferredEndHour,
  }) {
    if (preferredStartHour == null || preferredEndHour == null) {
      return 0;
    }

    if (start.hour >= preferredStartHour && start.hour < preferredEndHour) {
      return 25;
    }

    return -10;
  }

  static int _spacingScore({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
  }) {
    if (events.isEmpty) return 10;

    var score = 10;

    for (final event in events) {
      final eventStart = _safeParseDateTime(event.startDateTimeIso);
      final eventEnd = _safeParseDateTime(event.endDateTimeIso);

      if (eventStart == null || eventEnd == null) continue;

      final minutesBefore = start.difference(eventEnd).inMinutes.abs();
      final minutesAfter = eventStart.difference(end).inMinutes.abs();

      if (minutesBefore < 30 || minutesAfter < 30) {
        score -= 10;
      }

      if ((minutesBefore >= 30 && minutesBefore <= 120) ||
          (minutesAfter >= 30 && minutesAfter <= 120)) {
        score += 5;
      }
    }

    return score.clamp(-20, 15);
  }

  static int _dayComfortScore(DateTime start) {
    if (start.hour >= 13 && start.hour <= 16) return 10;
    if (start.hour >= 10 && start.hour < 12) return 5;
    if (start.hour < 9) return -20;
    if (start.hour >= 17) return -10;

    return 0;
  }

  static DateTime? _safeParseDateTime(String value) {
    if (value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
