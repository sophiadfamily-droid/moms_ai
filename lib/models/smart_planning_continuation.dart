import 'dart:collection';

import '../services/planning_proposal_engine.dart';
import '../services/smart_planning_service.dart';
import 'task_model.dart';
import 'action_autonomy_policy.dart';
import 'action_confirmation.dart';

enum SmartPlanningContinuationType {
  taskPlanning,
  explicitSlotRequest,
  proposalSelection,
  selectedSlot,
  simpleProposal,
  alternativeSearch,
}

enum SmartPlanningContinuationStep {
  planningConsent,
  duration,
  travelGo,
  travelBack,
  optionChoice,
  confirmation,
  alternativeConfirmation,
}

enum SmartPlanningContinuationStatus {
  active,
  completed,
  cancelled,
  expired,
  failed,
}

enum SmartPlanningPolicyState {
  active,
  blockedByPolicy,
  expired,
  completed,
  cancelled,
}

enum SmartPlanningContinuationResultStatus {
  success,
  invalidAnswer,
  clarificationStillRequired,
  confirmationRequired,
  conflict,
  expired,
  cancelled,
  staleContinuation,
  duplicateIntent,
  planningValidationFailure,
  pendingSync,
  recoverableFailure,
  blockingFailure,
}

final class SmartPlanningContinuation {
  static const int currentSchemaVersion = 1;

  SmartPlanningContinuation({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.sessionGeneration,
    required this.type,
    required this.step,
    required this.createdAt,
    required this.expiresAt,
    required this.task,
    required this.originalMessage,
    this.status = SmartPlanningContinuationStatus.active,
    this.taskType = '',
    this.outside = false,
    this.estimatedMinutes = 0,
    this.actionMinutes = 0,
    this.travelGoMinutes = 0,
    this.travelBackMinutes = 0,
    this.marginMinutes = 0,
    this.failedDate,
    this.startDate,
    this.proposal,
    List<TaskModel> groupedTasks = const [],
    List<PlanningProposalOption> options = const [],
    this.selectedOption,
    this.mutationId,
    required this.policyModeAtCreation,
    required this.policyVersionAtCreation,
    this.actionType = ActionType.smartPlanningReservation,
    this.origin = ActionOrigin.structuredContinuation,
    this.riskLevel = ActionRiskLevel.mutation,
    this.policyState = SmartPlanningPolicyState.active,
    this.canonicalConfirmation,
    this.logicalRequestId,
    this.sourceSuggestionId,
  })  : groupedTasks = UnmodifiableListView(groupedTasks),
        options = UnmodifiableListView(options) {
    if (schemaVersion != currentSchemaVersion ||
        id.trim().isEmpty ||
        sessionGeneration < 0 ||
        !expiresAt.isAfter(createdAt) ||
        originalMessage.length > 8000 ||
        estimatedMinutes < 0 ||
        actionMinutes < 0 ||
        travelGoMinutes < 0 ||
        travelBackMinutes < 0 ||
        marginMinutes < 0 ||
        mutationId != null && mutationId!.trim().isEmpty ||
        logicalRequestId != null && logicalRequestId!.trim().isEmpty ||
        sourceSuggestionId != null && sourceSuggestionId!.trim().isEmpty) {
      throw const FormatException('invalid_smart_planning_continuation');
    }
  }

  final int schemaVersion;
  final String id;
  final int sessionGeneration;
  final SmartPlanningContinuationType type;
  final SmartPlanningContinuationStep step;
  final SmartPlanningContinuationStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final TaskModel task;
  final String originalMessage;
  final String taskType;
  final bool outside;
  final int estimatedMinutes;
  final int actionMinutes;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final DateTime? failedDate;
  final DateTime? startDate;
  final SmartPlanningProposal? proposal;
  final List<TaskModel> groupedTasks;
  final List<PlanningProposalOption> options;
  final PlanningProposalOption? selectedOption;
  final String? mutationId;
  final ActionAutonomyMode policyModeAtCreation;
  final int policyVersionAtCreation;
  final ActionType actionType;
  final ActionOrigin origin;
  final ActionRiskLevel riskLevel;
  final SmartPlanningPolicyState policyState;
  final ActionConfirmation? canonicalConfirmation;
  final String? logicalRequestId;
  final String? sourceSuggestionId;

  SmartPlanningContinuation copyWith({
    SmartPlanningContinuationType? type,
    SmartPlanningContinuationStep? step,
    SmartPlanningContinuationStatus? status,
    String? taskType,
    bool? outside,
    int? estimatedMinutes,
    int? actionMinutes,
    int? travelGoMinutes,
    int? travelBackMinutes,
    int? marginMinutes,
    DateTime? failedDate,
    DateTime? startDate,
    SmartPlanningProposal? proposal,
    List<TaskModel>? groupedTasks,
    List<PlanningProposalOption>? options,
    PlanningProposalOption? selectedOption,
    String? mutationId,
    ActionAutonomyMode? policyModeAtCreation,
    int? policyVersionAtCreation,
    SmartPlanningPolicyState? policyState,
    ActionConfirmation? canonicalConfirmation,
    bool clearCanonicalConfirmation = false,
    String? logicalRequestId,
    String? sourceSuggestionId,
  }) =>
      SmartPlanningContinuation(
        id: id,
        sessionGeneration: sessionGeneration,
        type: type ?? this.type,
        step: step ?? this.step,
        status: status ?? this.status,
        createdAt: createdAt,
        expiresAt: expiresAt,
        task: task,
        originalMessage: originalMessage,
        taskType: taskType ?? this.taskType,
        outside: outside ?? this.outside,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        actionMinutes: actionMinutes ?? this.actionMinutes,
        travelGoMinutes: travelGoMinutes ?? this.travelGoMinutes,
        travelBackMinutes: travelBackMinutes ?? this.travelBackMinutes,
        marginMinutes: marginMinutes ?? this.marginMinutes,
        failedDate: failedDate ?? this.failedDate,
        startDate: startDate ?? this.startDate,
        proposal: proposal ?? this.proposal,
        groupedTasks: groupedTasks ?? this.groupedTasks,
        options: options ?? this.options,
        selectedOption: selectedOption ?? this.selectedOption,
        mutationId: mutationId ?? this.mutationId,
        policyModeAtCreation: policyModeAtCreation ?? this.policyModeAtCreation,
        policyVersionAtCreation:
            policyVersionAtCreation ?? this.policyVersionAtCreation,
        actionType: actionType,
        origin: origin,
        riskLevel: riskLevel,
        policyState: policyState ?? this.policyState,
        canonicalConfirmation: clearCanonicalConfirmation
            ? null
            : canonicalConfirmation ?? this.canonicalConfirmation,
        logicalRequestId: logicalRequestId ?? this.logicalRequestId,
        sourceSuggestionId: sourceSuggestionId ?? this.sourceSuggestionId,
      );
}

final class SmartPlanningContinuationResult {
  const SmartPlanningContinuationResult({
    required this.status,
    required this.message,
    required this.handled,
  });

  final SmartPlanningContinuationResultStatus status;
  final String message;
  final bool handled;
}
