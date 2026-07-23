import 'action_autonomy_policy.dart';
import 'action_inverse_patch.dart';

enum ActionLedgerDomain {
  event,
  task,
  shopping,
  profile,
  humanModel,
  memory,
  identity,
  routine,
}

enum ActionLedgerStatus {
  proposed,
  awaitingConfirmation,
  authorized,
  dispatching,
  pendingSync,
  succeeded,
  failed,
  conflict,
  blockedByPolicy,
  cancelled,
  expired,
  undoAvailable,
  undoRequested,
  undoDispatching,
  undone,
  undoPendingSync,
  undoConflict,
  undoFailed,
  notUndoable,
}

enum ActionOutcome {
  completed,
  pendingSync,
  rejected,
  conflict,
  validationFailure,
  policyBlocked,
  cancelled,
  unknownResult,
  technicalFailure,
}

enum ActionUndoCapabilityType {
  reversible,
  conditionallyReversible,
  irreversible,
  expired,
  conflict,
  unsupportedDomain,
  policyBlocked,
  targetChanged,
  alreadyUndone,
}

enum ActionUndoStrategy {
  undoCreateEvent,
  undoUpdateEvent,
  undoDeleteEvent,
  undoParticipantChange,
  undoCreateTask,
  undoUpdateTask,
  undoCompleteTask,
  undoReopenTask,
  undoDeleteTask,
  undoAddShoppingItem,
  undoUpdateShoppingItem,
  undoRemoveShoppingItem,
  undoProfilePatch,
  undoArchiveMemory,
  undoRestoreMemory,
  undoCorrectMemory,
  manualHumanModelResolution,
  identityNotSupported,
  routineNotSupported,
  irreversible,
}

final class ActionTargetReference {
  static const currentSchemaVersion = 1;

  ActionTargetReference({
    this.schemaVersion = currentSchemaVersion,
    required this.domain,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.revisionBefore,
    this.revisionAfter,
    required this.tombstoneBefore,
    this.tombstoneAfter,
    required this.patchType,
    required this.undoStrategy,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        entityType.trim().isEmpty ||
        entityType.length > 80 ||
        entityId.trim().isEmpty ||
        entityId.length > 200 ||
        operationType.trim().isEmpty ||
        operationType.length > 80 ||
        revisionBefore < 0 ||
        (revisionAfter != null && revisionAfter! <= revisionBefore) ||
        patchType.trim().isEmpty ||
        patchType.length > 80) {
      throw const FormatException('invalid_action_target_reference');
    }
  }

  final int schemaVersion;
  final ActionLedgerDomain domain;
  final String entityType;
  final String entityId;
  final String operationType;
  final int revisionBefore;
  final int? revisionAfter;
  final bool tombstoneBefore;
  final bool? tombstoneAfter;
  final String patchType;
  final ActionUndoStrategy undoStrategy;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'domain': domain.name,
        'entityType': entityType,
        'entityId': entityId,
        'operationType': operationType,
        'revisionBefore': revisionBefore,
        if (revisionAfter != null) 'revisionAfter': revisionAfter,
        'tombstoneBefore': tombstoneBefore,
        if (tombstoneAfter != null) 'tombstoneAfter': tombstoneAfter,
        'patchType': patchType,
        'undoStrategy': undoStrategy.name,
      };

  factory ActionTargetReference.fromJson(Map<String, dynamic> json) {
    const keys = {
      'schemaVersion',
      'domain',
      'entityType',
      'entityId',
      'operationType',
      'revisionBefore',
      'revisionAfter',
      'tombstoneBefore',
      'tombstoneAfter',
      'patchType',
      'undoStrategy',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('invalid_action_target_reference');
    }
    try {
      return ActionTargetReference(
        schemaVersion: json['schemaVersion'] as int,
        domain: ActionLedgerDomain.values.byName(json['domain'] as String),
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        operationType: json['operationType'] as String,
        revisionBefore: json['revisionBefore'] as int,
        revisionAfter: json['revisionAfter'] as int?,
        tombstoneBefore: json['tombstoneBefore'] as bool,
        tombstoneAfter: json['tombstoneAfter'] as bool?,
        patchType: json['patchType'] as String,
        undoStrategy:
            ActionUndoStrategy.values.byName(json['undoStrategy'] as String),
      );
    } on Object {
      throw const FormatException('invalid_action_target_reference');
    }
  }
}

final class ActionUndoCapability {
  const ActionUndoCapability({
    required this.type,
    required this.strategy,
    required this.reasonCode,
    required this.confirmationRequired,
    required this.currentRevisionRequired,
    required this.domain,
    required this.riskLevel,
    this.deadline,
  });

  final ActionUndoCapabilityType type;
  final ActionUndoStrategy strategy;
  final String reasonCode;
  final bool confirmationRequired;
  final bool currentRevisionRequired;
  final ActionLedgerDomain domain;
  final ActionRiskLevel riskLevel;
  final DateTime? deadline;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'strategy': strategy.name,
        'reasonCode': reasonCode,
        'confirmationRequired': confirmationRequired,
        'currentRevisionRequired': currentRevisionRequired,
        'domain': domain.name,
        'riskLevel': riskLevel.name,
        if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      };

  factory ActionUndoCapability.fromJson(Map<String, dynamic> json) {
    const keys = {
      'type',
      'strategy',
      'reasonCode',
      'confirmationRequired',
      'currentRevisionRequired',
      'domain',
      'riskLevel',
      'deadline',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('invalid_action_undo_capability');
    }
    try {
      return ActionUndoCapability(
        type: ActionUndoCapabilityType.values.byName(json['type'] as String),
        strategy: ActionUndoStrategy.values.byName(json['strategy'] as String),
        reasonCode: json['reasonCode'] as String,
        confirmationRequired: json['confirmationRequired'] as bool,
        currentRevisionRequired: json['currentRevisionRequired'] as bool,
        domain: ActionLedgerDomain.values.byName(json['domain'] as String),
        riskLevel: ActionRiskLevel.values.byName(json['riskLevel'] as String),
        deadline: json['deadline'] == null
            ? null
            : DateTime.parse(json['deadline'] as String).toUtc(),
      );
    } on Object {
      throw const FormatException('invalid_action_undo_capability');
    }
  }
}

final class ActionLedgerEntry {
  static const currentSchemaVersion = 1;

  ActionLedgerEntry({
    this.schemaVersion = currentSchemaVersion,
    required this.ledgerEntryId,
    required this.accountScopeId,
    required this.actionType,
    required this.actionDomain,
    required this.actionOrigin,
    required this.riskLevel,
    required this.policyModeObserved,
    required this.policyVersionObserved,
    this.sessionGeneration,
    this.requestId,
    this.pendingActionId,
    required this.mutationId,
    required this.targetReference,
    required this.expectedRevision,
    this.resultRevision,
    required this.status,
    required this.outcome,
    required this.createdAt,
    this.authorizedAt,
    this.dispatchedAt,
    this.completedAt,
    required this.updatedAt,
    required this.undoCapability,
    this.inversePatch,
    this.parentLedgerEntryId,
    this.causationLedgerEntryId,
    required this.correlationId,
    required this.provenance,
    this.errorCode,
    this.ledgerRevision = 1,
    required this.lastMutationId,
  }) {
    _validate();
  }

  final int schemaVersion;
  final String ledgerEntryId;
  final String accountScopeId;
  final ActionType actionType;
  final ActionLedgerDomain actionDomain;
  final ActionOrigin actionOrigin;
  final ActionRiskLevel riskLevel;
  final ActionAutonomyMode policyModeObserved;
  final int policyVersionObserved;
  final int? sessionGeneration;
  final String? requestId;
  final String? pendingActionId;
  final String mutationId;
  final ActionTargetReference targetReference;
  final int expectedRevision;
  final int? resultRevision;
  final ActionLedgerStatus status;
  final ActionOutcome outcome;
  final DateTime createdAt;
  final DateTime? authorizedAt;
  final DateTime? dispatchedAt;
  final DateTime? completedAt;
  final DateTime updatedAt;
  final ActionUndoCapability undoCapability;
  final ActionInversePatch? inversePatch;
  final String? parentLedgerEntryId;
  final String? causationLedgerEntryId;
  final String correlationId;
  final String provenance;
  final String? errorCode;
  final int ledgerRevision;
  final String lastMutationId;

  ActionLedgerEntry transition({
    required ActionLedgerStatus nextStatus,
    required ActionOutcome nextOutcome,
    required DateTime at,
    required String transitionMutationId,
    int? resultRevision,
    ActionUndoCapability? undoCapability,
  }) {
    if (!ActionLedgerTransitions.allows(status, nextStatus)) {
      throw const FormatException('invalid_action_ledger_transition');
    }
    return ActionLedgerEntry(
      ledgerEntryId: ledgerEntryId,
      accountScopeId: accountScopeId,
      actionType: actionType,
      actionDomain: actionDomain,
      actionOrigin: actionOrigin,
      riskLevel: riskLevel,
      policyModeObserved: policyModeObserved,
      policyVersionObserved: policyVersionObserved,
      sessionGeneration: sessionGeneration,
      requestId: requestId,
      pendingActionId: pendingActionId,
      mutationId: mutationId,
      targetReference: targetReference,
      expectedRevision: expectedRevision,
      resultRevision: resultRevision ?? this.resultRevision,
      status: nextStatus,
      outcome: nextOutcome,
      createdAt: createdAt,
      authorizedAt:
          nextStatus == ActionLedgerStatus.authorized ? at : authorizedAt,
      dispatchedAt:
          nextStatus == ActionLedgerStatus.dispatching ? at : dispatchedAt,
      completedAt: _terminalStatuses.contains(nextStatus) ? at : completedAt,
      updatedAt: at,
      undoCapability: undoCapability ?? this.undoCapability,
      inversePatch: inversePatch,
      parentLedgerEntryId: parentLedgerEntryId,
      causationLedgerEntryId: causationLedgerEntryId,
      correlationId: correlationId,
      provenance: provenance,
      errorCode: errorCode,
      ledgerRevision: ledgerRevision + 1,
      lastMutationId: transitionMutationId,
    );
  }

  void _validate() {
    if (schemaVersion != currentSchemaVersion ||
        ledgerEntryId.trim().isEmpty ||
        ledgerEntryId.length > 200 ||
        accountScopeId.trim().isEmpty ||
        mutationId.trim().isEmpty ||
        mutationId.length > 200 ||
        expectedRevision < 0 ||
        ledgerRevision < 1 ||
        lastMutationId.trim().isEmpty ||
        correlationId.trim().isEmpty ||
        provenance.trim().isEmpty ||
        provenance.length > 80 ||
        targetReference.domain != actionDomain ||
        targetReference.revisionBefore != expectedRevision ||
        (resultRevision != null && resultRevision! <= expectedRevision) ||
        (status == ActionLedgerStatus.succeeded &&
            outcome != ActionOutcome.completed) ||
        (status == ActionLedgerStatus.pendingSync &&
            outcome != ActionOutcome.pendingSync &&
            outcome != ActionOutcome.unknownResult) ||
        (undoCapability.type == ActionUndoCapabilityType.irreversible &&
            status == ActionLedgerStatus.undoAvailable)) {
      throw const FormatException('invalid_action_ledger_entry');
    }
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'ledgerEntryId': ledgerEntryId,
        'accountScopeId': accountScopeId,
        'actionType': actionType.name,
        'actionDomain': actionDomain.name,
        'actionOrigin': actionOrigin.name,
        'riskLevel': riskLevel.name,
        'policyModeObserved': policyModeObserved.name,
        'policyVersionObserved': policyVersionObserved,
        if (sessionGeneration != null) 'sessionGeneration': sessionGeneration,
        if (requestId != null) 'requestId': requestId,
        if (pendingActionId != null) 'pendingActionId': pendingActionId,
        'mutationId': mutationId,
        'targetReference': targetReference.toJson(),
        'expectedRevision': expectedRevision,
        if (resultRevision != null) 'resultRevision': resultRevision,
        'status': status.name,
        'outcome': outcome.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (authorizedAt != null)
          'authorizedAt': authorizedAt!.toUtc().toIso8601String(),
        if (dispatchedAt != null)
          'dispatchedAt': dispatchedAt!.toUtc().toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'undoCapability': undoCapability.toJson(),
        if (inversePatch != null) 'inversePatch': inversePatch!.toJson(),
        if (parentLedgerEntryId != null)
          'parentLedgerEntryId': parentLedgerEntryId,
        if (causationLedgerEntryId != null)
          'causationLedgerEntryId': causationLedgerEntryId,
        'correlationId': correlationId,
        'provenance': provenance,
        if (errorCode != null) 'errorCode': errorCode,
        'ledgerRevision': ledgerRevision,
        'lastMutationId': lastMutationId,
      };

  factory ActionLedgerEntry.fromJson(Map<String, dynamic> json) {
    const keys = {
      'schemaVersion',
      'ledgerEntryId',
      'accountScopeId',
      'actionType',
      'actionDomain',
      'actionOrigin',
      'riskLevel',
      'policyModeObserved',
      'policyVersionObserved',
      'sessionGeneration',
      'requestId',
      'pendingActionId',
      'mutationId',
      'targetReference',
      'expectedRevision',
      'resultRevision',
      'status',
      'outcome',
      'createdAt',
      'authorizedAt',
      'dispatchedAt',
      'completedAt',
      'updatedAt',
      'undoCapability',
      'inversePatch',
      'parentLedgerEntryId',
      'causationLedgerEntryId',
      'correlationId',
      'provenance',
      'errorCode',
      'ledgerRevision',
      'lastMutationId',
    };
    if (json.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('invalid_action_ledger_entry');
    }
    try {
      return ActionLedgerEntry(
        schemaVersion: json['schemaVersion'] as int,
        ledgerEntryId: json['ledgerEntryId'] as String,
        accountScopeId: json['accountScopeId'] as String,
        actionType: ActionType.values.byName(json['actionType'] as String),
        actionDomain:
            ActionLedgerDomain.values.byName(json['actionDomain'] as String),
        actionOrigin:
            ActionOrigin.values.byName(json['actionOrigin'] as String),
        riskLevel: ActionRiskLevel.values.byName(json['riskLevel'] as String),
        policyModeObserved: ActionAutonomyMode.values
            .byName(json['policyModeObserved'] as String),
        policyVersionObserved: json['policyVersionObserved'] as int,
        sessionGeneration: json['sessionGeneration'] as int?,
        requestId: json['requestId'] as String?,
        pendingActionId: json['pendingActionId'] as String?,
        mutationId: json['mutationId'] as String,
        targetReference: ActionTargetReference.fromJson(
          Map<String, dynamic>.from(json['targetReference'] as Map),
        ),
        expectedRevision: json['expectedRevision'] as int,
        resultRevision: json['resultRevision'] as int?,
        status: ActionLedgerStatus.values.byName(json['status'] as String),
        outcome: ActionOutcome.values.byName(json['outcome'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        authorizedAt: _date(json['authorizedAt']),
        dispatchedAt: _date(json['dispatchedAt']),
        completedAt: _date(json['completedAt']),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        undoCapability: ActionUndoCapability.fromJson(
          Map<String, dynamic>.from(json['undoCapability'] as Map),
        ),
        inversePatch: json['inversePatch'] == null
            ? null
            : ActionInversePatch.fromJson(
                Map<String, dynamic>.from(json['inversePatch'] as Map),
              ),
        parentLedgerEntryId: json['parentLedgerEntryId'] as String?,
        causationLedgerEntryId: json['causationLedgerEntryId'] as String?,
        correlationId: json['correlationId'] as String,
        provenance: json['provenance'] as String,
        errorCode: json['errorCode'] as String?,
        ledgerRevision: json['ledgerRevision'] as int,
        lastMutationId: json['lastMutationId'] as String,
      );
    } on Object {
      throw const FormatException('invalid_action_ledger_entry');
    }
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}

abstract final class ActionLedgerTransitions {
  static bool allows(ActionLedgerStatus current, ActionLedgerStatus next) =>
      (_allowed[current] ?? const {}).contains(next);

  static final Map<ActionLedgerStatus, Set<ActionLedgerStatus>> _allowed =
      Map.unmodifiable({
    ActionLedgerStatus.proposed: {
      ActionLedgerStatus.awaitingConfirmation,
      ActionLedgerStatus.authorized,
      ActionLedgerStatus.blockedByPolicy,
      ActionLedgerStatus.cancelled,
      ActionLedgerStatus.expired,
    },
    ActionLedgerStatus.awaitingConfirmation: {
      ActionLedgerStatus.authorized,
      ActionLedgerStatus.blockedByPolicy,
      ActionLedgerStatus.cancelled,
      ActionLedgerStatus.expired,
    },
    ActionLedgerStatus.authorized: {
      ActionLedgerStatus.dispatching,
      ActionLedgerStatus.blockedByPolicy,
      ActionLedgerStatus.cancelled,
    },
    ActionLedgerStatus.dispatching: {
      ActionLedgerStatus.pendingSync,
      ActionLedgerStatus.succeeded,
      ActionLedgerStatus.failed,
      ActionLedgerStatus.conflict,
    },
    ActionLedgerStatus.pendingSync: {
      ActionLedgerStatus.succeeded,
      ActionLedgerStatus.failed,
      ActionLedgerStatus.conflict,
    },
    ActionLedgerStatus.succeeded: {
      ActionLedgerStatus.undoAvailable,
      ActionLedgerStatus.notUndoable,
    },
    ActionLedgerStatus.undoAvailable: {
      ActionLedgerStatus.undoRequested,
      ActionLedgerStatus.expired,
    },
    ActionLedgerStatus.undoRequested: {
      ActionLedgerStatus.undoDispatching,
      ActionLedgerStatus.blockedByPolicy,
      ActionLedgerStatus.undoConflict,
      ActionLedgerStatus.undoFailed,
    },
    ActionLedgerStatus.undoDispatching: {
      ActionLedgerStatus.undone,
      ActionLedgerStatus.undoPendingSync,
      ActionLedgerStatus.undoConflict,
      ActionLedgerStatus.undoFailed,
    },
    ActionLedgerStatus.undoPendingSync: {
      ActionLedgerStatus.undone,
      ActionLedgerStatus.undoConflict,
      ActionLedgerStatus.undoFailed,
    },
  });
}

final class ActionUndoRequest {
  static const currentSchemaVersion = 1;

  ActionUndoRequest({
    this.schemaVersion = currentSchemaVersion,
    required this.undoMutationId,
    required this.sourceLedgerEntryId,
    required this.accountScopeId,
    required this.currentRevision,
    required this.policyMode,
    required this.policyVersion,
    required this.confirmed,
    required this.requestedAt,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        undoMutationId.trim().isEmpty ||
        sourceLedgerEntryId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        currentRevision < 1) {
      throw const FormatException('invalid_action_undo_request');
    }
  }

  final int schemaVersion;
  final String undoMutationId;
  final String sourceLedgerEntryId;
  final String accountScopeId;
  final int currentRevision;
  final ActionAutonomyMode policyMode;
  final int policyVersion;
  final bool confirmed;
  final DateTime requestedAt;
}

enum ActionUndoResultType {
  ready,
  confirmationRequired,
  blockedByPolicy,
  targetChanged,
  expired,
  alreadyUndone,
  notSupported,
  conflict,
}

final class ActionUndoResult {
  const ActionUndoResult({
    required this.type,
    required this.capability,
    required this.reasonCode,
  });

  final ActionUndoResultType type;
  final ActionUndoCapability capability;
  final String reasonCode;
}

const _terminalStatuses = {
  ActionLedgerStatus.succeeded,
  ActionLedgerStatus.failed,
  ActionLedgerStatus.conflict,
  ActionLedgerStatus.cancelled,
  ActionLedgerStatus.expired,
  ActionLedgerStatus.undone,
  ActionLedgerStatus.undoConflict,
  ActionLedgerStatus.undoFailed,
  ActionLedgerStatus.notUndoable,
};
