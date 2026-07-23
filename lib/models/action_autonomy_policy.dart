enum ActionAutonomyMode { normal, suggestions, paused }

enum ActionAutonomyChangeSource {
  explicitUserSetting,
  restrictiveDefault,
  migrationLegacy,
}

enum ActionType {
  answerGeneralQuestion,
  readAgenda,
  readTasks,
  readShopping,
  readRoutines,
  readMemory,
  explainPriority,
  inspectProfile,
  updateProfile,
  proposeEvent,
  createEvent,
  updateEvent,
  deleteEvent,
  resolveEventConflict,
  modifyParticipant,
  modifyRecurrence,
  smartPlanningReservation,
  proposeTask,
  createTask,
  updateTask,
  completeTask,
  deleteTask,
  proposeShoppingItem,
  addShoppingItem,
  updateShoppingItem,
  removeShoppingItem,
  clearShoppingList,
  proposeRoutine,
  createRoutine,
  updateRoutine,
  archiveRoutine,
  deleteRoutine,
  proposeMemory,
  confirmMemory,
  correctMemory,
  archiveMemory,
  deleteMemory,
  deleteAllMemory,
  proposePerson,
  createPerson,
  updatePerson,
  archivePerson,
  createIdentity,
  linkIdentity,
  modifyRelationship,
  modifyHousehold,
  modifyResponsibility,
  thirdPartyUnsupported,
}

enum ActionOrigin {
  explicitUserRequest,
  explicitUserConfirmation,
  assistantSuggestion,
  structuredContinuation,
  retry,
  restoredPending,
  systemProactive,
  externalTrigger,
  unknown,
}

enum ActionRiskLevel {
  readOnly,
  reversibleLowRisk,
  mutation,
  sensitiveMutation,
  destructive,
  thirdParty,
}

enum ActionAuthorizationDecisionType {
  allowReadOnly,
  allowExecution,
  allowProposal,
  requireExplicitConfirmation,
  blockedPaused,
  blockedUnsupported,
  blockedUnknownOrigin,
  blockedIncomplete,
  blockedUngrounded,
  blockedDomainPolicy,
  blockedConflict,
  blockedAlreadyExecuted,
  blockedStalePolicy,
  invalidRequest,
}

enum ActionPendingPolicyState {
  active,
  blockedByPolicy,
  expired,
  completed,
}

enum ActionPendingState {
  awaitingConfirmation,
  blockedByPolicy,
  readyAfterConfirmation,
  executing,
  pendingSync,
  completed,
  rejected,
  expired,
  cancelled,
}

sealed class ActionPendingPayload {
  const ActionPendingPayload();

  ActionType get actionType;
}

final class PendingTaskPayload extends ActionPendingPayload {
  const PendingTaskPayload({
    required this.title,
    this.dueDate = '',
    this.notes = '',
    this.planning = '',
    this.priority = '',
    this.isImportant = false,
  }) : assert(title.length <= 500);

  final String title;
  final String dueDate;
  final String notes;
  final String planning;
  final String priority;
  final bool isImportant;

  @override
  ActionType get actionType => ActionType.createTask;
}

final class PendingShoppingPayload extends ActionPendingPayload {
  const PendingShoppingPayload({
    required this.title,
    this.category = '',
    this.notes = '',
    this.section = '',
    this.isUrgent = false,
  }) : assert(title.length <= 500);

  final String title;
  final String category;
  final String notes;
  final String section;
  final bool isUrgent;

  @override
  ActionType get actionType => ActionType.addShoppingItem;
}

final class ActionPending {
  static const int currentSchemaVersion = 1;
  static const int maximumAttempts = 2;

  const ActionPending({
    this.schemaVersion = currentSchemaVersion,
    required this.pendingActionId,
    required this.sessionGeneration,
    required this.actionType,
    required this.origin,
    required this.riskLevel,
    required this.policyModeAtCreation,
    required this.policyVersionAtCreation,
    required this.wasGrounded,
    required this.wasComplete,
    required this.payload,
    required this.originalInstruction,
    required this.mutationId,
    required this.createdAt,
    this.expiresAt,
    this.state = ActionPendingState.awaitingConfirmation,
    this.hasFreshConfirmation = false,
    this.attemptCount = 0,
  });

  final int schemaVersion;
  final String pendingActionId;
  final int sessionGeneration;
  final ActionType actionType;
  final ActionOrigin origin;
  final ActionRiskLevel riskLevel;
  final ActionAutonomyMode policyModeAtCreation;
  final int policyVersionAtCreation;
  final bool wasGrounded;
  final bool wasComplete;
  final ActionPendingPayload payload;
  final String originalInstruction;
  final String mutationId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final ActionPendingState state;
  final bool hasFreshConfirmation;
  final int attemptCount;

  bool isExpiredAt(DateTime value) =>
      expiresAt != null && !value.isBefore(expiresAt!);

  void validate() {
    final payloadValid = switch (payload) {
      PendingTaskPayload(
        :final title,
        :final dueDate,
        :final notes,
        :final planning,
        :final priority,
      ) =>
        title.trim().isNotEmpty &&
            title.length <= 500 &&
            dueDate.length <= 80 &&
            notes.length <= 2000 &&
            planning.length <= 120 &&
            priority.length <= 80,
      PendingShoppingPayload(
        :final title,
        :final category,
        :final notes,
        :final section,
      ) =>
        title.trim().isNotEmpty &&
            title.length <= 500 &&
            category.length <= 120 &&
            notes.length <= 2000 &&
            section.length <= 120,
    };
    if (schemaVersion != currentSchemaVersion ||
        pendingActionId.trim().isEmpty ||
        mutationId.trim().isEmpty ||
        originalInstruction.trim().isEmpty ||
        originalInstruction.length > 4000 ||
        sessionGeneration < 0 ||
        payload.actionType != actionType ||
        attemptCount < 0 ||
        attemptCount > maximumAttempts ||
        expiresAt != null && !expiresAt!.isAfter(createdAt) ||
        !payloadValid) {
      throw const ActionAutonomyPolicyException('invalid_action_pending');
    }
  }

  ActionPending copyWith({
    ActionPendingState? state,
    bool? hasFreshConfirmation,
    int? attemptCount,
  }) =>
      ActionPending(
        pendingActionId: pendingActionId,
        sessionGeneration: sessionGeneration,
        actionType: actionType,
        origin: origin,
        riskLevel: riskLevel,
        policyModeAtCreation: policyModeAtCreation,
        policyVersionAtCreation: policyVersionAtCreation,
        wasGrounded: wasGrounded,
        wasComplete: wasComplete,
        payload: payload,
        originalInstruction: originalInstruction,
        mutationId: mutationId,
        createdAt: createdAt,
        expiresAt: expiresAt,
        state: state ?? this.state,
        hasFreshConfirmation: hasFreshConfirmation ?? this.hasFreshConfirmation,
        attemptCount: attemptCount ?? this.attemptCount,
      );
}

final class ActionPendingMetadata {
  const ActionPendingMetadata({
    required this.actionType,
    required this.origin,
    required this.riskLevel,
    required this.policyModeAtCreation,
    required this.policyVersionAtCreation,
    required this.sessionGeneration,
  });

  final ActionType actionType;
  final ActionOrigin origin;
  final ActionRiskLevel riskLevel;
  final ActionAutonomyMode policyModeAtCreation;
  final int policyVersionAtCreation;
  final int sessionGeneration;
}

final class ActionAutonomyPolicyException implements Exception {
  const ActionAutonomyPolicyException(this.code);
  final String code;
}

final class ActionAutonomyPolicy {
  static const int currentSchemaVersion = 1;

  const ActionAutonomyPolicy({
    this.schemaVersion = currentSchemaVersion,
    required this.mode,
    required this.changedAt,
    required this.changeSource,
    required this.accountScopeId,
    this.policyRevision = 0,
  });

  factory ActionAutonomyPolicy.restrictiveDefault({
    required String accountScopeId,
    required DateTime changedAt,
  }) =>
      ActionAutonomyPolicy(
        mode: ActionAutonomyMode.suggestions,
        changedAt: changedAt.toUtc(),
        changeSource: ActionAutonomyChangeSource.restrictiveDefault,
        accountScopeId: accountScopeId,
      );

  factory ActionAutonomyPolicy.fromJson(
    Map<String, Object?> json, {
    required String expectedAccountScopeId,
  }) {
    if (json['schemaVersion'] != currentSchemaVersion) {
      throw const ActionAutonomyPolicyException(
        'unsupported_action_autonomy_policy_version',
      );
    }
    final mode = _enumByName(ActionAutonomyMode.values, json['mode']);
    final source =
        _enumByName(ActionAutonomyChangeSource.values, json['changeSource']);
    final changedAt = DateTime.tryParse(json['changedAt']?.toString() ?? '');
    final scope = json['accountScopeId']?.toString() ?? '';
    final revision = json['policyRevision'];
    if (mode == null ||
        source == null ||
        changedAt == null ||
        scope.isEmpty ||
        scope != expectedAccountScopeId ||
        revision is! int ||
        revision < 0) {
      throw const ActionAutonomyPolicyException(
        'invalid_action_autonomy_policy',
      );
    }
    return ActionAutonomyPolicy(
      mode: mode,
      changedAt: changedAt.toUtc(),
      changeSource: source,
      accountScopeId: scope,
      policyRevision: revision,
    );
  }

  final int schemaVersion;
  final ActionAutonomyMode mode;
  final DateTime changedAt;
  final ActionAutonomyChangeSource changeSource;
  final String accountScopeId;
  final int policyRevision;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'mode': mode.name,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'changeSource': changeSource.name,
        'accountScopeId': accountScopeId,
        'policyRevision': policyRevision,
      };

  Map<String, Object?> toBackendSummary() => {
        'schemaVersion': schemaVersion,
        'mode': mode.name,
      };

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        policyRevision < 0) {
      throw const ActionAutonomyPolicyException(
        'invalid_action_autonomy_policy',
      );
    }
  }
}

final class ActionAuthorizationRequest {
  static const int currentSchemaVersion = 1;

  const ActionAuthorizationRequest({
    this.schemaVersion = currentSchemaVersion,
    required this.actionType,
    required this.origin,
    required this.riskLevel,
    required this.sessionGeneration,
    required this.policyVersionObserved,
    this.isGrounded = true,
    this.isComplete = true,
    this.domainPolicyAllows = true,
    this.domainConfirmationRequired = false,
    this.hasFreshExplicitConfirmation = false,
    this.hasBlockingConflict = false,
    this.isAlreadyExecuted = false,
    this.isPending = false,
  });

  final int schemaVersion;
  final ActionType actionType;
  final ActionOrigin origin;
  final ActionRiskLevel riskLevel;
  final int sessionGeneration;
  final int policyVersionObserved;
  final bool isGrounded;
  final bool isComplete;
  final bool domainPolicyAllows;
  final bool domainConfirmationRequired;
  final bool hasFreshExplicitConfirmation;
  final bool hasBlockingConflict;
  final bool isAlreadyExecuted;
  final bool isPending;
}

final class ActionAuthorizationDecision {
  static const int currentSchemaVersion = 1;

  const ActionAuthorizationDecision({
    this.schemaVersion = currentSchemaVersion,
    required this.decision,
    required this.actionType,
    required this.modeObserved,
    required this.reasonCode,
    required this.requiresConfirmation,
    required this.mayCreateProposal,
    required this.mayExecute,
    required this.revalidationRequired,
    required this.blockingState,
    required this.policyVersion,
    required this.evaluatedAt,
  });

  final int schemaVersion;
  final ActionAuthorizationDecisionType decision;
  final ActionType actionType;
  final ActionAutonomyMode modeObserved;
  final String reasonCode;
  final bool requiresConfirmation;
  final bool mayCreateProposal;
  final bool mayExecute;
  final bool revalidationRequired;
  final ActionPendingPolicyState? blockingState;
  final int policyVersion;
  final DateTime evaluatedAt;
}

T? _enumByName<T extends Enum>(Iterable<T> values, Object? raw) {
  final value = raw?.toString();
  for (final item in values) {
    if (item.name == value) return item;
  }
  return null;
}
