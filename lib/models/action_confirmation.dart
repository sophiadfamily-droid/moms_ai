import 'dart:collection';
import 'dart:convert';

import 'action_autonomy_policy.dart';
import 'action_ledger.dart';

enum ActionConfirmationScopeType {
  executeExactMutation,
  confirmSensitiveMutation,
  confirmDestructiveMutation,
  confirmConflictResolution,
  confirmSmartPlanningReservation,
  confirmIdentityLink,
  confirmMemoryConsent,
  confirmThirdPartyAction,
  customUnsupported,
}

enum ActionConfirmationRequirementSource {
  autonomySuggestionsMode,
  domainRequired,
  sensitiveMutation,
  destructiveMutation,
  memoryPolicy,
  healthPolicy,
  identityPolicy,
  conflictResolution,
  thirdPartyPolicy,
  explicitProductRule,
}

enum ActionConfirmationFieldKey {
  targetId,
  operation,
  title,
  date,
  time,
  durationMinutes,
  travelGoMinutes,
  travelBackMinutes,
  marginMinutes,
  participantId,
  recurrenceType,
  recurrenceWeekday,
  recurrenceUntil,
  dueDate,
  quantity,
  category,
  location,
  section,
  tombstone,
  choiceId,
}

enum ActionConfirmationState {
  proposed,
  awaitingResponse,
  accepted,
  rejected,
  postponed,
  cancelled,
  expired,
  superseded,
  consumed,
  blockedByPolicy,
  blockedByConflict,
  staleAction,
  invalid,
  completed,
}

enum ActionConfirmationResponseChoice { accept, reject, postpone, cancel }

enum ActionConfirmationResultType {
  awaitingResponse,
  accepted,
  rejected,
  postponed,
  cancelled,
  expired,
  superseded,
  consumed,
  blockedByPolicy,
  blockedByConflict,
  staleAction,
  invalid,
  completed,
  thirdPartyUnsupported,
}

final class ActionConfirmationField {
  const ActionConfirmationField({
    required this.key,
    required this.value,
  });

  final ActionConfirmationFieldKey key;
  final Object? value;

  void validate() {
    final valid = value == null ||
        value is bool ||
        value is int ||
        value is String && (value as String).length <= 500;
    if (!valid) throw const FormatException('invalid_confirmation_field');
  }

  String get canonicalValue => switch (value) {
        null => 'n:',
        bool value => 'b:${value ? 1 : 0}',
        int value => 'i:$value',
        String value => 's:${base64Url.encode(utf8.encode(value))}',
        _ => throw const FormatException('invalid_confirmation_field'),
      };

  Map<String, Object?> toJson() => {'key': key.name, 'value': value};
}

final class ActionConfirmationScope {
  ActionConfirmationScope({
    required this.type,
    required this.targetId,
    required this.operation,
    required this.expectedRevision,
    required Iterable<ActionConfirmationField> fields,
  }) : _fields = List.unmodifiable(fields) {
    if (targetId.trim().isEmpty ||
        targetId.length > 200 ||
        operation.trim().isEmpty ||
        operation.length > 80 ||
        expectedRevision < 0 ||
        _fields.length > 24) {
      throw const FormatException('invalid_confirmation_scope');
    }
    final keys = <ActionConfirmationFieldKey>{};
    for (final field in _fields) {
      field.validate();
      if (!keys.add(field.key)) {
        throw const FormatException('duplicate_confirmation_field');
      }
    }
  }

  final ActionConfirmationScopeType type;
  final String targetId;
  final String operation;
  final int expectedRevision;
  final List<ActionConfirmationField> _fields;

  UnmodifiableListView<ActionConfirmationField> get fields =>
      UnmodifiableListView(_fields);

  String canonicalForm({
    required ActionType actionType,
    required ActionLedgerDomain domain,
    required ActionRiskLevel riskLevel,
    required String mutationId,
  }) {
    final sorted = [..._fields]
      ..sort((a, b) => a.key.name.compareTo(b.key.name));
    return [
      'a3-v1',
      actionType.name,
      domain.name,
      riskLevel.name,
      type.name,
      _encoded(targetId),
      _encoded(operation),
      expectedRevision.toString(),
      _encoded(mutationId),
      for (final field in sorted) '${field.key.name}=${field.canonicalValue}',
    ].join('|');
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        'targetId': targetId,
        'operation': operation,
        'expectedRevision': expectedRevision,
        'fields': _fields.map((item) => item.toJson()).toList(growable: false),
      };
}

final class ActionConfirmationRequirement {
  const ActionConfirmationRequirement({
    required this.source,
    required this.code,
    required this.scope,
    required this.requiresFreshConfirmation,
    required this.requiresSeparateConfirmation,
    required this.policyVersionObserved,
  });

  final ActionConfirmationRequirementSource source;
  final String code;
  final ActionConfirmationScopeType scope;
  final bool requiresFreshConfirmation;
  final bool requiresSeparateConfirmation;
  final int policyVersionObserved;

  void validate() {
    if (code.trim().isEmpty || code.length > 80 || policyVersionObserved < 1) {
      throw const FormatException('invalid_confirmation_requirement');
    }
  }

  Map<String, Object?> toJson() => {
        'source': source.name,
        'code': code,
        'scope': scope.name,
        'requiresFreshConfirmation': requiresFreshConfirmation,
        'requiresSeparateConfirmation': requiresSeparateConfirmation,
        'policyVersionObserved': policyVersionObserved,
      };
}

final class ActionConfirmationPresentation {
  const ActionConfirmationPresentation({
    required this.title,
    required this.summary,
    required this.consequence,
    this.allowPostpone = false,
  });

  final String title;
  final String summary;
  final String consequence;
  final bool allowPostpone;

  void validate() {
    if (title.trim().isEmpty ||
        title.length > 120 ||
        summary.trim().isEmpty ||
        summary.length > 500 ||
        consequence.trim().isEmpty ||
        consequence.length > 300) {
      throw const FormatException('invalid_confirmation_presentation');
    }
  }

  Map<String, Object?> toJson() => {
        'title': title,
        'summary': summary,
        'consequence': consequence,
        'allowPostpone': allowPostpone,
      };
}

final class ActionConfirmation {
  static const currentSchemaVersion = 1;
  static const maximumAttemptsLimit = 3;

  ActionConfirmation({
    this.schemaVersion = currentSchemaVersion,
    required this.confirmationId,
    required this.accountScopeId,
    required this.sessionGeneration,
    this.requestId,
    required this.actionPendingId,
    this.ledgerEntryId,
    required this.actionType,
    required this.actionDomain,
    required this.actionOrigin,
    required this.riskLevel,
    required this.confirmationScope,
    required Iterable<ActionConfirmationRequirement> requirements,
    required this.actionFingerprint,
    required this.mutationId,
    required this.policyModeAtCreation,
    required this.policyVersionAtCreation,
    required this.createdAt,
    required this.expiresAt,
    required this.state,
    this.attemptCount = 0,
    this.maximumAttempts = 2,
    this.consumedAt,
    this.responseId,
    this.supersededByConfirmationId,
    required this.userPresentation,
    required this.provenance,
  }) : _requirements = List.unmodifiable(requirements) {
    validate();
  }

  final int schemaVersion;
  final String confirmationId;
  final String accountScopeId;
  final int sessionGeneration;
  final String? requestId;
  final String actionPendingId;
  final String? ledgerEntryId;
  final ActionType actionType;
  final ActionLedgerDomain actionDomain;
  final ActionOrigin actionOrigin;
  final ActionRiskLevel riskLevel;
  final ActionConfirmationScope confirmationScope;
  final List<ActionConfirmationRequirement> _requirements;
  final String actionFingerprint;
  final String mutationId;
  final ActionAutonomyMode policyModeAtCreation;
  final int policyVersionAtCreation;
  final DateTime createdAt;
  final DateTime expiresAt;
  final ActionConfirmationState state;
  final int attemptCount;
  final int maximumAttempts;
  final DateTime? consumedAt;
  final String? responseId;
  final String? supersededByConfirmationId;
  final ActionConfirmationPresentation userPresentation;
  final String provenance;

  UnmodifiableListView<ActionConfirmationRequirement> get requirements =>
      UnmodifiableListView(_requirements);

  bool isExpiredAt(DateTime value) => !value.isBefore(expiresAt);

  void validate() {
    userPresentation.validate();
    if (schemaVersion != currentSchemaVersion ||
        confirmationId.trim().isEmpty ||
        confirmationId.length > 200 ||
        accountScopeId.trim().isEmpty ||
        accountScopeId.length > 200 ||
        sessionGeneration < 0 ||
        actionPendingId.trim().isEmpty ||
        actionPendingId.length > 200 ||
        actionFingerprint.trim().isEmpty ||
        actionFingerprint.length > 160 ||
        mutationId.trim().isEmpty ||
        mutationId.length > 200 ||
        policyVersionAtCreation < 1 ||
        !expiresAt.isAfter(createdAt) ||
        _requirements.isEmpty ||
        _requirements.length > 8 ||
        attemptCount < 0 ||
        attemptCount > maximumAttempts ||
        maximumAttempts < 1 ||
        maximumAttempts > maximumAttemptsLimit ||
        provenance.trim().isEmpty ||
        provenance.length > 80 ||
        (state == ActionConfirmationState.consumed && consumedAt == null) ||
        (responseId != null && responseId!.trim().isEmpty)) {
      throw const FormatException('invalid_action_confirmation');
    }
    for (final requirement in _requirements) {
      requirement.validate();
    }
  }

  ActionConfirmation transition({
    required ActionConfirmationState next,
    required DateTime at,
    String? responseId,
    String? supersededByConfirmationId,
    bool incrementAttempt = false,
  }) {
    if (!ActionConfirmationStateMachine.allows(state, next)) {
      throw const FormatException('invalid_confirmation_transition');
    }
    return ActionConfirmation(
      confirmationId: confirmationId,
      accountScopeId: accountScopeId,
      sessionGeneration: sessionGeneration,
      requestId: requestId,
      actionPendingId: actionPendingId,
      ledgerEntryId: ledgerEntryId,
      actionType: actionType,
      actionDomain: actionDomain,
      actionOrigin: actionOrigin,
      riskLevel: riskLevel,
      confirmationScope: confirmationScope,
      requirements: _requirements,
      actionFingerprint: actionFingerprint,
      mutationId: mutationId,
      policyModeAtCreation: policyModeAtCreation,
      policyVersionAtCreation: policyVersionAtCreation,
      createdAt: createdAt,
      expiresAt: expiresAt,
      state: next,
      attemptCount: attemptCount + (incrementAttempt ? 1 : 0),
      maximumAttempts: maximumAttempts,
      consumedAt: next == ActionConfirmationState.consumed ? at : consumedAt,
      responseId: responseId ?? this.responseId,
      supersededByConfirmationId:
          supersededByConfirmationId ?? this.supersededByConfirmationId,
      userPresentation: userPresentation,
      provenance: provenance,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'confirmationId': confirmationId,
        'sessionGeneration': sessionGeneration,
        if (requestId != null) 'requestId': requestId,
        'actionPendingId': actionPendingId,
        if (ledgerEntryId != null) 'ledgerEntryId': ledgerEntryId,
        'actionType': actionType.name,
        'actionDomain': actionDomain.name,
        'actionOrigin': actionOrigin.name,
        'riskLevel': riskLevel.name,
        'confirmationScope': confirmationScope.toJson(),
        'requirements':
            _requirements.map((item) => item.toJson()).toList(growable: false),
        'actionFingerprint': actionFingerprint,
        'mutationId': mutationId,
        'policyModeAtCreation': policyModeAtCreation.name,
        'policyVersionAtCreation': policyVersionAtCreation,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'state': state.name,
        'attemptCount': attemptCount,
        'maximumAttempts': maximumAttempts,
        if (consumedAt != null)
          'consumedAt': consumedAt!.toUtc().toIso8601String(),
        if (responseId != null) 'responseId': responseId,
        if (supersededByConfirmationId != null)
          'supersededByConfirmationId': supersededByConfirmationId,
        'userPresentation': userPresentation.toJson(),
        'provenance': provenance,
      };
}

final class ActionConfirmationResponse {
  const ActionConfirmationResponse({
    required this.responseId,
    required this.confirmationId,
    required this.sessionGeneration,
    required this.respondedAt,
    required this.choice,
    this.choiceId,
    required this.actionFingerprint,
  });

  final String responseId;
  final String confirmationId;
  final int sessionGeneration;
  final DateTime respondedAt;
  final ActionConfirmationResponseChoice choice;
  final String? choiceId;
  final String actionFingerprint;

  void validate() {
    if (responseId.trim().isEmpty ||
        responseId.length > 200 ||
        confirmationId.trim().isEmpty ||
        confirmationId.length > 200 ||
        sessionGeneration < 0 ||
        actionFingerprint.trim().isEmpty ||
        (choiceId != null &&
            (choiceId!.trim().isEmpty || choiceId!.length > 120))) {
      throw const FormatException('invalid_confirmation_response');
    }
  }

  String get receipt =>
      '$confirmationId|${choice.name}|${choiceId ?? ''}|$actionFingerprint';
}

final class ActionConfirmationResult {
  const ActionConfirmationResult({
    required this.type,
    required this.confirmation,
    required this.reasonCode,
    this.dispatchAllowed = false,
    this.idempotent = false,
  });

  final ActionConfirmationResultType type;
  final ActionConfirmation confirmation;
  final String reasonCode;
  final bool dispatchAllowed;
  final bool idempotent;
}

abstract final class ActionConfirmationFingerprint {
  static String compute({
    required ActionType actionType,
    required ActionLedgerDomain domain,
    required ActionRiskLevel riskLevel,
    required ActionConfirmationScope scope,
    required String mutationId,
  }) {
    final canonical = scope.canonicalForm(
      actionType: actionType,
      domain: domain,
      riskLevel: riskLevel,
      mutationId: mutationId,
    );
    final bytes = utf8.encode(canonical);
    final first = _fnv64(bytes, 0xcbf29ce484222325);
    final second = _fnv64(bytes.reversed, 0x84222325cbf29ce4);
    return 'a3-${first.toRadixString(16).padLeft(16, '0')}'
        '${second.toRadixString(16).padLeft(16, '0')}';
  }

  static int _fnv64(Iterable<int> bytes, int seed) {
    var hash = seed;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash;
  }
}

abstract final class ActionConfirmationStateMachine {
  static bool allows(
          ActionConfirmationState current, ActionConfirmationState next) =>
      (_allowed[current] ?? const {}).contains(next);

  static final Map<ActionConfirmationState, Set<ActionConfirmationState>>
      _allowed = Map.unmodifiable({
    ActionConfirmationState.proposed: {
      ActionConfirmationState.awaitingResponse,
      ActionConfirmationState.blockedByPolicy,
      ActionConfirmationState.invalid,
    },
    ActionConfirmationState.awaitingResponse: {
      ActionConfirmationState.accepted,
      ActionConfirmationState.rejected,
      ActionConfirmationState.postponed,
      ActionConfirmationState.cancelled,
      ActionConfirmationState.expired,
      ActionConfirmationState.superseded,
      ActionConfirmationState.blockedByPolicy,
      ActionConfirmationState.blockedByConflict,
      ActionConfirmationState.staleAction,
      ActionConfirmationState.invalid,
    },
    ActionConfirmationState.accepted: {
      ActionConfirmationState.consumed,
      ActionConfirmationState.blockedByPolicy,
      ActionConfirmationState.blockedByConflict,
      ActionConfirmationState.staleAction,
      ActionConfirmationState.expired,
      ActionConfirmationState.invalid,
    },
    ActionConfirmationState.consumed: {
      ActionConfirmationState.completed,
      ActionConfirmationState.blockedByConflict,
      ActionConfirmationState.invalid,
    },
  });
}

String _encoded(String value) => base64Url.encode(utf8.encode(value));
