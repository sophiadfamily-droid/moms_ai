import '../models/task_model.dart';
import '../models/event_model.dart';
import 'smart_planning_service.dart';

class PlanningProposalService {
  static Future<SmartPlanningProposal> buildFromDurationPlanning({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    List<Map<String, dynamic>> memoryReasoning = const [],
    List<EventModel>? contextEvents,
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
    List<Map<String, dynamic>> memoryReasoning = const [],
    List<EventModel>? contextEvents,
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
