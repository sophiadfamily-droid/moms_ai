import '../models/event_model.dart';
import 'event_service.dart';

class PlanningScoreService {
  static int scoreSlot({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
    int? preferredStartHour,
    int? preferredEndHour,
  }) {
    if (!end.isAfter(start)) {
      return 0;
    }

    var score = 50;

    score += _preferredPeriodScore(
      start: start,
      preferredStartHour: preferredStartHour,
      preferredEndHour: preferredEndHour,
    );

    score += _sameDayPlanningScore(
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

  static int _sameDayPlanningScore({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
  }) {
    final sameDayRanges = <_ProtectedEventRange>[];

    for (final event in events) {
      final protectedStart = EventService.parseProtectedStart(event);
      final protectedEnd = EventService.parseProtectedEnd(event);

      if (protectedStart == null || protectedEnd == null) {
        continue;
      }

      if (!_isSameCalendarDay(protectedStart, start) &&
          !_isSameCalendarDay(protectedEnd, start)) {
        continue;
      }

      sameDayRanges.add(
        _ProtectedEventRange(
          start: protectedStart,
          end: protectedEnd,
        ),
      );
    }

    if (sameDayRanges.isEmpty) {
      return 5;
    }

    var nearestGapMinutes = 24 * 60;

    for (final range in sameDayRanges) {
      final gap = _gapBetween(
        candidateStart: start,
        candidateEnd: end,
        eventStart: range.start,
        eventEnd: range.end,
      );

      if (gap < nearestGapMinutes) {
        nearestGapMinutes = gap;
      }
    }

    if (nearestGapMinutes < 0) {
      return -40;
    }

    if (nearestGapMinutes < 15) {
      return -15;
    }

    if (nearestGapMinutes < 30) {
      return -5;
    }

    if (nearestGapMinutes <= 120) {
      return 15;
    }

    if (nearestGapMinutes <= 240) {
      return 5;
    }

    return -5;
  }

  static int _gapBetween({
    required DateTime candidateStart,
    required DateTime candidateEnd,
    required DateTime eventStart,
    required DateTime eventEnd,
  }) {
    final overlaps =
        candidateStart.isBefore(eventEnd) && eventStart.isBefore(candidateEnd);

    if (overlaps) {
      return -1;
    }

    if (!candidateStart.isBefore(eventEnd)) {
      return candidateStart.difference(eventEnd).inMinutes;
    }

    return eventStart.difference(candidateEnd).inMinutes;
  }

  static bool _isSameCalendarDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  static int _dayComfortScore(DateTime start) {
    if (start.hour >= 13 && start.hour <= 16) return 10;
    if (start.hour >= 10 && start.hour < 12) return 5;
    if (start.hour < 9) return -20;
    if (start.hour >= 17) return -10;

    return 0;
  }
}

class _ProtectedEventRange {
  final DateTime start;
  final DateTime end;

  const _ProtectedEventRange({
    required this.start,
    required this.end,
  });
}
