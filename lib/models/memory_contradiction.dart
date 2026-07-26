enum MemoryContradictionReasonCode {
  incompatibleClosedAttributeValues,
}

enum MemoryReplacementActionType { memoryReplacementConfirmation }

enum MemoryReplacementActionState {
  pending,
  declined,
  acceptedPendingExecution,
  executed,
  conflict,
  cancelled,
}

enum MemoryReplacementExecutionCode {
  executed,
  alreadyExecuted,
  revisionConflict,
  invalidState,
  missingDocument,
  scopeMismatch,
  identityMismatch,
  expired,
  unavailable,
}

final class MemoryContradictionMatch {
  const MemoryContradictionMatch({
    required this.existingMemoryId,
    required this.proposedMemoryId,
    required this.canonicalKey,
    required this.existingRevision,
    required this.existingValueFingerprint,
    required this.proposedValueFingerprint,
    required this.subjectScope,
    required this.reasonCode,
  });

  final String existingMemoryId;
  final String proposedMemoryId;
  final String canonicalKey;
  final int existingRevision;
  final String existingValueFingerprint;
  final String proposedValueFingerprint;
  final String subjectScope;
  final MemoryContradictionReasonCode reasonCode;
}

final class MemoryContradictionCandidate {
  static const currentSchemaVersion = 1;

  MemoryContradictionCandidate({
    required this.contradictionId,
    required this.existingMemoryId,
    required this.proposedMemoryId,
    required this.canonicalKey,
    required this.existingRevision,
    required this.proposedRevision,
    required this.existingValueFingerprint,
    required this.proposedValueFingerprint,
    required this.subjectScope,
    required this.detectedAt,
    required this.reasonCode,
    required this.eligibleForReplacement,
    this.schemaVersion = currentSchemaVersion,
  }) {
    if (!_isValidId(contradictionId) ||
        existingMemoryId.trim().isEmpty ||
        proposedMemoryId.trim().isEmpty ||
        existingMemoryId == proposedMemoryId ||
        canonicalKey.trim().isEmpty ||
        existingRevision < 1 ||
        proposedRevision < 1 ||
        !_isFingerprint(existingValueFingerprint) ||
        !_isFingerprint(proposedValueFingerprint) ||
        existingValueFingerprint == proposedValueFingerprint ||
        subjectScope.trim().isEmpty ||
        !detectedAt.isUtc ||
        !eligibleForReplacement ||
        schemaVersion != currentSchemaVersion) {
      throw const FormatException('invalid_memory_contradiction_candidate');
    }
  }

  final String contradictionId;
  final String existingMemoryId;
  final String proposedMemoryId;
  final String canonicalKey;
  final int existingRevision;
  final int proposedRevision;
  final String existingValueFingerprint;
  final String proposedValueFingerprint;
  final String subjectScope;
  final DateTime detectedAt;
  final MemoryContradictionReasonCode reasonCode;
  final bool eligibleForReplacement;
  final int schemaVersion;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'contradictionId': contradictionId,
        'existingMemoryId': existingMemoryId,
        'proposedMemoryId': proposedMemoryId,
        'canonicalKey': canonicalKey,
        'existingRevision': existingRevision,
        'proposedRevision': proposedRevision,
        'existingValueFingerprint': existingValueFingerprint,
        'proposedValueFingerprint': proposedValueFingerprint,
        'subjectScope': subjectScope,
        'detectedAt': detectedAt.toIso8601String(),
        'reasonCode': reasonCode.name,
        'eligibleForReplacement': eligibleForReplacement,
      };

  factory MemoryContradictionCandidate.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('invalid_memory_contradiction_candidate');
    }
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('invalid_memory_contradiction_candidate');
      }
      map[entry.key as String] = entry.value;
    }
    final reason = map['reasonCode'];
    final detectedAt = DateTime.tryParse(map['detectedAt']?.toString() ?? '');
    if (reason is! String || detectedAt == null) {
      throw const FormatException('invalid_memory_contradiction_candidate');
    }
    final reasonCode = MemoryContradictionReasonCode.values
        .where((item) => item.name == reason)
        .firstOrNull;
    if (reasonCode == null) {
      throw const FormatException('invalid_memory_contradiction_candidate');
    }
    return MemoryContradictionCandidate(
      contradictionId: map['contradictionId']?.toString() ?? '',
      existingMemoryId: map['existingMemoryId']?.toString() ?? '',
      proposedMemoryId: map['proposedMemoryId']?.toString() ?? '',
      canonicalKey: map['canonicalKey']?.toString() ?? '',
      existingRevision:
          map['existingRevision'] is int ? map['existingRevision'] as int : 0,
      proposedRevision:
          map['proposedRevision'] is int ? map['proposedRevision'] as int : 0,
      existingValueFingerprint:
          map['existingValueFingerprint']?.toString() ?? '',
      proposedValueFingerprint:
          map['proposedValueFingerprint']?.toString() ?? '',
      subjectScope: map['subjectScope']?.toString() ?? '',
      detectedAt: detectedAt.toUtc(),
      reasonCode: reasonCode,
      eligibleForReplacement: map['eligibleForReplacement'] == true,
      schemaVersion:
          map['schemaVersion'] is int ? map['schemaVersion'] as int : 0,
    );
  }

  static bool _isFingerprint(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  static bool _isValidId(String value) => _isFingerprint(value);
}

final class MemoryReplacementPendingAction {
  static const currentSchemaVersion = 1;

  MemoryReplacementPendingAction({
    required this.actionId,
    this.actionType = MemoryReplacementActionType.memoryReplacementConfirmation,
    required this.accountScopeFingerprint,
    required this.existingMemoryId,
    required this.proposedMemoryId,
    required this.canonicalKey,
    required this.expectedExistingRevision,
    required this.expectedProposedRevision,
    required this.contradictionId,
    required this.reasonCode,
    required this.state,
    required this.logicalRequestFingerprint,
    required this.createdAt,
    required this.updatedAt,
    this.executedAt,
    this.executionCode,
    this.finalExistingRevision,
    this.finalProposedRevision,
    this.schemaVersion = currentSchemaVersion,
  }) {
    if (!_fingerprint(actionId) ||
        !_fingerprint(accountScopeFingerprint) ||
        !_fingerprint(logicalRequestFingerprint) ||
        !_fingerprint(contradictionId) ||
        existingMemoryId.trim().isEmpty ||
        proposedMemoryId.trim().isEmpty ||
        existingMemoryId == proposedMemoryId ||
        canonicalKey.trim().isEmpty ||
        !canonicalKey.startsWith('v1|') ||
        expectedExistingRevision < 1 ||
        expectedProposedRevision < 1 ||
        !createdAt.isUtc ||
        !updatedAt.isUtc ||
        updatedAt.isBefore(createdAt) ||
        (executedAt != null && !executedAt!.isUtc) ||
        (state == MemoryReplacementActionState.executed &&
            (executedAt == null ||
                executionCode != MemoryReplacementExecutionCode.executed ||
                finalExistingRevision == null ||
                finalProposedRevision == null)) ||
        (state != MemoryReplacementActionState.executed &&
            (executedAt != null ||
                finalExistingRevision != null ||
                finalProposedRevision != null)) ||
        (state == MemoryReplacementActionState.conflict &&
            (executionCode == null ||
                executionCode == MemoryReplacementExecutionCode.executed ||
                executionCode ==
                    MemoryReplacementExecutionCode.alreadyExecuted)) ||
        (state != MemoryReplacementActionState.executed &&
            state != MemoryReplacementActionState.conflict &&
            executionCode != null) ||
        schemaVersion != currentSchemaVersion) {
      throw const FormatException('invalid_memory_replacement_pending_action');
    }
  }

  final String actionId;
  final MemoryReplacementActionType actionType;
  final String accountScopeFingerprint;
  final String existingMemoryId;
  final String proposedMemoryId;
  final String canonicalKey;
  final int expectedExistingRevision;
  final int expectedProposedRevision;
  final String contradictionId;
  final MemoryContradictionReasonCode reasonCode;
  final MemoryReplacementActionState state;
  final String logicalRequestFingerprint;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? executedAt;
  final MemoryReplacementExecutionCode? executionCode;
  final int? finalExistingRevision;
  final int? finalProposedRevision;
  final int schemaVersion;

  MemoryReplacementPendingAction withState(
    MemoryReplacementActionState next,
    DateTime at,
  ) =>
      MemoryReplacementPendingAction(
        actionId: actionId,
        actionType: actionType,
        accountScopeFingerprint: accountScopeFingerprint,
        existingMemoryId: existingMemoryId,
        proposedMemoryId: proposedMemoryId,
        canonicalKey: canonicalKey,
        expectedExistingRevision: expectedExistingRevision,
        expectedProposedRevision: expectedProposedRevision,
        contradictionId: contradictionId,
        reasonCode: reasonCode,
        state: next,
        logicalRequestFingerprint: logicalRequestFingerprint,
        createdAt: createdAt,
        updatedAt: at.toUtc(),
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'actionId': actionId,
        'actionType': actionType.name,
        'accountScopeFingerprint': accountScopeFingerprint,
        'existingMemoryId': existingMemoryId,
        'proposedMemoryId': proposedMemoryId,
        'canonicalKey': canonicalKey,
        'expectedExistingRevision': expectedExistingRevision,
        'expectedProposedRevision': expectedProposedRevision,
        'contradictionId': contradictionId,
        'reasonCode': reasonCode.name,
        'state': state.name,
        'logicalRequestFingerprint': logicalRequestFingerprint,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (executedAt != null) 'executedAt': executedAt!.toIso8601String(),
        if (executionCode != null) 'executionCode': executionCode!.name,
        if (finalExistingRevision != null)
          'finalExistingRevision': finalExistingRevision,
        if (finalProposedRevision != null)
          'finalProposedRevision': finalProposedRevision,
      };

  factory MemoryReplacementPendingAction.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('invalid_memory_replacement_pending_action');
    }
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'invalid_memory_replacement_pending_action',
        );
      }
      map[entry.key as String] = entry.value;
    }
    T parseEnum<T extends Enum>(List<T> values, String field) {
      final raw = map[field];
      if (raw is! String) {
        throw const FormatException(
          'invalid_memory_replacement_pending_action',
        );
      }
      return values.where((item) => item.name == raw).firstOrNull ??
          (throw const FormatException(
            'invalid_memory_replacement_pending_action',
          ));
    }

    final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    final executedAt = map['executedAt'] == null
        ? null
        : DateTime.tryParse(map['executedAt']?.toString() ?? '');
    if (createdAt == null ||
        updatedAt == null ||
        (map.containsKey('executedAt') && executedAt == null)) {
      throw const FormatException('invalid_memory_replacement_pending_action');
    }
    return MemoryReplacementPendingAction(
      actionId: map['actionId']?.toString() ?? '',
      actionType: parseEnum(MemoryReplacementActionType.values, 'actionType'),
      accountScopeFingerprint: map['accountScopeFingerprint']?.toString() ?? '',
      existingMemoryId: map['existingMemoryId']?.toString() ?? '',
      proposedMemoryId: map['proposedMemoryId']?.toString() ?? '',
      canonicalKey: map['canonicalKey']?.toString() ?? '',
      expectedExistingRevision: map['expectedExistingRevision'] is int
          ? map['expectedExistingRevision'] as int
          : 0,
      expectedProposedRevision: map['expectedProposedRevision'] is int
          ? map['expectedProposedRevision'] as int
          : 0,
      contradictionId: map['contradictionId']?.toString() ?? '',
      reasonCode: parseEnum(MemoryContradictionReasonCode.values, 'reasonCode'),
      state: parseEnum(MemoryReplacementActionState.values, 'state'),
      logicalRequestFingerprint:
          map['logicalRequestFingerprint']?.toString() ?? '',
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      executedAt: executedAt?.toUtc(),
      executionCode: map['executionCode'] == null
          ? null
          : parseEnum(
              MemoryReplacementExecutionCode.values,
              'executionCode',
            ),
      finalExistingRevision: map['finalExistingRevision'] is int
          ? map['finalExistingRevision'] as int
          : null,
      finalProposedRevision: map['finalProposedRevision'] is int
          ? map['finalProposedRevision'] as int
          : null,
      schemaVersion:
          map['schemaVersion'] is int ? map['schemaVersion'] as int : 0,
    );
  }

  static bool _fingerprint(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
}
