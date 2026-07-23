import 'dart:collection';

import 'life_context/life_context_provenance.dart';
import 'life_context/memory_context.dart';
import 'memory_lifecycle_state.dart';
import 'memory_policy.dart';

final class MemorySyncException implements Exception {
  const MemorySyncException(this.code);
  final String code;
}

enum MemorySyncStatus {
  synced,
  localOnly,
  pending,
  retryScheduled,
  conflict,
  blockedByPolicy,
  unavailable,
  corrupted,
}

enum MemoryMutationType {
  createMemory,
  updateMemory,
  confirmMemory,
  rejectMemory,
  postponeMemory,
  expireMemory,
  archiveMemory,
  changePolicy,
}

enum MemoryMutationState {
  queued,
  sending,
  retryScheduled,
  blockedByConflict,
  blockedByPolicy,
  completed,
  abandoned,
}

enum MemoryConflictType {
  revisionConflict,
  contentConflict,
  confirmationConflict,
  policyConflict,
  expirationConflict,
  deletionConflict,
  structuredDomainConflict,
  accountMismatch,
  unsupportedVersion,
  corruptedRemote,
}

enum MemoryConflictResolution {
  keepRemote,
  retryAgainstLatest,
  discardLocalMutation,
  requireUserResolution,
  applyNonConflictingPatch,
  cancelExpiredMutation,
}

final class RevisionedMemory {
  static const currentSchemaVersion = 1;

  RevisionedMemory({
    this.schemaVersion = currentSchemaVersion,
    required this.memoryId,
    required this.accountScopeId,
    required this.memoryRevision,
    required this.lifecycleStatus,
    required this.confirmationStatus,
    required this.provenance,
    required this.sensitivity,
    required this.category,
    required this.isHealth,
    required this.text,
    required this.normalizedText,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMutationId,
    this.validFrom,
    this.validUntil,
    this.expiresAt,
    this.structuredDomain,
    this.structuredReferenceId,
    this.tombstone = false,
  }) {
    validate();
  }

  final int schemaVersion;
  final String memoryId;
  final String accountScopeId;
  final int memoryRevision;
  final MemoryLifecycleState lifecycleStatus;
  final MemoryConfirmationStatus confirmationStatus;
  final LifeContextSourceType provenance;
  final LifeContextSensitivity sensitivity;
  final String category;
  final bool isHealth;
  final String text;
  final String normalizedText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? expiresAt;
  final String? structuredDomain;
  final String? structuredReferenceId;
  final String lastMutationId;
  final bool tombstone;

  bool isExpiredAt(DateTime date) {
    final end = expiresAt ?? validUntil;
    return lifecycleStatus == MemoryLifecycleState.expired ||
        (end != null && !date.toUtc().isBefore(end.toUtc()));
  }

  void validate() {
    if (schemaVersion != currentSchemaVersion ||
        memoryId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        memoryRevision < 1 ||
        lastMutationId.trim().isEmpty ||
        lastMutationId.length > 128 ||
        text.length > 4000 ||
        normalizedText.length > 4000 ||
        (validFrom != null &&
            validUntil != null &&
            validUntil!.isBefore(validFrom!))) {
      throw const MemorySyncException('invalid_revisioned_memory');
    }
  }

  RevisionedMemory copyWith({
    int? memoryRevision,
    MemoryLifecycleState? lifecycleStatus,
    MemoryConfirmationStatus? confirmationStatus,
    DateTime? updatedAt,
    String? lastMutationId,
    bool? tombstone,
  }) =>
      RevisionedMemory(
        schemaVersion: schemaVersion,
        memoryId: memoryId,
        accountScopeId: accountScopeId,
        memoryRevision: memoryRevision ?? this.memoryRevision,
        lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
        confirmationStatus: confirmationStatus ?? this.confirmationStatus,
        provenance: provenance,
        sensitivity: sensitivity,
        category: category,
        isHealth: isHealth,
        text: text,
        normalizedText: normalizedText,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        validFrom: validFrom,
        validUntil: validUntil,
        expiresAt: expiresAt,
        structuredDomain: structuredDomain,
        structuredReferenceId: structuredReferenceId,
        lastMutationId: lastMutationId ?? this.lastMutationId,
        tombstone: tombstone ?? this.tombstone,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'memoryId': memoryId,
        'accountScopeId': accountScopeId,
        'memoryRevision': memoryRevision,
        'lifecycleStatus': lifecycleStatus.name,
        'confirmationStatus': confirmationStatus.name,
        'provenance': provenance.name,
        'sensitivity': sensitivity.name,
        'category': category,
        'isHealth': isHealth,
        'text': text,
        'normalizedText': normalizedText,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (validFrom != null)
          'validFrom': validFrom!.toUtc().toIso8601String(),
        if (validUntil != null)
          'validUntil': validUntil!.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
        if (structuredDomain != null) 'structuredDomain': structuredDomain,
        if (structuredReferenceId != null)
          'structuredReferenceId': structuredReferenceId,
        'lastMutationId': lastMutationId,
        'tombstone': tombstone,
      };

  factory RevisionedMemory.fromJson(
    Map<String, Object?> json, {
    required String expectedScope,
    String? expectedId,
  }) {
    final memory = RevisionedMemory(
      schemaVersion: _int(json['schemaVersion']),
      memoryId: _string(json['memoryId']),
      accountScopeId: _string(json['accountScopeId']),
      memoryRevision: _int(json['memoryRevision']),
      lifecycleStatus: _enum(MemoryLifecycleState.values,
          json['lifecycleStatus'], 'invalid_memory_status'),
      confirmationStatus: _enum(MemoryConfirmationStatus.values,
          json['confirmationStatus'], 'invalid_memory_confirmation'),
      provenance: _enum(LifeContextSourceType.values, json['provenance'],
          'invalid_memory_provenance'),
      sensitivity: _enum(LifeContextSensitivity.values, json['sensitivity'],
          'invalid_memory_sensitivity'),
      category: _string(json['category']),
      isHealth: json['isHealth'] is bool
          ? json['isHealth']! as bool
          : throw const MemorySyncException('invalid_memory_health'),
      text: _string(json['text']),
      normalizedText: _string(json['normalizedText']),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      validFrom: _optionalDate(json['validFrom']),
      validUntil: _optionalDate(json['validUntil']),
      expiresAt: _optionalDate(json['expiresAt']),
      structuredDomain: _optionalString(json['structuredDomain']),
      structuredReferenceId: _optionalString(json['structuredReferenceId']),
      lastMutationId: _string(json['lastMutationId']),
      tombstone: json['tombstone'] == true,
    );
    if (memory.accountScopeId != expectedScope ||
        (expectedId != null && memory.memoryId != expectedId)) {
      throw const MemorySyncException('memory_account_mismatch');
    }
    return memory;
  }
}

final class RevisionedMemoryPolicy {
  RevisionedMemoryPolicy({
    required this.policy,
    required this.policyRevision,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMutationId,
    this.explicitHealthConsentAt,
  }) {
    policy.validate();
    if (policyRevision < 1 ||
        lastMutationId.trim().isEmpty ||
        lastMutationId.length > 128) {
      throw const MemorySyncException('invalid_revisioned_memory_policy');
    }
  }

  final MemoryPolicy policy;
  final int policyRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? explicitHealthConsentAt;
  final String lastMutationId;

  Map<String, Object?> toJson() => {
        ...policy.toJson(),
        'policyRevision': policyRevision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (explicitHealthConsentAt != null)
          'explicitHealthConsentAt':
              explicitHealthConsentAt!.toUtc().toIso8601String(),
        'lastMutationId': lastMutationId,
      };
}

final class MemorySyncMutation {
  MemorySyncMutation({
    required this.mutationId,
    required this.accountScopeId,
    required this.type,
    required this.targetId,
    required this.expectedRevision,
    required this.createdAt,
    required this.observedGeneralMode,
    required this.observedHealthMode,
    required this.isHealth,
    required this.provenance,
    this.state = MemoryMutationState.queued,
    this.attempt = 0,
    this.nextRetryAt,
    Map<String, Object?> patch = const {},
  }) : patch = UnmodifiableMapView(Map.of(patch)) {
    if (mutationId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        targetId.trim().isEmpty ||
        expectedRevision < 0 ||
        attempt < 0 ||
        patch.length > 20) {
      throw const MemorySyncException('invalid_memory_mutation');
    }
  }

  final String mutationId;
  final String accountScopeId;
  final MemoryMutationType type;
  final String targetId;
  final int expectedRevision;
  final DateTime createdAt;
  final int attempt;
  final DateTime? nextRetryAt;
  final MemoryGeneralMode observedGeneralMode;
  final MemoryHealthMode observedHealthMode;
  final bool isHealth;
  final LifeContextSourceType provenance;
  final MemoryMutationState state;
  final Map<String, Object?> patch;

  MemorySyncMutation copyWith({
    int? expectedRevision,
    int? attempt,
    DateTime? nextRetryAt,
    bool clearNextRetry = false,
    MemoryMutationState? state,
    Map<String, Object?>? patch,
  }) =>
      MemorySyncMutation(
        mutationId: mutationId,
        accountScopeId: accountScopeId,
        type: type,
        targetId: targetId,
        expectedRevision: expectedRevision ?? this.expectedRevision,
        createdAt: createdAt,
        attempt: attempt ?? this.attempt,
        nextRetryAt: clearNextRetry ? null : (nextRetryAt ?? this.nextRetryAt),
        observedGeneralMode: observedGeneralMode,
        observedHealthMode: observedHealthMode,
        isHealth: isHealth,
        provenance: provenance,
        state: state ?? this.state,
        patch: patch ?? this.patch,
      );

  Map<String, Object?> toJson() => {
        'mutationId': mutationId,
        'accountScopeId': accountScopeId,
        'type': type.name,
        'targetId': targetId,
        'expectedRevision': expectedRevision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempt': attempt,
        if (nextRetryAt != null)
          'nextRetryAt': nextRetryAt!.toUtc().toIso8601String(),
        'observedGeneralMode': observedGeneralMode.name,
        'observedHealthMode': observedHealthMode.name,
        'isHealth': isHealth,
        'provenance': provenance.name,
        'state': state.name,
        'patch': Map<String, Object?>.from(patch),
      };

  factory MemorySyncMutation.fromJson(Map<String, Object?> json) =>
      MemorySyncMutation(
        mutationId: _string(json['mutationId']),
        accountScopeId: _string(json['accountScopeId']),
        type: _enum(MemoryMutationType.values, json['type'],
            'invalid_memory_mutation_type'),
        targetId: _string(json['targetId']),
        expectedRevision: _int(json['expectedRevision']),
        createdAt: _date(json['createdAt']),
        attempt: _int(json['attempt']),
        nextRetryAt: _optionalDate(json['nextRetryAt']),
        observedGeneralMode: _enum(MemoryGeneralMode.values,
            json['observedGeneralMode'], 'invalid_memory_general_mode'),
        observedHealthMode: _enum(MemoryHealthMode.values,
            json['observedHealthMode'], 'invalid_memory_health_mode'),
        isHealth: json['isHealth'] == true,
        provenance: _enum(LifeContextSourceType.values, json['provenance'],
            'invalid_memory_provenance'),
        state: _enum(MemoryMutationState.values, json['state'],
            'invalid_memory_mutation_state'),
        patch: json['patch'] is Map
            ? Map<String, Object?>.from(json['patch']! as Map)
            : const {},
      );
}

final class MemorySyncConflict {
  const MemorySyncConflict({
    required this.id,
    required this.targetId,
    required this.mutationId,
    required this.expectedRevision,
    required this.remoteRevision,
    required this.type,
    required this.createdAt,
    this.resolution = MemoryConflictResolution.requireUserResolution,
  });
  final String id;
  final String targetId;
  final String mutationId;
  final int expectedRevision;
  final int? remoteRevision;
  final MemoryConflictType type;
  final DateTime createdAt;
  final MemoryConflictResolution resolution;

  Map<String, Object?> toJson() => {
        'id': id,
        'targetId': targetId,
        'mutationId': mutationId,
        'expectedRevision': expectedRevision,
        'remoteRevision': remoteRevision,
        'type': type.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'resolution': resolution.name,
      };

  factory MemorySyncConflict.fromJson(Map<String, Object?> json) =>
      MemorySyncConflict(
        id: _string(json['id']),
        targetId: _string(json['targetId']),
        mutationId: _string(json['mutationId']),
        expectedRevision: _int(json['expectedRevision']),
        remoteRevision: json['remoteRevision'] == null
            ? null
            : _int(json['remoteRevision']),
        type: _enum(
          MemoryConflictType.values,
          json['type'],
          'invalid_memory_conflict_type',
        ),
        createdAt: _date(json['createdAt']),
        resolution: _enum(
          MemoryConflictResolution.values,
          json['resolution'],
          'invalid_memory_conflict_resolution',
        ),
      );
}

enum MemoryCloudWriteStatus {
  success,
  idempotentSuccess,
  revisionConflict,
  mutationMismatch,
  notFound,
  scopeMismatch,
  invalid,
  unavailable,
}

final class MemoryCloudWriteResult {
  const MemoryCloudWriteResult(this.status, {this.memory, this.policy});
  final MemoryCloudWriteStatus status;
  final RevisionedMemory? memory;
  final RevisionedMemoryPolicy? policy;
}

T _enum<T extends Enum>(List<T> values, Object? raw, String code) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw MemorySyncException(code);
}

String _string(Object? value) => value is String
    ? value
    : throw const MemorySyncException('invalid_memory_field');
String? _optionalString(Object? value) => value == null ? null : _string(value);
int _int(Object? value) => value is int
    ? value
    : throw const MemorySyncException('invalid_memory_int');
DateTime _date(Object? value) {
  if (value is DateTime) return value.toUtc();
  final dynamic candidate = value;
  try {
    final converted = candidate?.toDate();
    if (converted is DateTime) return converted.toUtc();
  } on Object {
    // Continue with the stable string representation.
  }
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) throw const MemorySyncException('invalid_memory_date');
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value) => value == null ? null : _date(value);
