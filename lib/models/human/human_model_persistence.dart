import 'human_model.dart';

enum HumanModelSyncStatus {
  synced,
  localOnly,
  pendingUpload,
  remoteChanged,
  migrationFailed,
  corruptedLocal,
  unsupportedVersion,
}

enum HumanModelMigrationStatus { pending, complete, failed }

enum HumanModelWriteStatus {
  success,
  notFound,
  alreadyExists,
  revisionConflict,
  scopeMismatch,
  invalidModel,
  unavailable,
  persistenceFailure,
}

enum HumanModelBootstrapStatus {
  restoredFromCloud,
  uploadedLocalModel,
  migratedLegacyProfile,
  localFallback,
  absent,
  conflict,
  failure,
}

final class RevisionedHumanModel {
  RevisionedHumanModel({
    required this.model,
    required this.modelRevision,
    required this.lastMutationId,
    required this.migrationVersion,
    required this.migrationStatus,
  }) {
    model.validate();
    if (modelRevision < 1) {
      throw const HumanModelException('invalid_human_model_revision');
    }
    if (lastMutationId.trim().isEmpty) {
      throw const HumanModelException('invalid_human_mutation_id');
    }
    if (migrationVersion < 1) {
      throw const HumanModelException('invalid_human_migration_version');
    }
  }

  final HumanModel model;
  final int modelRevision;
  final String lastMutationId;
  final int migrationVersion;
  final HumanModelMigrationStatus migrationStatus;
}

final class PendingHumanModelMutation {
  PendingHumanModelMutation({
    required this.mutationId,
    required this.expectedRevision,
    required this.proposed,
    required this.createdAt,
  }) {
    if (mutationId.trim().isEmpty) {
      throw const HumanModelException('invalid_human_mutation_id');
    }
    if (expectedRevision < 1) {
      throw const HumanModelException('invalid_human_model_revision');
    }
    proposed.validate();
  }

  final String mutationId;
  final int expectedRevision;
  final HumanModel proposed;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'mutationId': mutationId,
        'expectedRevision': expectedRevision,
        'proposed': proposed.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory PendingHumanModelMutation.fromJson(Object? value) {
    final map = _map(value, 'invalid_pending_human_mutation');
    return PendingHumanModelMutation(
      mutationId: _string(map['mutationId'], 'invalid_human_mutation_id'),
      expectedRevision:
          _integer(map['expectedRevision'], 'invalid_human_model_revision'),
      proposed: HumanModel.fromJson(map['proposed']),
      createdAt: _date(map['createdAt'], 'invalid_human_mutation_date'),
    );
  }
}

final class HumanModelLocalState {
  static const currentStorageVersion = 1;

  HumanModelLocalState({
    this.storageVersion = currentStorageVersion,
    required this.model,
    this.knownCloudRevision,
    required this.syncStatus,
    this.lastMutationId,
    this.pendingMutation,
    required this.migrationStatus,
  }) {
    model.validate();
    if (storageVersion != currentStorageVersion) {
      throw const HumanModelException('unsupported_human_local_state_version');
    }
    if (knownCloudRevision != null && knownCloudRevision! < 1) {
      throw const HumanModelException('invalid_human_model_revision');
    }
    if (pendingMutation != null &&
        pendingMutation!.proposed.accountScopeId != model.accountScopeId) {
      throw const HumanModelException('human_model_scope_mismatch');
    }
    if (syncStatus == HumanModelSyncStatus.synced &&
        knownCloudRevision == null) {
      throw const HumanModelException('synced_human_model_requires_revision');
    }
  }

  final int storageVersion;
  final HumanModel model;
  final int? knownCloudRevision;
  final HumanModelSyncStatus syncStatus;
  final String? lastMutationId;
  final PendingHumanModelMutation? pendingMutation;
  final HumanModelMigrationStatus migrationStatus;

  HumanModelLocalState copyWith({
    HumanModel? model,
    int? knownCloudRevision,
    bool clearKnownCloudRevision = false,
    HumanModelSyncStatus? syncStatus,
    String? lastMutationId,
    bool clearLastMutationId = false,
    PendingHumanModelMutation? pendingMutation,
    bool clearPendingMutation = false,
    HumanModelMigrationStatus? migrationStatus,
  }) {
    return HumanModelLocalState(
      model: model ?? this.model,
      knownCloudRevision: clearKnownCloudRevision
          ? null
          : (knownCloudRevision ?? this.knownCloudRevision),
      syncStatus: syncStatus ?? this.syncStatus,
      lastMutationId:
          clearLastMutationId ? null : (lastMutationId ?? this.lastMutationId),
      pendingMutation: clearPendingMutation
          ? null
          : (pendingMutation ?? this.pendingMutation),
      migrationStatus: migrationStatus ?? this.migrationStatus,
    );
  }

  Map<String, Object?> toJson() => {
        'storageVersion': storageVersion,
        'model': model.toJson(),
        'knownCloudRevision': knownCloudRevision,
        'syncStatus': syncStatus.name,
        'lastMutationId': lastMutationId,
        'pendingMutation': pendingMutation?.toJson(),
        'migrationStatus': migrationStatus.name,
      };

  factory HumanModelLocalState.fromJson(Object? value) {
    final map = _map(value, 'invalid_human_local_state');
    final version =
        _integer(map['storageVersion'], 'invalid_human_local_state_version');
    if (version != currentStorageVersion) {
      throw const HumanModelException('unsupported_human_local_state_version');
    }
    return HumanModelLocalState(
      storageVersion: version,
      model: HumanModel.fromJson(map['model']),
      knownCloudRevision: _optionalInteger(map['knownCloudRevision']),
      syncStatus: _enum(
        HumanModelSyncStatus.values,
        map['syncStatus'],
        'invalid_human_sync_status',
      ),
      lastMutationId: _optionalString(map['lastMutationId']),
      pendingMutation: map['pendingMutation'] == null
          ? null
          : PendingHumanModelMutation.fromJson(map['pendingMutation']),
      migrationStatus: _enum(
        HumanModelMigrationStatus.values,
        map['migrationStatus'],
        'invalid_human_migration_status',
      ),
    );
  }
}

final class HumanModelWriteResult {
  const HumanModelWriteResult._(this.status, this.value);

  const HumanModelWriteResult.success(RevisionedHumanModel value)
      : this._(HumanModelWriteStatus.success, value);
  const HumanModelWriteResult.status(HumanModelWriteStatus status)
      : this._(status, null);

  final HumanModelWriteStatus status;
  final RevisionedHumanModel? value;

  bool get isSuccess =>
      status == HumanModelWriteStatus.success && value != null;
}

final class HumanModelBootstrapResult {
  const HumanModelBootstrapResult({
    required this.status,
    this.state,
    this.errorCode,
  });

  final HumanModelBootstrapStatus status;
  final HumanModelLocalState? state;
  final String? errorCode;
}

Map<String, Object?> _map(Object? value, String code) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw HumanModelException(code);
  }
  return Map<String, Object?>.from(value);
}

String _string(Object? value, String code) {
  if (value is! String || value.trim().isEmpty) {
    throw HumanModelException(code);
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  return _string(value, 'invalid_optional_human_string');
}

int _integer(Object? value, String code) {
  if (value is! int) throw HumanModelException(code);
  return value;
}

int? _optionalInteger(Object? value) {
  if (value == null) return null;
  return _integer(value, 'invalid_optional_human_integer');
}

DateTime _date(Object? value, String code) {
  if (value is! String) throw HumanModelException(code);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw HumanModelException(code);
  return parsed.toUtc();
}

T _enum<T extends Enum>(List<T> values, Object? value, String code) {
  if (value is String) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
  }
  throw HumanModelException(code);
}
