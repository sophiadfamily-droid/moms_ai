import 'shopping_item_model.dart';
import 'task_model.dart';
import 'user_profile.dart';
import 'revisioned_sync_protocol.dart';

enum TaskMutationType {
  createTask,
  updateTask,
  completeTask,
  reopenTask,
  archiveTask,
  deleteTask,
  restoreTask,
}

enum ShoppingMutationType {
  addItem,
  updateItem,
  removeItem,
  restoreItem,
  clearList,
}

enum ProfileMutationType {
  updateProfileFields,
  updatePlanningPreferences,
  updateWorkInformation,
  updateCompatibilityProjection,
}

final class RevisionedTask {
  static const currentSchemaVersion = 1;

  RevisionedTask({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.entityId,
    required this.task,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMutationId,
    this.syncStatus = RevisionedSyncStatus.synced,
    this.isTombstone = false,
    this.legacyProvenance,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        entityId.trim().isEmpty ||
        task.id != entityId ||
        revision < 1 ||
        lastMutationId.trim().isEmpty ||
        updatedAt.isBefore(createdAt)) {
      throw const FormatException('invalid_revisioned_task');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final String entityId;
  final TaskModel task;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMutationId;
  final RevisionedSyncStatus syncStatus;
  final bool isTombstone;
  final String? legacyProvenance;

  RevisionedTask copyWith({
    TaskModel? task,
    int? revision,
    DateTime? updatedAt,
    String? lastMutationId,
    RevisionedSyncStatus? syncStatus,
    bool? isTombstone,
  }) =>
      RevisionedTask(
        accountScopeId: accountScopeId,
        entityId: entityId,
        task: task ?? this.task,
        revision: revision ?? this.revision,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastMutationId: lastMutationId ?? this.lastMutationId,
        syncStatus: syncStatus ?? this.syncStatus,
        isTombstone: isTombstone ?? this.isTombstone,
        legacyProvenance: legacyProvenance,
      );

  Map<String, Object?> toJson({bool includeScope = true}) => {
        'schemaVersion': schemaVersion,
        if (includeScope) 'accountScopeId': accountScopeId,
        'entityId': entityId,
        'payload': task.toJson(),
        'revision': revision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastMutationId': lastMutationId,
        'syncStatus': syncStatus.name,
        'isTombstone': isTombstone,
        if (legacyProvenance != null) 'legacyProvenance': legacyProvenance,
      };

  factory RevisionedTask.fromJson(Map<String, dynamic> json) => RevisionedTask(
        schemaVersion: json['schemaVersion'] as int? ?? -1,
        accountScopeId: json['accountScopeId'] as String? ?? '',
        entityId: json['entityId'] as String? ?? '',
        task: TaskModel.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
        revision: json['revision'] as int? ?? -1,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastMutationId: json['lastMutationId'] as String? ?? '',
        syncStatus: RevisionedSyncStatus.values.singleWhere(
          (value) => value.name == json['syncStatus'],
        ),
        isTombstone: json['isTombstone'] as bool? ?? false,
        legacyProvenance: json['legacyProvenance'] as String?,
      );
}

final class RevisionedShoppingItem {
  static const currentSchemaVersion = 1;

  RevisionedShoppingItem({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.entityId,
    required this.item,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMutationId,
    this.syncStatus = RevisionedSyncStatus.synced,
    this.isTombstone = false,
    this.clearGeneration = 0,
    this.legacyProvenance,
  }) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        entityId.trim().isEmpty ||
        item.id != entityId ||
        revision < 1 ||
        clearGeneration < 0 ||
        lastMutationId.trim().isEmpty ||
        updatedAt.isBefore(createdAt)) {
      throw const FormatException('invalid_revisioned_shopping_item');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final String entityId;
  final ShoppingItemModel item;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMutationId;
  final RevisionedSyncStatus syncStatus;
  final bool isTombstone;
  final int clearGeneration;
  final String? legacyProvenance;

  Map<String, Object?> toJson({bool includeScope = true}) => {
        'schemaVersion': schemaVersion,
        if (includeScope) 'accountScopeId': accountScopeId,
        'entityId': entityId,
        'payload': item.toJson(),
        'revision': revision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastMutationId': lastMutationId,
        'syncStatus': syncStatus.name,
        'isTombstone': isTombstone,
        'clearGeneration': clearGeneration,
        if (legacyProvenance != null) 'legacyProvenance': legacyProvenance,
      };

  factory RevisionedShoppingItem.fromJson(Map<String, dynamic> json) =>
      RevisionedShoppingItem(
        schemaVersion: json['schemaVersion'] as int? ?? -1,
        accountScopeId: json['accountScopeId'] as String? ?? '',
        entityId: json['entityId'] as String? ?? '',
        item: ShoppingItemModel.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
        revision: json['revision'] as int? ?? -1,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastMutationId: json['lastMutationId'] as String? ?? '',
        syncStatus: RevisionedSyncStatus.values.singleWhere(
          (value) => value.name == json['syncStatus'],
        ),
        isTombstone: json['isTombstone'] as bool? ?? false,
        clearGeneration: json['clearGeneration'] as int? ?? 0,
        legacyProvenance: json['legacyProvenance'] as String?,
      );
}

abstract final class ProfileFieldOwnership {
  static const humanModelFields = {
    'humanPersonId',
    'partnerHumanPersonId',
    'firstName',
    'familyStatus',
    'partnerName',
    'children',
    'age',
    'birthDate',
    'partnerBirthDate',
    'relationshipStatus',
    'marriageDate',
    'engagementDate',
  };

  static const profileOwnedFields = {
    'workStatus',
    'wantsNotifications',
    'workHours',
    'workScheduleType',
    'workDays',
    'morningStart',
    'morningEnd',
    'afternoonStart',
    'afternoonEnd',
    'variableWorkDetails',
    'workTimeRanges',
    'habits',
    'personalNotes',
    'preferences',
    'goals',
    'aiTone',
    'planningStyle',
    'notificationLevel',
    'mainLifePriority',
    'spokenLanguage',
    'country',
    'timeZone',
    'personalGoals',
    'businessGoals',
    'familyGoals',
    'vehicleInfo',
    'petsInfo',
    'transportInfo',
    'childcareInfo',
    'foodPreferences',
    'adminNotes',
    'budgetNotes',
    'importantPlaces',
    'personalActivities',
  };

  static void validatePatch(Iterable<String> fields) {
    for (final field in fields) {
      if (humanModelFields.contains(field)) {
        throw const FormatException('profile_canonical_ownership_conflict');
      }
      if (!profileOwnedFields.contains(field)) {
        throw const FormatException('profile_field_not_owned');
      }
    }
  }

  static Map<String, dynamic> ownedPayload(UserProfile profile) {
    final json = profile.toJson();
    return {
      for (final field in profileOwnedFields)
        if (json.containsKey(field)) field: json[field],
      ...profile.legacyExtensions,
    };
  }
}

final class RevisionedProfileState {
  static const currentSchemaVersion = 1;
  static const entityId = 'profile';

  RevisionedProfileState({
    this.schemaVersion = currentSchemaVersion,
    required this.accountScopeId,
    required this.profile,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMutationId,
    this.syncStatus = RevisionedSyncStatus.synced,
    this.legacyExtensions = const {},
    this.projectionProvenance = 'profileOwned',
  }) {
    if (schemaVersion != currentSchemaVersion ||
        accountScopeId.trim().isEmpty ||
        revision < 1 ||
        lastMutationId.trim().isEmpty ||
        updatedAt.isBefore(createdAt) ||
        legacyExtensions.length > 64) {
      throw const FormatException('invalid_revisioned_profile');
    }
  }

  final int schemaVersion;
  final String accountScopeId;
  final UserProfile profile;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastMutationId;
  final RevisionedSyncStatus syncStatus;
  final Map<String, dynamic> legacyExtensions;
  final String projectionProvenance;

  Map<String, Object?> toJson({bool includeScope = true}) => {
        'schemaVersion': schemaVersion,
        if (includeScope) 'accountScopeId': accountScopeId,
        'entityId': entityId,
        'payload': ProfileFieldOwnership.ownedPayload(profile),
        'profileRevision': revision,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastMutationId': lastMutationId,
        'syncStatus': syncStatus.name,
        'legacyExtensions': legacyExtensions,
        'projectionProvenance': projectionProvenance,
      };

  factory RevisionedProfileState.fromJson(Map<String, dynamic> json) =>
      RevisionedProfileState(
        schemaVersion: json['schemaVersion'] as int? ?? -1,
        accountScopeId: json['accountScopeId'] as String? ?? '',
        profile: UserProfile.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
        revision: json['profileRevision'] as int? ?? -1,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        lastMutationId: json['lastMutationId'] as String? ?? '',
        syncStatus: RevisionedSyncStatus.values.singleWhere(
          (value) => value.name == json['syncStatus'],
        ),
        legacyExtensions: Map<String, dynamic>.from(
          json['legacyExtensions'] as Map? ?? const {},
        ),
        projectionProvenance:
            json['projectionProvenance'] as String? ?? 'profileOwned',
      );
}

sealed class RevisionedDomainMutation {
  const RevisionedDomainMutation({
    required this.mutationId,
    required this.targetId,
    required this.expectedRevision,
    required this.createdAt,
    required this.attempt,
    required this.nextRetryAt,
    required this.state,
    this.actionReference,
  });

  final String mutationId;
  final String targetId;
  final int expectedRevision;
  final DateTime createdAt;
  final int attempt;
  final DateTime? nextRetryAt;
  final RevisionedMutationState state;
  final RevisionedActionReference? actionReference;

  RevisionedSyncDomain get domain;
}

final class TaskMutation extends RevisionedDomainMutation {
  const TaskMutation({
    required super.mutationId,
    required super.targetId,
    required super.expectedRevision,
    required super.createdAt,
    required super.attempt,
    required super.nextRetryAt,
    required super.state,
    super.actionReference,
    required this.type,
    required this.task,
  });

  final TaskMutationType type;
  final TaskModel task;

  @override
  RevisionedSyncDomain get domain => RevisionedSyncDomain.task;
}

final class ShoppingMutation extends RevisionedDomainMutation {
  const ShoppingMutation({
    required super.mutationId,
    required super.targetId,
    required super.expectedRevision,
    required super.createdAt,
    required super.attempt,
    required super.nextRetryAt,
    required super.state,
    super.actionReference,
    required this.type,
    required this.item,
    this.clearGeneration = 0,
  });

  final ShoppingMutationType type;
  final ShoppingItemModel item;
  final int clearGeneration;

  @override
  RevisionedSyncDomain get domain => RevisionedSyncDomain.shopping;
}

final class ProfileMutation extends RevisionedDomainMutation {
  ProfileMutation({
    required super.mutationId,
    required super.targetId,
    required super.expectedRevision,
    required super.createdAt,
    required super.attempt,
    required super.nextRetryAt,
    required super.state,
    super.actionReference,
    required this.type,
    required this.changedFields,
    required this.profile,
  }) {
    ProfileFieldOwnership.validatePatch(changedFields);
    if (changedFields.isEmpty || changedFields.length > 32) {
      throw const FormatException('invalid_profile_patch');
    }
  }

  final ProfileMutationType type;
  final Set<String> changedFields;
  final UserProfile profile;

  @override
  RevisionedSyncDomain get domain => RevisionedSyncDomain.profile;
}
