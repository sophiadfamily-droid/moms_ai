import '../models/agenda_conflict_move_suggestion.dart';
import '../models/event_model.dart';
import 'event_service.dart';
import 'planning_proposal_engine.dart';
import 'routine/routine_agenda_service.dart';
import 'routine/routine_planning_blocker_service.dart';

final class AgendaConflictSuggestionService {
  AgendaConflictSuggestionService({
    Future<List<EventModel>> Function()? loadEvents,
    RoutineAgendaService? routineAgendaService,
    DateTime Function()? clock,
  })  : _loadEvents = loadEvents ?? EventService.getEvents,
        _routineAgendaService =
            routineAgendaService ?? RoutineAgendaService.production(),
        _clock = clock ?? DateTime.now;

  final Future<List<EventModel>> Function() _loadEvents;
  final RoutineAgendaService _routineAgendaService;
  final DateTime Function() _clock;

  Future<AgendaConflictMoveSuggestion?> suggest({
    required String accountScopeId,
    required String eventId,
  }) async {
    if (accountScopeId.trim().isEmpty || accountScopeId == 'guest') return null;
    final events = await _loadEvents();
    final target = events.where((event) => event.id == eventId).firstOrNull;
    if (target == null) return null;
    final now = _clock();
    if (!(EventService.parseProtectedEnd(target)?.isAfter(now) ?? false)) {
      return null;
    }
    final blocked = events.where((event) => event.id != eventId).toList();
    final routineBlockers = await RoutinePlanningBlockerService(
      routineAgendaService: _routineAgendaService,
    ).load(
      accountScopeId: accountScopeId,
      startDay: now,
      days: 7,
    );
    blocked.addAll(routineBlockers);
    final duration = target.durationMinutes > 0 ? target.durationMinutes : 60;
    final protectedMinutes = target.resolvedTravelGoMinutes +
        duration +
        target.resolvedTravelBackMinutes +
        target.marginMinutes;
    final result = PlanningProposalEngine.findBestOptionsFromEvents(
      startDate: now,
      totalMinutes: protectedMinutes,
      events: blocked,
      reasoning: const [],
      searchDays: 7,
      maxOptions: 3,
    );
    final option =
        result.options.where((item) => item.start.isAfter(now)).firstOrNull;
    if (option == null) return null;
    final appointmentStart = option.start.add(
      Duration(minutes: target.resolvedTravelGoMinutes),
    );
    return AgendaConflictMoveSuggestion(
      eventId: eventId,
      eventTitle: target.title,
      dateIso: _dateIso(appointmentStart),
      time: _time(appointmentStart),
      label: option.label,
    );
  }

  static String _dateIso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
