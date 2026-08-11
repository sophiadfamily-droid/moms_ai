import '../models/event_model.dart';
import '../models/user_profile.dart';
import 'event_service.dart';
import 'routine/routine_planning_blocker_service.dart';

typedef ExistingEventConflictLoader = Future<EventModel?> Function({
  required EventModel candidate,
});

typedef EventStartAlternativeSuggester = Future<DateTime?> Function({
  required String startDateTimeIso,
  required EventModel conflict,
});

typedef EventAlternativeSuggester = Future<DateTime?> Function({
  required EventModel candidate,
  required EventModel conflict,
});

/// Checks a proposed Event against both persisted Events and the recurring
/// constraints projected from the canonical Life Context.
final class EventPlanningConflictService {
  EventPlanningConflictService({
    required ExistingEventConflictLoader loadEventConflict,
    required RoutinePlanningBlockerService routinePlanningBlockers,
    required String? Function() currentAccountScopeId,
    RoutinePlanningBlockerService? profilePlanningBlockers,
  })  : _loadEventConflict = loadEventConflict,
        _routinePlanningBlockers = routinePlanningBlockers,
        _profilePlanningBlockers = profilePlanningBlockers,
        _currentAccountScopeId = currentAccountScopeId;

  factory EventPlanningConflictService.production({
    required String? Function() currentAccountScopeId,
    required UserProfile Function() currentProfile,
  }) =>
      EventPlanningConflictService(
        loadEventConflict: EventService.getOverlapConflict,
        routinePlanningBlockers: RoutinePlanningBlockerService.production(),
        profilePlanningBlockers:
            RoutinePlanningBlockerService.fromProfile(currentProfile),
        currentAccountScopeId: currentAccountScopeId,
      );

  final ExistingEventConflictLoader _loadEventConflict;
  final RoutinePlanningBlockerService _routinePlanningBlockers;
  final RoutinePlanningBlockerService? _profilePlanningBlockers;
  final String? Function() _currentAccountScopeId;

  static Future<EventModel?> findExistingConflictAtStart({
    required String startDateTimeIso,
    required ExistingEventConflictLoader loadEventConflict,
  }) async {
    final candidate = _candidateAtStart(startDateTimeIso);
    if (candidate == null) return null;
    return loadEventConflict(candidate: candidate);
  }

  Future<EventModel?> findConflictAtStart({
    required String startDateTimeIso,
  }) async {
    final candidate = _candidateAtStart(startDateTimeIso);
    if (candidate == null) return null;
    return findConflict(candidate: candidate);
  }

  /// Suggests the first free start after the blocking item, on the same day.
  ///
  /// The Event duration is deliberately not guessed here. The conversation
  /// revalidates the complete protected range once duration and travel are
  /// known.
  Future<DateTime?> suggestAlternativeAtStart({
    required String startDateTimeIso,
    required EventModel conflict,
  }) async {
    final requestedStart = DateTime.tryParse(startDateTimeIso);
    final conflictEnd = EventService.parseProtectedEnd(conflict);
    if (requestedStart == null || conflictEnd == null) return null;

    var cursor = conflictEnd.isAfter(requestedStart)
        ? conflictEnd
        : requestedStart.add(const Duration(minutes: 15));
    cursor = _ceilToQuarterHour(cursor);
    final requestedDay = DateTime(
      requestedStart.year,
      requestedStart.month,
      requestedStart.day,
    );

    for (var attempt = 0; attempt < 96; attempt++) {
      final cursorDay = DateTime(cursor.year, cursor.month, cursor.day);
      if (cursorDay != requestedDay) return null;
      final nextConflict = await findConflictAtStart(
        startDateTimeIso: cursor.toIso8601String(),
      );
      if (nextConflict == null) return cursor;
      final nextEnd = EventService.parseProtectedEnd(nextConflict);
      final fallback = cursor.add(const Duration(minutes: 15));
      cursor = _ceilToQuarterHour(
        nextEnd != null && nextEnd.isAfter(fallback) ? nextEnd : fallback,
      );
    }
    return null;
  }

  /// Suggests a start whose complete protected range is free.
  Future<DateTime?> suggestAlternative({
    required EventModel candidate,
    required EventModel conflict,
  }) async {
    final appointmentStart = EventService.parseStart(candidate);
    final protectedStart = EventService.parseProtectedStart(candidate);
    final protectedEnd = EventService.parseProtectedEnd(candidate);
    final conflictEnd = EventService.parseProtectedEnd(conflict);
    if (appointmentStart == null ||
        protectedStart == null ||
        protectedEnd == null ||
        conflictEnd == null ||
        !protectedEnd.isAfter(protectedStart)) {
      return null;
    }

    final travelBefore = appointmentStart.difference(protectedStart);
    var nextProtectedStart = _ceilToQuarterHour(conflictEnd);
    final requestedDay = DateTime(
      appointmentStart.year,
      appointmentStart.month,
      appointmentStart.day,
    );

    for (var attempt = 0; attempt < 96; attempt++) {
      final nextAppointmentStart = nextProtectedStart.add(travelBefore);
      final nextDay = DateTime(
        nextAppointmentStart.year,
        nextAppointmentStart.month,
        nextAppointmentStart.day,
      );
      if (nextDay != requestedDay) return null;
      final shifted = _moveCandidate(candidate, nextAppointmentStart);
      final nextConflict = await findConflict(candidate: shifted);
      if (nextConflict == null) return nextAppointmentStart;
      final nextConflictEnd = EventService.parseProtectedEnd(nextConflict);
      final fallback = nextProtectedStart.add(const Duration(minutes: 15));
      nextProtectedStart = _ceilToQuarterHour(
        nextConflictEnd != null && nextConflictEnd.isAfter(fallback)
            ? nextConflictEnd
            : fallback,
      );
    }
    return null;
  }

  Future<EventModel?> findConflict({required EventModel candidate}) async {
    EventModel? eventConflict;
    try {
      eventConflict = await _loadEventConflict(candidate: candidate);
    } on Object {
      eventConflict = null;
    }
    if (eventConflict != null) return eventConflict;

    final scope = _currentAccountScopeId()?.trim();
    final start = EventService.parseStart(candidate);
    if (scope == null || scope.isEmpty || scope == 'guest' || start == null) {
      return null;
    }
    final profileSource = _profilePlanningBlockers;
    if (profileSource != null) {
      try {
        final conflict = _firstOverlap(
          await profileSource.load(
            accountScopeId: scope,
            startDay: start,
          ),
          candidate,
        );
        if (conflict != null) return conflict;
      } on Object {
        // One unavailable read source must never break the conversation.
      }
    }
    try {
      return _firstOverlap(
        await _routinePlanningBlockers.load(
          accountScopeId: scope,
          startDay: start,
        ),
        candidate,
      );
    } on Object {
      return null;
    }
  }

  static EventModel? _firstOverlap(
    List<EventModel> blockers,
    EventModel candidate,
  ) =>
      blockers
          .where(
            (blocker) =>
                EventService.eventsProtectedOverlap(blocker, candidate),
          )
          .firstOrNull;

  static EventModel? _candidateAtStart(String startDateTimeIso) {
    final start = DateTime.tryParse(startDateTimeIso);
    if (start == null) return null;
    final end = start.add(const Duration(minutes: 1));
    return EventModel(
      title: 'Créneau demandé',
      date: EventService.formatIsoDate(start),
      time: EventService.formatIsoTime(start),
      notes: '',
      category: 'Planning',
      createdAt: start,
      startDateTimeIso: start.toIso8601String(),
      endTime: EventService.formatIsoTime(end),
      endDateTimeIso: end.toIso8601String(),
      durationMinutes: 1,
    );
  }

  static EventModel _moveCandidate(
    EventModel candidate,
    DateTime appointmentStart,
  ) {
    final appointmentEnd = appointmentStart.add(
      Duration(minutes: candidate.durationMinutes),
    );
    return candidate.copyWith(
      date: EventService.formatIsoDate(appointmentStart),
      time: EventService.formatIsoTime(appointmentStart),
      startDateTimeIso: appointmentStart.toIso8601String(),
      endTime: EventService.formatIsoTime(appointmentEnd),
      endDateTimeIso: appointmentEnd.toIso8601String(),
    );
  }

  static DateTime _ceilToQuarterHour(DateTime value) {
    final remainder = value.minute % 15;
    if (remainder == 0 && value.second == 0 && value.millisecond == 0) {
      return value;
    }
    final minutesToAdd = remainder == 0 ? 15 : 15 - remainder;
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    ).add(Duration(minutes: minutesToAdd));
  }
}
