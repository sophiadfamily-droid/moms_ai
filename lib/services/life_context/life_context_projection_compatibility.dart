import 'dart:collection';

import '../../models/chat_backend_request.dart';
import '../../models/event_model.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/task_model.dart';
import '../conversation_context_assembler.dart';

/// Transitional adapter only. It never loads domains and never serializes the
/// LC.1 snapshot or LC.2 graph.
abstract final class LifeContextConversationProjectionAdapter {
  static ChatBackendRequest toChatBackendRequest({
    required String message,
    required LifeContextProjection projection,
  }) {
    if (projection.purpose != LifeContextConsumerPurpose.conversation) {
      throw const LifeContextProjectionException(
        'conversation_projection_required',
      );
    }
    return ChatBackendRequest(
      message: message,
      context: ConversationContextAssembler.assemble(projection),
    );
  }
}

final class PlanningProjectionEvent {
  const PlanningProjectionEvent({
    required this.id,
    required this.start,
    required this.end,
    required this.travelGoMinutes,
    required this.travelBackMinutes,
    required this.marginMinutes,
    required this.recurringType,
    required this.syncStatus,
    required this.revision,
    this.location,
    this.locationEntityId,
  });

  final String id;
  final String start;
  final String end;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final String? recurringType;
  final String syncStatus;
  final int revision;
  final String? location;
  final String? locationEntityId;

  EventModel toEventModel() {
    final parsedStart = DateTime.tryParse(start);
    final parsedEnd = DateTime.tryParse(end);
    if (parsedStart == null ||
        parsedEnd == null ||
        !parsedEnd.isAfter(parsedStart)) {
      throw const LifeContextProjectionException('invalid_planning_event');
    }
    String date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    String time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return EventModel(
      id: id,
      title: 'Contrainte calendrier',
      date: date(parsedStart),
      time: time(parsedStart),
      notes: '',
      category: 'Planning',
      location: location ?? '',
      locationEntityId: locationEntityId,
      createdAt: parsedStart,
      startDateTimeIso: start,
      endTime: time(parsedEnd),
      endDateTimeIso: end,
      durationMinutes: parsedEnd.difference(parsedStart).inMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      usesSeparateTravelTimes: true,
      marginMinutes: marginMinutes,
      isRecurring: recurringType?.isNotEmpty ?? false,
      recurringType: recurringType ?? '',
      eventRevision: revision,
    );
  }
}

final class PlanningProjectionRoutine {
  const PlanningProjectionRoutine({
    required this.id,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.travelMinutes,
    this.routineKind = 'routine',
    this.label,
    this.subjectNodeId,
    this.recurrenceType,
    this.anchorDateIso,
    this.weekOfMonth,
    this.travelGoMinutes = 0,
    this.travelBackMinutes = 0,
    this.marginMinutes = 0,
  });

  final String id;
  final String routineKind;
  final String? label;
  final String? subjectNodeId;
  final List<String> days;
  final String? startTime;
  final String? endTime;
  final int? travelMinutes;
  final String? recurrenceType;
  final String? anchorDateIso;
  final int? weekOfMonth;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;

  /// Planning must not treat another person's timetable as if the primary
  /// user were occupied for the whole period. A school day, for example, is
  /// often a useful availability window for the caregiver; its boundaries
  /// are nevertheless important because a drop-off or pickup may be needed.
  Map<String, dynamic> toPlanningReasoning({
    required String? primaryPersonNodeId,
  }) {
    final mayCreateCareTransitions =
        routineKind == 'schoolSchedule' || routineKind == 'childActivity';

    // These routine kinds are sourced only from another household person's
    // profile. Keep the semantic fallback when an older profile has no linked
    // person id yet: missing migration metadata must not turn a child's whole
    // school day into a hard block for the primary user.
    final belongsToAnotherPerson = subjectNodeId == null ||
        subjectNodeId!.isEmpty ||
        subjectNodeId != primaryPersonNodeId;

    if (mayCreateCareTransitions && belongsToAnotherPerson) {
      return {
        'type': 'other_person_schedule',
        'planningEffect': 'potential_care_transition',
        'routineKind': routineKind,
        if (label != null && label!.trim().isNotEmpty) 'label': label,
        'subjectNodeId': subjectNodeId,
        'recurrenceType': recurrenceType ?? 'weekly',
        'days': days,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        'transitionBeforeMinutes':
            travelGoMinutes > 0 ? travelGoMinutes : travelMinutes ?? 0,
        'transitionAfterMinutes':
            travelBackMinutes > 0 ? travelBackMinutes : travelMinutes ?? 0,
        if (anchorDateIso != null) 'anchorDateIso': anchorDateIso,
        if (weekOfMonth != null) 'weekOfMonth': weekOfMonth,
      };
    }

    return toBlockedPeriod();
  }

  Map<String, dynamic> toBlockedPeriod() => {
        'type': 'blocked_period',
        'recurrenceType': recurrenceType ?? 'weekly',
        'days': days,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        'travelBeforeMinutes':
            travelGoMinutes > 0 ? travelGoMinutes : travelMinutes ?? 0,
        'travelAfterMinutes': travelBackMinutes > 0
            ? travelBackMinutes + marginMinutes
            : (travelMinutes ?? 0) + marginMinutes,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        if (anchorDateIso != null) 'anchorDateIso': anchorDateIso,
        if (weekOfMonth != null) 'weekOfMonth': weekOfMonth,
      };
}

final class PlanningProjectionTask {
  const PlanningProjectionTask({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.syncStatus,
    this.dueDate,
    this.durationMinutes,
    this.importance,
    this.urgency,
    this.category,
    this.createdAt,
  });

  final String id;
  final String title;
  final bool isCompleted;
  final String syncStatus;
  final String? dueDate;
  final int? durationMinutes;
  final double? importance;
  final double? urgency;
  final String? category;
  final String? createdAt;

  TaskModel toTaskModel() => TaskModel(
        id: id,
        title: title,
        category: category?.trim().isNotEmpty == true ? category! : 'Perso',
        isDone: isCompleted,
        createdAt: DateTime.tryParse(createdAt ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isImportant: (importance ?? 0) > 0 || (urgency ?? 0) > 0,
        dueDate: dueDate ?? '',
        durationMinutes: durationMinutes,
        priority: (urgency ?? 0) > 0 ? 'Haute' : 'Normale',
      );
}

/// A confirmed, time-bounded effect of one person's responsibility on the
/// responsible person's own availability.
///
/// Broad responsibilities (parental role, custody, household role, etc.) are
/// deliberately not represented here. Planning only receives a consequence
/// when the responsibility type is explicit and its start/end form one small
/// concrete time range.
final class PlanningProjectionConsequence {
  const PlanningProjectionConsequence({
    required this.id,
    required this.kind,
    this.label,
    required this.responsiblePersonNodeId,
    required this.subjectPersonNodeId,
    required this.start,
    required this.end,
  });

  static const blockingKinds = {
    'accompaniment',
    'transport',
    'participation',
    'preparation',
    'waiting',
    'replacement',
    'care',
    'dailyAssistance',
  };

  final String id;
  final String kind;
  final String? label;
  final String responsiblePersonNodeId;
  final String subjectPersonNodeId;
  final String start;
  final String end;

  DateTime? get parsedStart => DateTime.tryParse(start);
  DateTime? get parsedEnd => DateTime.tryParse(end);
  String get displayLabel => _planningConsequenceLabel(kind, label: label);

  bool get isConcreteBlockingTime {
    final from = parsedStart;
    final until = parsedEnd;
    if (!blockingKinds.contains(kind) ||
        from == null ||
        until == null ||
        !until.isAfter(from)) {
      return false;
    }
    return until.difference(from) <= const Duration(hours: 24);
  }

  EventModel? toBlockingEvent() {
    if (!isConcreteBlockingTime) return null;
    final rawStart = parsedStart!;
    final rawEnd = parsedEnd!;
    final localStart = rawStart.isUtc ? rawStart.toLocal() : rawStart;
    final localEnd = rawEnd.isUtc ? rawEnd.toLocal() : rawEnd;
    return EventModel(
      id: 'responsibility:$id',
      title: displayLabel,
      date: _dateIso(localStart),
      time: _time(localStart),
      notes: '',
      category: 'Responsabilité',
      createdAt: localStart,
      startDateTimeIso: localStart.toIso8601String(),
      endTime: _time(localEnd),
      endDateTimeIso: localEnd.toIso8601String(),
      durationMinutes: localEnd.difference(localStart).inMinutes,
    );
  }
}

/// A confirmed weekly effect of a responsibility on the responsible person's
/// own availability. It is distinct from the other person's schedule and from
/// a one-off dated consequence.
final class PlanningProjectionRecurringConsequence {
  PlanningProjectionRecurringConsequence({
    required this.id,
    required this.kind,
    this.label,
    required this.responsiblePersonNodeId,
    required this.subjectPersonNodeId,
    required List<int> weekdays,
    required this.startTime,
    required this.endTime,
    this.validFrom,
    this.validUntil,
  }) : weekdays = UnmodifiableListView(List<int>.of(weekdays)..sort());

  final String id;
  final String kind;
  final String? label;
  final String responsiblePersonNodeId;
  final String subjectPersonNodeId;
  final List<int> weekdays;
  final String startTime;
  final String endTime;
  final DateTime? validFrom;
  final DateTime? validUntil;
  String get displayLabel => _planningConsequenceLabel(kind, label: label);

  bool get isConcreteBlockingTime {
    final start = _localMinutes(startTime);
    final end = _localMinutes(endTime);
    if (!PlanningProjectionConsequence.blockingKinds.contains(kind) ||
        responsiblePersonNodeId.isEmpty ||
        subjectPersonNodeId.isEmpty ||
        weekdays.isEmpty ||
        weekdays.length > DateTime.daysPerWeek ||
        weekdays.toSet().length != weekdays.length ||
        weekdays.any(
          (weekday) => weekday < DateTime.monday || weekday > DateTime.sunday,
        ) ||
        start == null ||
        end == null ||
        start == end) {
      return false;
    }
    final duration = end > start ? end - start : (24 * 60) - start + end;
    return duration > 0 && duration <= 24 * 60;
  }

  bool appliesOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final from = validFrom == null
        ? null
        : DateTime(validFrom!.year, validFrom!.month, validFrom!.day);
    final until = validUntil == null
        ? null
        : DateTime(validUntil!.year, validUntil!.month, validUntil!.day);
    return weekdays.contains(day.weekday) &&
        (from == null || !day.isBefore(from)) &&
        (until == null || !day.isAfter(until));
  }

  Map<String, dynamic>? toBlockedPeriod() {
    if (!isConcreteBlockingTime) return null;
    return {
      'type': 'blocked_period',
      'sourceType': 'responsibility',
      'label': displayLabel,
      'recurrenceType': 'weekly',
      'days': weekdays.map((weekday) => '$weekday').toList(growable: false),
      'startTime': startTime,
      'endTime': endTime,
      'travelBeforeMinutes': 0,
      'travelAfterMinutes': 0,
      if (validFrom != null) 'validFrom': _dateIso(validFrom!),
      if (validUntil != null) 'validUntil': _dateIso(validUntil!),
    };
  }

  static int? _localMinutes(String value) {
    final parts = value.trim().split(':');
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
    return hour * 60 + minute;
  }
}

String _planningConsequenceLabel(String kind, {String? label}) {
  final informative = label?.trim();
  if (informative != null && informative.isNotEmpty && informative != kind) {
    return informative;
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

String _dateIso(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

final class PlanningProjectionContext {
  PlanningProjectionContext({
    required List<PlanningProjectionEvent> events,
    List<PlanningProjectionTask> tasks = const [],
    required List<PlanningProjectionRoutine> routines,
    required List<LifeContextProjectionItem> temporalResponsibilities,
    required List<String> warningCodes,
    List<PlanningProjectionConsequence> planningConsequences = const [],
    List<PlanningProjectionRecurringConsequence> recurringPlanningConsequences =
        const [],
    this.primaryPersonNodeId,
  })  : events = UnmodifiableListView(events),
        tasks = UnmodifiableListView(tasks),
        routines = UnmodifiableListView(routines),
        temporalResponsibilities =
            UnmodifiableListView(temporalResponsibilities),
        planningConsequences = UnmodifiableListView(planningConsequences),
        recurringPlanningConsequences =
            UnmodifiableListView(recurringPlanningConsequences),
        warningCodes = UnmodifiableListView(warningCodes);

  final List<PlanningProjectionEvent> events;
  final List<PlanningProjectionTask> tasks;
  final List<PlanningProjectionRoutine> routines;
  final List<LifeContextProjectionItem> temporalResponsibilities;
  final List<PlanningProjectionConsequence> planningConsequences;
  final List<PlanningProjectionRecurringConsequence>
      recurringPlanningConsequences;
  final List<String> warningCodes;
  final String? primaryPersonNodeId;
}

/// Typed bridge for existing planning services. It provides facts only and
/// performs no scheduling, scoring, conflict resolution, or Event mutation.
abstract final class LifeContextPlanningProjectionAdapter {
  static PlanningProjectionContext toPlanningContext(
    LifeContextProjection projection,
  ) {
    if (projection.purpose != LifeContextConsumerPurpose.planning) {
      throw const LifeContextProjectionException(
        'planning_projection_required',
      );
    }
    final events = <PlanningProjectionEvent>[];
    final tasks = <PlanningProjectionTask>[];
    final routines = <PlanningProjectionRoutine>[];
    final responsibilities = <LifeContextProjectionItem>[];
    final consequences = <PlanningProjectionConsequence>[];
    final recurringConsequences = <PlanningProjectionRecurringConsequence>[];
    String? primaryPersonNodeId;
    for (final section in projection.sections) {
      if (section.type == LifeContextProjectionSectionType.event) {
        for (final item in section.items) {
          final facts = _facts(item);
          events.add(
            PlanningProjectionEvent(
              id: item.id,
              start: facts[LifeContextProjectionFactKeys.start]!,
              end: facts[LifeContextProjectionFactKeys.end]!,
              travelGoMinutes: int.parse(
                facts[LifeContextProjectionFactKeys.travelGoMinutes]!,
              ),
              travelBackMinutes: int.parse(
                facts[LifeContextProjectionFactKeys.travelBackMinutes]!,
              ),
              marginMinutes: int.parse(
                facts[LifeContextProjectionFactKeys.marginMinutes]!,
              ),
              recurringType: facts[LifeContextProjectionFactKeys.recurringType],
              syncStatus:
                  facts[LifeContextProjectionFactKeys.syncStatus] ?? 'unknown',
              revision: int.parse(
                facts[LifeContextProjectionFactKeys.revision]!,
              ),
              location: facts[LifeContextProjectionFactKeys.location],
              locationEntityId:
                  facts[LifeContextProjectionFactKeys.locationEntityId],
            ),
          );
        }
      } else if (section.type == LifeContextProjectionSectionType.task) {
        for (final item in section.items) {
          final facts = _facts(item);
          tasks.add(
            PlanningProjectionTask(
              id: item.id,
              title: facts[LifeContextProjectionFactKeys.title] ?? '',
              isCompleted:
                  facts[LifeContextProjectionFactKeys.status] == 'completed',
              syncStatus:
                  facts[LifeContextProjectionFactKeys.syncStatus] ?? 'unknown',
              dueDate: facts[LifeContextProjectionFactKeys.dueDate],
              durationMinutes: int.tryParse(
                facts[LifeContextProjectionFactKeys.durationMinutes] ?? '',
              ),
              importance: double.tryParse(
                facts[LifeContextProjectionFactKeys.importance] ?? '',
              ),
              urgency: double.tryParse(
                facts[LifeContextProjectionFactKeys.urgency] ?? '',
              ),
              category: facts[LifeContextProjectionFactKeys.category],
              createdAt: facts[LifeContextProjectionFactKeys.createdAt],
            ),
          );
        }
      } else if (section.type == LifeContextProjectionSectionType.routine) {
        for (final item in section.items) {
          final facts = _facts(item);
          routines.add(
            PlanningProjectionRoutine(
              id: item.id,
              routineKind:
                  facts[LifeContextProjectionFactKeys.routineKind] ?? 'routine',
              label: facts[LifeContextProjectionFactKeys.title],
              subjectNodeId: facts[LifeContextProjectionFactKeys.subjectNodeId],
              days: (facts[LifeContextProjectionFactKeys.days] ?? '')
                  .split(',')
                  .where((day) => day.isNotEmpty)
                  .toList(growable: false),
              startTime: facts[LifeContextProjectionFactKeys.startTime],
              endTime: facts[LifeContextProjectionFactKeys.endTime],
              travelMinutes: int.tryParse(
                facts[LifeContextProjectionFactKeys.travelMinutes] ?? '',
              ),
              recurrenceType:
                  facts[LifeContextProjectionFactKeys.recurringType],
              anchorDateIso: facts[LifeContextProjectionFactKeys.anchorDateIso],
              weekOfMonth: int.tryParse(
                facts[LifeContextProjectionFactKeys.weekOfMonth] ?? '',
              ),
              travelGoMinutes: int.tryParse(
                    facts[LifeContextProjectionFactKeys.travelGoMinutes] ?? '',
                  ) ??
                  0,
              travelBackMinutes: int.tryParse(
                    facts[LifeContextProjectionFactKeys.travelBackMinutes] ??
                        '',
                  ) ??
                  0,
              marginMinutes: int.tryParse(
                    facts[LifeContextProjectionFactKeys.marginMinutes] ?? '',
                  ) ??
                  0,
            ),
          );
        }
      } else if (section.type == LifeContextProjectionSectionType.human) {
        for (final item
            in section.items.where((item) => item.type == 'person')) {
          final facts = _facts(item);
          if (facts[LifeContextProjectionFactKeys.personRole] == 'primary') {
            primaryPersonNodeId = facts[LifeContextProjectionFactKeys.nodeId];
            break;
          }
        }
        responsibilities.addAll(
          section.items.where((item) => item.type == 'responsibility'),
        );
        for (final item
            in section.items.where((item) => item.type == 'responsibility')) {
          final facts = _facts(item);
          if (facts[LifeContextProjectionFactKeys.blocksResponsiblePerson] !=
              'true') {
            continue;
          }
          final kind =
              facts[LifeContextProjectionFactKeys.consequenceType] ?? '';
          final label = facts[LifeContextProjectionFactKeys.kind];
          final responsible =
              facts[LifeContextProjectionFactKeys.sourceNodeId] ?? '';
          final subject =
              facts[LifeContextProjectionFactKeys.targetNodeId] ?? '';
          if (facts[LifeContextProjectionFactKeys.recurringConsequence] ==
              'weekly') {
            final recurring = PlanningProjectionRecurringConsequence(
              id: item.id,
              kind: kind,
              label: label,
              responsiblePersonNodeId: responsible,
              subjectPersonNodeId: subject,
              weekdays: (facts[LifeContextProjectionFactKeys.days] ?? '')
                  .split(',')
                  .map(int.tryParse)
                  .whereType<int>()
                  .toList(growable: false),
              startTime: facts[LifeContextProjectionFactKeys.startTime] ?? '',
              endTime: facts[LifeContextProjectionFactKeys.endTime] ?? '',
              validFrom: item.validFrom,
              validUntil: item.validUntil,
            );
            if (recurring.isConcreteBlockingTime) {
              recurringConsequences.add(recurring);
            }
          } else {
            final consequence = PlanningProjectionConsequence(
              id: item.id,
              kind: kind,
              label: label,
              responsiblePersonNodeId: responsible,
              subjectPersonNodeId: subject,
              start: facts[LifeContextProjectionFactKeys.start] ?? '',
              end: facts[LifeContextProjectionFactKeys.end] ?? '',
            );
            if (consequence.responsiblePersonNodeId.isNotEmpty &&
                consequence.subjectPersonNodeId.isNotEmpty &&
                consequence.isConcreteBlockingTime) {
              consequences.add(consequence);
            }
          }
        }
      }
    }
    return PlanningProjectionContext(
      events: events,
      tasks: tasks,
      routines: routines,
      temporalResponsibilities: responsibilities,
      planningConsequences: consequences,
      recurringPlanningConsequences: recurringConsequences,
      warningCodes: projection.warningCodes,
      primaryPersonNodeId: primaryPersonNodeId,
    );
  }

  static Map<String, String> _facts(LifeContextProjectionItem item) => {
        for (final fact in item.facts) fact.key: fact.value,
      };
}
