import '../models/task_model.dart';
import 'smart_planning_service.dart';

class PlanningProposalService {
  static Future<SmartPlanningProposal> buildFromDurationPlanning({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
  }) async {
    return SmartPlanningService.buildProposal(
      task: task,
      originalMessage: originalMessage,
      actionMinutesOverride: actionMinutes,
    );
  }

  static Future<SmartPlanningProposal> buildFromTravelPlanning({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required List<TaskModel> groupedTasks,
  }) async {
    if (groupedTasks.length > 1) {
      return SmartPlanningService.buildGroupedProposal(
        mainTask: task,
        originalMessage: originalMessage,
        groupedTasks: groupedTasks,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelGoMinutes,
        actionMinutesOverride: actionMinutes > 0 ? actionMinutes : null,
      );
    }

    return SmartPlanningService.buildProposal(
      task: task,
      originalMessage: originalMessage,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelGoMinutes,
      actionMinutesOverride: actionMinutes > 0 ? actionMinutes : null,
    );
  }
}
