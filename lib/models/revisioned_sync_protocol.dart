enum RevisionedSyncDomain { task, shopping, profile }

enum RevisionedSyncStatus {
  synced,
  queued,
  sending,
  retryScheduled,
  blockedByConflict,
  blockedByPolicy,
  unavailable,
  corrupted,
}

enum RevisionedMutationState {
  queued,
  sending,
  retryScheduled,
  blockedByConflict,
  blockedByPolicy,
  completed,
  abandoned,
  corrupted,
}

enum RevisionedConflictType {
  revisionConflict,
  contentConflict,
  deletionConflict,
  completionConflict,
  listConflict,
  profileFieldConflict,
  canonicalOwnershipConflict,
  accountMismatch,
  unsupportedVersion,
  corruptedLocal,
  corruptedRemote,
}

enum RevisionedConflictStatus { unresolved, resolved, abandoned }

enum RevisionedConflictResolution {
  keepRemote,
  discardLocalMutation,
  retryAgainstLatest,
  requireUserResolution,
  applyDeterministicNonConflictingPatch,
  cancelDeletedTarget,
}

enum RevisionedCloudWriteStatus {
  success,
  idempotent,
  revisionConflict,
  mutationConflict,
  accountMismatch,
  notFound,
  unavailable,
  corrupted,
}

final class RevisionedCloudWriteResult<T> {
  const RevisionedCloudWriteResult(this.status, {this.value});

  final RevisionedCloudWriteStatus status;
  final T? value;
}

final class RevisionedConflict {
  static const currentSchemaVersion = 1;

  RevisionedConflict({
    this.schemaVersion = currentSchemaVersion,
    required this.conflictId,
    required this.domain,
    required this.targetId,
    required this.mutationId,
    required this.expectedRevision,
    required this.remoteRevision,
    required this.type,
    this.status = RevisionedConflictStatus.unresolved,
    required this.createdAt,
    required this.allowedResolutions,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        conflictId.trim().isEmpty ||
        targetId.trim().isEmpty ||
        mutationId.trim().isEmpty ||
        expectedRevision < 0 ||
        remoteRevision < 0 ||
        allowedResolutions.isEmpty ||
        allowedResolutions.length > 6) {
      throw const FormatException('invalid_revisioned_conflict');
    }
  }

  final int schemaVersion;
  final String conflictId;
  final RevisionedSyncDomain domain;
  final String targetId;
  final String mutationId;
  final int expectedRevision;
  final int remoteRevision;
  final RevisionedConflictType type;
  final RevisionedConflictStatus status;
  final DateTime createdAt;
  final List<RevisionedConflictResolution> allowedResolutions;

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'conflictId': conflictId,
        'domain': domain.name,
        'targetId': targetId,
        'mutationId': mutationId,
        'expectedRevision': expectedRevision,
        'remoteRevision': remoteRevision,
        'type': type.name,
        'status': status.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'allowedResolutions':
            allowedResolutions.map((value) => value.name).toList(),
      };

  factory RevisionedConflict.fromJson(Map<String, dynamic> json) {
    T parse<T extends Enum>(List<T> values, Object? raw) => values.singleWhere(
          (value) => value.name == raw,
          orElse: () => throw const FormatException(
            'unknown_revisioned_conflict_value',
          ),
        );
    return RevisionedConflict(
      schemaVersion: json['schemaVersion'] as int? ?? -1,
      conflictId: json['conflictId'] as String? ?? '',
      domain: parse(RevisionedSyncDomain.values, json['domain']),
      targetId: json['targetId'] as String? ?? '',
      mutationId: json['mutationId'] as String? ?? '',
      expectedRevision: json['expectedRevision'] as int? ?? -1,
      remoteRevision: json['remoteRevision'] as int? ?? -1,
      type: parse(RevisionedConflictType.values, json['type']),
      status: parse(RevisionedConflictStatus.values, json['status']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      allowedResolutions: (json['allowedResolutions'] as List<dynamic>)
          .map(
            (value) => parse(
              RevisionedConflictResolution.values,
              value,
            ),
          )
          .toList(growable: false),
    );
  }
}

final class RevisionedActionReference {
  const RevisionedActionReference({
    required this.actionType,
    required this.pendingActionId,
    required this.policyMode,
    required this.policyVersion,
    required this.sessionGeneration,
    required this.origin,
  });

  final String actionType;
  final String? pendingActionId;
  final String policyMode;
  final int policyVersion;
  final int sessionGeneration;
  final String origin;

  Map<String, Object?> toJson() => {
        'actionType': actionType,
        'pendingActionId': pendingActionId,
        'policyMode': policyMode,
        'policyVersion': policyVersion,
        'sessionGeneration': sessionGeneration,
        'origin': origin,
      };
}
