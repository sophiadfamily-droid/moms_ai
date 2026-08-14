import '../models/event_model.dart';
import 'event_service.dart';
import 'recurrence_date_match_service.dart';

class PlanningScoreService {
  static int scoreSlot({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
    int? preferredStartHour,
    int? preferredEndHour,
    String location = '',
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

    score += _sameLocationContinuityScore(
      start: start,
      end: end,
      events: events,
      location: location,
    );

    score += _dayComfortScore(start);

    score += _careWindowComfortScore(
      start: start,
      end: end,
      reasoning: reasoning,
    );

    return score.clamp(0, 100);
  }

  static String explainSlot({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required List<Map<String, dynamic>> reasoning,
    int? preferredStartHour,
    int? preferredEndHour,
    String location = '',
  }) {
    if (_fitsComfortablyInsideCareWindow(
      start: start,
      end: end,
      reasoning: reasoning,
    )) {
      return 'Ce moment évite les horaires probables de dépôt ou de récupération.';
    }

    final locationReason = _sameLocationContinuityReason(
      start: start,
      end: end,
      events: events,
      location: location,
    );
    if (locationReason != null) return locationReason;

    if (_matchesPreferredPeriod(
      start: start,
      preferredStartHour: preferredStartHour,
      preferredEndHour: preferredEndHour,
    )) {
      final period = _periodLabel(
        preferredStartHour!,
        preferredEndHour!,
      );
      return 'Ce moment correspond à ta préférence pour $period.';
    }

    final continuityReason = _sameDayContinuityReason(
      start: start,
      end: end,
      events: events,
    );
    if (continuityReason != null) return continuityReason;

    return 'Ce créneau garde tout le temps prévu autour du rendez-vous.';
  }

  static int _sameLocationContinuityScore({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required String location,
  }) {
    final gap = _nearestSameLocationGap(
      start: start,
      end: end,
      events: events,
      location: location,
    );
    if (gap == null) return 0;
    if (gap <= 120) return 20;
    if (gap <= 180) return 10;
    return 0;
  }

  static String? _sameLocationContinuityReason({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required String location,
  }) {
    final gap = _nearestSameLocationGap(
      start: start,
      end: end,
      events: events,
      location: location,
    );
    if (gap == null || gap > 180) return null;
    return 'Ce créneau reste proche d’un autre rendez-vous au même endroit.';
  }

  static int? _nearestSameLocationGap({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
    required String location,
  }) {
    final requested = _normalizedLocation(location);
    if (requested.isEmpty) return null;
    int? nearest;
    for (final event in events) {
      if (_normalizedLocation(event.location) != requested) continue;
      final eventStart = EventService.parseProtectedStart(event);
      final eventEnd = EventService.parseProtectedEnd(event);
      if (eventStart == null || eventEnd == null) continue;
      if (!_isSameCalendarDay(eventStart, start) &&
          !_isSameCalendarDay(eventEnd, start)) {
        continue;
      }
      final gap = _gapBetween(
        candidateStart: start,
        candidateEnd: end,
        eventStart: eventStart,
        eventEnd: eventEnd,
      );
      if (gap < 0) continue;
      if (nearest == null || gap < nearest) nearest = gap;
    }
    return nearest;
  }

  static String _normalizedLocation(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceFirst(RegExp(r'^(?:a|au|aux|chez|la|le|les|l)\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Gives preference to an appointment that fits comfortably inside a
  /// dependent person's structured schedule, while avoiding the moments at
  /// which a hand-off, drop-off or pickup is likely. This is deliberately a
  /// soft score: until a responsibility is confirmed, it must not invent a
  /// hard unavailability for the user.
  static int _careWindowComfortScore({
    required DateTime start,
    required DateTime end,
    required List<Map<String, dynamic>> reasoning,
  }) {
    var bestComfortBonus = 0;
    var strongestTransitionPenalty = 0;

    for (final item in reasoning) {
      if (item['type'] != 'other_person_schedule' ||
          item['planningEffect'] != 'potential_care_transition' ||
          !RecurrenceDateMatchService.appliesToDate(item, start)) {
        continue;
      }

      final rawStart = _dateTimeFromTime(
        start,
        item['startTime']?.toString(),
      );
      final rawEnd = _dateTimeFromTime(
        start,
        item['endTime']?.toString(),
      );
      if (rawStart == null || rawEnd == null || !rawEnd.isAfter(rawStart)) {
        continue;
      }

      final transitionBefore = _transitionMinutes(
        item['transitionBeforeMinutes'],
        minimum: 15,
      );
      final transitionAfter = _transitionMinutes(
        item['transitionAfterMinutes'],
        minimum: 30,
      );
      final comfortableStart = rawStart.add(
        Duration(minutes: transitionBefore),
      );
      final comfortableEnd = rawEnd.subtract(
        Duration(minutes: transitionAfter),
      );

      final fullyInsideComfortWindow =
          !start.isBefore(comfortableStart) && !end.isAfter(comfortableEnd);
      if (fullyInsideComfortWindow &&
          comfortableEnd.isAfter(comfortableStart)) {
        bestComfortBonus = 35;
        continue;
      }

      final overlapsRawWindow =
          start.isBefore(rawEnd) && rawStart.isBefore(end);
      if (overlapsRawWindow) {
        strongestTransitionPenalty = -45;
        continue;
      }

      final minutesAfterEnd = start.difference(rawEnd).inMinutes;
      if (minutesAfterEnd >= 0 && minutesAfterEnd < transitionAfter) {
        strongestTransitionPenalty = -45;
        continue;
      }

      final minutesBeforeStart = rawStart.difference(end).inMinutes;
      if (minutesBeforeStart >= 0 && minutesBeforeStart < transitionBefore) {
        if (strongestTransitionPenalty > -30) {
          strongestTransitionPenalty = -30;
        }
      }
    }

    if (strongestTransitionPenalty < 0) return strongestTransitionPenalty;
    return bestComfortBonus;
  }

  static bool _fitsComfortablyInsideCareWindow({
    required DateTime start,
    required DateTime end,
    required List<Map<String, dynamic>> reasoning,
  }) {
    for (final item in reasoning) {
      if (item['type'] != 'other_person_schedule' ||
          item['planningEffect'] != 'potential_care_transition' ||
          !RecurrenceDateMatchService.appliesToDate(item, start)) {
        continue;
      }

      final rawStart = _dateTimeFromTime(
        start,
        item['startTime']?.toString(),
      );
      final rawEnd = _dateTimeFromTime(
        start,
        item['endTime']?.toString(),
      );
      if (rawStart == null || rawEnd == null || !rawEnd.isAfter(rawStart)) {
        continue;
      }

      final comfortableStart = rawStart.add(
        Duration(
          minutes: _transitionMinutes(
            item['transitionBeforeMinutes'],
            minimum: 15,
          ),
        ),
      );
      final comfortableEnd = rawEnd.subtract(
        Duration(
          minutes: _transitionMinutes(
            item['transitionAfterMinutes'],
            minimum: 30,
          ),
        ),
      );

      if (comfortableEnd.isAfter(comfortableStart) &&
          !start.isBefore(comfortableStart) &&
          !end.isAfter(comfortableEnd)) {
        return true;
      }
    }

    return false;
  }

  static int _transitionMinutes(dynamic value, {required int minimum}) {
    final parsed = int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed > minimum ? parsed : minimum;
  }

  static DateTime? _dateTimeFromTime(DateTime date, String? value) {
    final clean = value?.trim().toLowerCase().replaceAll('h', ':') ?? '';
    if (!RegExp(r'^\d{1,2}(:\d{1,2})?$').hasMatch(clean)) return null;
    final parts = clean.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
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

  static bool _matchesPreferredPeriod({
    required DateTime start,
    int? preferredStartHour,
    int? preferredEndHour,
  }) {
    if (preferredStartHour == null || preferredEndHour == null) return false;
    return start.hour >= preferredStartHour && start.hour < preferredEndHour;
  }

  static String _periodLabel(int startHour, int endHour) {
    if (endHour <= 12) return 'le matin';
    if (startHour >= 18) return 'le soir';
    return 'l’après-midi';
  }

  static String? _sameDayContinuityReason({
    required DateTime start,
    required DateTime end,
    required List<EventModel> events,
  }) {
    DateTime? previousEnd;
    DateTime? nextStart;

    for (final event in events) {
      final protectedStart = EventService.parseProtectedStart(event);
      final protectedEnd = EventService.parseProtectedEnd(event);
      if (protectedStart == null || protectedEnd == null) continue;
      if (!_isSameCalendarDay(protectedStart, start) &&
          !_isSameCalendarDay(protectedEnd, start)) {
        continue;
      }

      if (!protectedEnd.isAfter(start) &&
          (previousEnd == null || protectedEnd.isAfter(previousEnd))) {
        previousEnd = protectedEnd;
      }
      if (!protectedStart.isBefore(end) &&
          (nextStart == null || protectedStart.isBefore(nextStart))) {
        nextStart = protectedStart;
      }
    }

    final before =
        previousEnd == null ? null : start.difference(previousEnd).inMinutes;
    final after = nextStart?.difference(end).inMinutes;
    final comfortableBefore = before != null && before >= 30 && before <= 120;
    final comfortableAfter = after != null && after >= 30 && after <= 120;

    if (comfortableBefore && comfortableAfter) {
      return 'Ce créneau s’intègre entre deux engagements sans les coller.';
    }
    if (comfortableBefore || comfortableAfter) {
      return 'Ce créneau reste proche d’un autre engagement tout en gardant une marge.';
    }
    return null;
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
