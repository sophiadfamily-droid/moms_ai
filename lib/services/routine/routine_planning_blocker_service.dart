import '../../models/event_model.dart';
import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/user_profile.dart';
import '../life_context/life_context_projection_compatibility.dart';
import '../life_context_production_factory.dart';
import '../profile_reasoning_service.dart';
import '../recurrence_date_match_service.dart';
import 'routine_agenda_service.dart';

typedef RoutinePlanningContextLoader = Future<PlanningProjectionContext>
    Function(String accountScopeId);
typedef RoutinePlanningProjectionLoader = Future<LifeContextProjection>
    Function(String accountScopeId);

/// Converts canonical routine occurrences into read-only planning blockers.
/// The synthetic Events are used only by conflict validation and are never
/// persisted.
final class RoutinePlanningBlockerService {
  const RoutinePlanningBlockerService({
    RoutineAgendaService? routineAgendaService,
    RoutinePlanningContextLoader? loadPlanningContext,
    RoutinePlanningProjectionLoader? loadPlanningProjection,
  })  : assert(
          routineAgendaService != null ||
              loadPlanningContext != null ||
              loadPlanningProjection != null,
          'A planning source is required.',
        ),
        _routineAgendaService = routineAgendaService,
        _loadPlanningContext = loadPlanningContext,
        _loadPlanningProjection = loadPlanningProjection;

  factory RoutinePlanningBlockerService.production() =>
      RoutinePlanningBlockerService(
        loadPlanningProjection: (accountScopeId) async {
          final production = await LifeContextProductionFactory.production();
          return production.getCurrentProjection(
            LifeContextConsumerPurpose.planning,
          );
        },
      );

  factory RoutinePlanningBlockerService.fromProfile(
    UserProfile Function() currentProfile,
  ) =>
      RoutinePlanningBlockerService(
        loadPlanningContext: (_) async =>
            _planningContextFromProfile(currentProfile()),
      );

  final RoutineAgendaService? _routineAgendaService;
  final RoutinePlanningContextLoader? _loadPlanningContext;
  final RoutinePlanningProjectionLoader? _loadPlanningProjection;

  Future<List<EventModel>> load({
    required String accountScopeId,
    required DateTime startDay,
    int days = 1,
  }) async {
    if (accountScopeId.trim().isEmpty || accountScopeId == 'guest') {
      throw StateError('routine_planning_scope_unavailable');
    }
    final projectionLoader = _loadPlanningProjection;
    final contextLoader = _loadPlanningContext;
    if (projectionLoader != null || contextLoader != null) {
      final context = projectionLoader != null
          ? _planningContextFromProjection(
              projection: await projectionLoader(accountScopeId),
              accountScopeId: accountScopeId,
            )
          : await contextLoader!(accountScopeId);
      return _fromPlanningContext(
        context: context,
        startDay: startDay,
        days: days,
      );
    }
    final routines = await _routineAgendaService!.forWindow(
      accountScopeId: accountScopeId,
      startDay: startDay,
      days: days,
    );
    return routines
        .map(
          (routine) => EventModel(
            id: 'routine:${routine.occurrenceId}',
            title: routine.title,
            date: _dateIso(routine.protectedStart),
            time: _time(routine.protectedStart),
            notes: '',
            category: 'Routine',
            createdAt: routine.protectedStart,
            startDateTimeIso: routine.protectedStart.toIso8601String(),
            endTime: _time(routine.protectedEnd),
            endDateTimeIso: routine.protectedEnd.toIso8601String(),
            durationMinutes: routine.protectedEnd
                .difference(routine.protectedStart)
                .inMinutes,
          ),
        )
        .toList(growable: false);
  }

  static PlanningProjectionContext _planningContextFromProjection({
    required LifeContextProjection projection,
    required String accountScopeId,
  }) {
    if (projection.purpose != LifeContextConsumerPurpose.planning ||
        projection.accountScopeId != accountScopeId) {
      throw StateError('routine_planning_context_unavailable');
    }
    LifeContextProjectionSection? routineSection;
    LifeContextProjectionSection? humanSection;
    for (final section in projection.sections) {
      if (section.type == LifeContextProjectionSectionType.routine) {
        routineSection = section;
      } else if (section.type == LifeContextProjectionSectionType.human) {
        humanSection = section;
      }
    }
    final routineUsable = _sectionIsComplete(routineSection);
    final humanUsable = _sectionIsComplete(humanSection);
    if (!routineUsable && !humanUsable) {
      throw StateError('routine_planning_context_unavailable');
    }
    final context =
        LifeContextPlanningProjectionAdapter.toPlanningContext(projection);
    return PlanningProjectionContext(
      events: context.events,
      routines: routineUsable ? context.routines : const [],
      temporalResponsibilities:
          humanUsable ? context.temporalResponsibilities : const [],
      planningConsequences:
          humanUsable ? context.planningConsequences : const [],
      recurringPlanningConsequences:
          humanUsable ? context.recurringPlanningConsequences : const [],
      warningCodes: context.warningCodes,
      primaryPersonNodeId: humanUsable ? context.primaryPersonNodeId : null,
    );
  }

  static bool _sectionIsComplete(LifeContextProjectionSection? section) =>
      section != null &&
      section.accountScopeMatch &&
      !const {
        LifeContextAvailability.unavailable,
        LifeContextAvailability.corrupted,
        LifeContextAvailability.unsupported,
        LifeContextAvailability.accountMismatch,
      }.contains(section.availability) &&
      !section.truncated &&
      section.sourceTruncationState != LifeContextTruncationState.truncated;

  List<EventModel> _fromPlanningContext({
    required PlanningProjectionContext context,
    required DateTime startDay,
    required int days,
  }) {
    if (days < 1 || days > 31) {
      throw const FormatException('invalid_routine_planning_window');
    }
    final firstDay = DateTime(startDay.year, startDay.month, startDay.day);
    final blockers = <EventModel>[];
    for (var offset = 0; offset < days; offset++) {
      final date = firstDay.add(Duration(days: offset));
      for (final routine in context.routines) {
        if (!_blocksPrimaryUser(routine, context)) continue;
        final blockedPeriod = routine.toBlockedPeriod();
        if (!RecurrenceDateMatchService.appliesToDate(blockedPeriod, date)) {
          continue;
        }
        final start = _onDate(date, routine.startTime);
        final end = _onDate(date, routine.endTime);
        if (start == null || end == null || !end.isAfter(start)) continue;
        final travelBefore =
            int.tryParse('${blockedPeriod['travelBeforeMinutes']}') ?? 0;
        final travelAfter =
            int.tryParse('${blockedPeriod['travelAfterMinutes']}') ?? 0;
        final protectedStart = start.subtract(
          Duration(minutes: travelBefore),
        );
        final protectedEnd = end.add(Duration(minutes: travelAfter));
        blockers.add(
          EventModel(
            id: 'routine:${routine.id}:${_dateIso(date)}',
            title: _titleFor(
              routine.routineKind,
              label: routine.label,
            ),
            date: _dateIso(protectedStart),
            time: _time(protectedStart),
            notes: '',
            category: 'Routine',
            createdAt: protectedStart,
            startDateTimeIso: protectedStart.toIso8601String(),
            endTime: _time(protectedEnd),
            endDateTimeIso: protectedEnd.toIso8601String(),
            durationMinutes: protectedEnd.difference(protectedStart).inMinutes,
          ),
        );
      }
      for (final consequence in context.recurringPlanningConsequences) {
        if (consequence.responsiblePersonNodeId !=
                context.primaryPersonNodeId ||
            !consequence.isConcreteBlockingTime ||
            !consequence.appliesOn(date)) {
          continue;
        }
        final start = _onDate(date, consequence.startTime);
        var end = _onDate(date, consequence.endTime);
        if (start == null || end == null) continue;
        if (!end.isAfter(start)) {
          end = end.add(const Duration(days: 1));
        }
        blockers.add(
          EventModel(
            id: 'responsibility:${consequence.id}:${_dateIso(date)}',
            title: _responsibilityTitle(
              consequence.kind,
              label: consequence.label,
            ),
            date: _dateIso(start),
            time: _time(start),
            notes: '',
            category: 'Responsabilité',
            createdAt: start,
            startDateTimeIso: start.toIso8601String(),
            endTime: _time(end),
            endDateTimeIso: end.toIso8601String(),
            durationMinutes: end.difference(start).inMinutes,
          ),
        );
      }
    }
    final windowEnd = firstDay.add(Duration(days: days));
    for (final consequence in context.planningConsequences) {
      if (consequence.responsiblePersonNodeId != context.primaryPersonNodeId ||
          !consequence.isConcreteBlockingTime) {
        continue;
      }
      final rawStart = consequence.parsedStart!;
      final rawEnd = consequence.parsedEnd!;
      final start = rawStart.isUtc ? rawStart.toLocal() : rawStart;
      final end = rawEnd.isUtc ? rawEnd.toLocal() : rawEnd;
      if (!end.isAfter(firstDay) || !start.isBefore(windowEnd)) continue;
      final protectedStart = start.isBefore(firstDay) ? firstDay : start;
      final protectedEnd = end.isAfter(windowEnd) ? windowEnd : end;
      blockers.add(
        EventModel(
          id: 'responsibility:${consequence.id}',
          title: _responsibilityTitle(
            consequence.kind,
            label: consequence.label,
          ),
          date: _dateIso(protectedStart),
          time: _time(protectedStart),
          notes: '',
          category: 'Responsabilité',
          createdAt: protectedStart,
          startDateTimeIso: protectedStart.toIso8601String(),
          endTime: _time(protectedEnd),
          endDateTimeIso: protectedEnd.toIso8601String(),
          durationMinutes: protectedEnd.difference(protectedStart).inMinutes,
        ),
      );
    }
    blockers.sort((left, right) {
      final start = left.startDateTimeIso.compareTo(right.startDateTimeIso);
      return start != 0 ? start : (left.id ?? '').compareTo(right.id ?? '');
    });
    return blockers;
  }

  static DateTime? _onDate(DateTime date, String? time) {
    final parts = time?.trim().split(':') ?? const <String>[];
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
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

  static bool _blocksPrimaryUser(
    PlanningProjectionRoutine routine,
    PlanningProjectionContext context,
  ) {
    final subject = routine.subjectNodeId?.trim();
    final primary = context.primaryPersonNodeId?.trim();
    if (subject != null && subject.isNotEmpty) {
      if (primary == null || primary.isEmpty) {
        return false;
      }
      return subject == primary;
    }

    // Compatibility for legacy projections that predate typed person IDs.
    // These kinds are explicitly another person's schedule; they remain
    // contextual until a separate primary-user consequence is projected.
    return routine.routineKind != 'schoolSchedule' &&
        routine.routineKind != 'childActivity';
  }

  static PlanningProjectionContext _planningContextFromProfile(
    UserProfile profile,
  ) {
    final routines = <PlanningProjectionRoutine>[];
    final reasoning = ProfileReasoningService.buildReasoning(profile);
    for (var index = 0; index < reasoning.length; index++) {
      final period = reasoning[index];
      if (period['type'] != 'blocked_period') continue;
      final start = period['startTime']?.toString().trim();
      final end = period['endTime']?.toString().trim();
      if (start == null || start.isEmpty || end == null || end.isEmpty) {
        continue;
      }
      final sourceType = period['sourceType']?.toString();
      final rawDays = period['days'];
      routines.add(
        PlanningProjectionRoutine(
          id: 'profile:$index',
          routineKind: switch (sourceType) {
            'work' => 'workSchedule',
            'personal_activity' => 'personalActivity',
            'child_school' => 'schoolSchedule',
            'child_activity' => 'childActivity',
            _ => 'routine',
          },
          label: period['label']?.toString().trim(),
          days: rawDays is List
              ? rawDays.map((day) => '$day').toList(growable: false)
              : const [],
          startTime: start,
          endTime: end,
          travelMinutes: int.tryParse('${period['travelMinutes'] ?? ''}'),
          travelGoMinutes:
              int.tryParse('${period['travelBeforeMinutes'] ?? ''}') ?? 0,
          travelBackMinutes:
              int.tryParse('${period['travelAfterMinutes'] ?? ''}') ?? 0,
        ),
      );
    }
    return PlanningProjectionContext(
      events: const [],
      routines: routines,
      temporalResponsibilities: const [],
      warningCodes: const [],
    );
  }

  static String _titleFor(String routineKind, {String? label}) {
    final informativeLabel = label?.trim();
    if (informativeLabel != null && informativeLabel.isNotEmpty) {
      return informativeLabel;
    }
    return switch (routineKind) {
      'workSchedule' => 'Tes horaires de travail',
      'personalActivity' => 'Une de tes activités',
      'schoolSchedule' => 'Un horaire d’école',
      'childActivity' => 'Une activité familiale',
      _ => 'Une routine',
    };
  }

  static String _responsibilityTitle(String kind, {String? label}) {
    final informativeLabel = label?.trim();
    if (informativeLabel != null &&
        informativeLabel.isNotEmpty &&
        informativeLabel != kind) {
      return informativeLabel;
    }
    return switch (kind) {
      'accompaniment' => 'Un accompagnement prévu',
      'transport' => 'Un trajet à assurer',
      'participation' => 'Ta présence est prévue',
      'preparation' => 'Un temps de préparation prévu',
      'waiting' => 'Un temps d’attente prévu',
      'replacement' => 'Un remplacement prévu',
      'care' => 'Un temps de présence prévu',
      'dailyAssistance' => 'Un temps d’aide prévu',
      _ => kind.trim().isEmpty ? 'Une responsabilité prévue' : kind.trim(),
    };
  }

  static String _dateIso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
