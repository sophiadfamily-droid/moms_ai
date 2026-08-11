import '../models/event_model.dart';
import '../models/user_profile.dart';
import 'event_service.dart';
import 'routine/routine_planning_blocker_service.dart';

typedef ExistingEventConflictLoader = Future<EventModel?> Function({
  required EventModel candidate,
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
}
