import 'dart:collection';

import '../../models/chat_backend_request.dart';
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
}

final class PlanningProjectionRoutine {
  const PlanningProjectionRoutine({
    required this.id,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.travelMinutes,
  });

  final String id;
  final List<String> days;
  final String? startTime;
  final String? endTime;
  final int? travelMinutes;
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
              days: (facts[LifeContextProjectionFactKeys.days] ?? '')
                  .split(',')
                  .where((day) => day.isNotEmpty)
                  .toList(growable: false),
              startTime: facts[LifeContextProjectionFactKeys.startTime],
              endTime: facts[LifeContextProjectionFactKeys.endTime],
              travelMinutes: int.tryParse(
                facts[LifeContextProjectionFactKeys.travelMinutes] ?? '',
              ),
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
