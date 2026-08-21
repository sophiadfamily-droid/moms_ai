import '../models/task_model.dart';
import '../models/event_model.dart';
import 'smart_planning_service.dart';

class PlanningProposalService {
  static Future<SmartPlanningProposal> buildFromDurationPlanning({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required List<EventModel> contextEvents,
    List<Map<String, dynamic>> memoryReasoning = const [],
  }) async {
    return SmartPlanningService.buildProposal(
      task: task,
      originalMessage: originalMessage,
      actionMinutesOverride: actionMinutes,
      memoryReasoning: memoryReasoning,
      contextEvents: contextEvents,
    );
  }

  static Future<SmartPlanningProposal> buildFromTravelPlanning({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required List<TaskModel> groupedTasks,
    required List<EventModel> contextEvents,
    List<Map<String, dynamic>> memoryReasoning = const [],
  }) async {
    if (groupedTasks.length > 1) {
      return SmartPlanningService.buildGroupedProposal(
        mainTask: task,
        originalMessage: originalMessage,
        groupedTasks: groupedTasks,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        actionMinutesOverride: actionMinutes > 0 ? actionMinutes : null,
        memoryReasoning: memoryReasoning,
        contextEvents: contextEvents,
      );
    }

    return SmartPlanningService.buildProposal(
      task: task,
      originalMessage: originalMessage,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      actionMinutesOverride: actionMinutes > 0 ? actionMinutes : null,
      memoryReasoning: memoryReasoning,
      contextEvents: contextEvents,
    );
  }
}
