import 'dart:collection';

import '../../models/chat_backend_request.dart';
import '../../models/event_model.dart';
import '../../models/life_context/life_context_projection.dart';
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

final class PlanningProjectionContext {
  PlanningProjectionContext({
    required List<PlanningProjectionEvent> events,
    required List<PlanningProjectionRoutine> routines,
    required List<LifeContextProjectionItem> temporalResponsibilities,
    required List<String> warningCodes,
  })  : events = UnmodifiableListView(events),
        routines = UnmodifiableListView(routines),
        temporalResponsibilities =
            UnmodifiableListView(temporalResponsibilities),
        warningCodes = UnmodifiableListView(warningCodes);

  final List<PlanningProjectionEvent> events;
  final List<PlanningProjectionRoutine> routines;
  final List<LifeContextProjectionItem> temporalResponsibilities;
  final List<String> warningCodes;
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
    final routines = <PlanningProjectionRoutine>[];
    final responsibilities = <LifeContextProjectionItem>[];
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
        responsibilities.addAll(
          section.items.where((item) => item.type == 'responsibility'),
        );
      }
    }
    return PlanningProjectionContext(
      events: events,
      routines: routines,
      temporalResponsibilities: responsibilities,
      warningCodes: projection.warningCodes,
    );
  }

  static Map<String, String> _facts(LifeContextProjectionItem item) => {
        for (final fact in item.facts) fact.key: fact.value,
      };
}
