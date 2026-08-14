import 'dart:collection';

enum LifeContextDomain { human, identity, event, task, routine, memory }

enum LifeContextAvailability {
  available,
  availableStale,
  empty,
  unavailable,
  unsupported,
  corrupted,
  accountMismatch,
}

enum LifeContextFreshness { current, stale, unknown }

enum LifeContextTruncationState { complete, truncated }

enum LifeContextSourceKind {
  humanModelLocal,
  identityLinks,
  eventService,
  taskService,
  legacyProfileRoutine,
  memoryFirestore,
}

enum LifeContextGlobalState { complete, partial, unavailable }

final class TaskLifeContextSyncMetadata {
  const TaskLifeContextSyncMetadata({
    required this.revision,
    required this.syncStatus,
    required this.pendingCount,
    required this.hasConflict,
    required this.itemSyncStatuses,
  });

  final int revision;
  final String syncStatus;
  final int pendingCount;
  final bool hasConflict;
  final Map<String, String> itemSyncStatuses;
}

final class LifeContextSourceMetadata {
  const LifeContextSourceMetadata({
    required this.domain,
    required this.source,
    required this.readAt,
    required this.availability,
    required this.freshness,
    required this.isLocal,
    required this.itemCount,
    this.revision,
    this.syncStatus,
    this.errorCode,
    this.truncationState = LifeContextTruncationState.complete,
    this.warningCodes = const [],
  });

  static const int currentSchemaVersion = 1;

  final LifeContextDomain domain;
  final LifeContextSourceKind source;
  final DateTime readAt;
  final LifeContextAvailability availability;
  final LifeContextFreshness freshness;
  final bool isLocal;
  final int itemCount;
  final int? revision;
  final String? syncStatus;
  final String? errorCode;
  final LifeContextTruncationState truncationState;
  final List<String> warningCodes;

  int get schemaVersion => currentSchemaVersion;
  int get entityCount => itemCount;
  int? get sourceRevision => revision;
  DateTime get generatedAt => readAt;
  bool get accountScopeMatch =>
      availability != LifeContextAvailability.accountMismatch;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'domain': domain.name,
        'source': source.name,
        'readAt': readAt.toUtc().toIso8601String(),
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'availability': availability.name,
        'freshness': freshness.name,
        'accountScopeMatch': accountScopeMatch,
        'isLocal': isLocal,
        'itemCount': itemCount,
        'entityCount': entityCount,
        'truncationState': truncationState.name,
        'warningCodes': warningCodes,
        if (revision != null) 'revision': revision,
        if (sourceRevision != null) 'sourceRevision': sourceRevision,
        if (syncStatus != null) 'syncStatus': syncStatus,
        if (errorCode != null) 'errorCode': errorCode,
      };
}

sealed class LifeContextDomainSection {
  const LifeContextDomainSection({required this.metadata});

  static const int currentSchemaVersion = 1;
  final LifeContextSourceMetadata metadata;
  LifeContextDomain get domain => metadata.domain;
  Map<String, Object?> toJson();
}

final class HumanContextPerson {
  const HumanContextPerson({
    required this.id,
    required this.displayName,
    required this.status,
    required this.confirmation,
    this.identityEntityId,
    this.birthDate,
    this.familyStatus,
    this.workStatus,
  });

  final String id;
  final String? displayName;
  final String status;
  final String confirmation;
  final String? identityEntityId;
  final String? birthDate;
  final String? familyStatus;
  final String? workStatus;

  Map<String, Object?> toJson() => {
        'id': id,
        if (displayName != null) 'displayName': displayName,
        'status': status,
        'confirmation': confirmation,
        if (identityEntityId != null) 'identityEntityId': identityEntityId,
        if (birthDate != null) 'birthDate': birthDate,
        if (familyStatus != null) 'familyStatus': familyStatus,
        if (workStatus != null) 'workStatus': workStatus,
      };
}

final class HumanContextRecord {
  const HumanContextRecord({
    required this.id,
    required this.kind,
    required this.references,
    required this.status,
    required this.confirmation,
    this.label,
    this.validFrom,
    this.validUntil,
    this.sourceReferenceId,
    this.targetReferenceId,
    this.householdIds = const [],
    this.personIds = const [],
    this.placeEntityId,
    this.evidenceSource,
    this.reciprocal = false,
    this.relationshipStatus,
    this.marriageDate,
    this.engagementDate,
    this.planningConsequenceType,
    this.planningConsequenceStart,
    this.planningConsequenceEnd,
    this.planningConsequenceWeekdays = const [],
    this.planningConsequenceStartTime,
    this.planningConsequenceEndTime,
    this.blocksResponsiblePerson = false,
  });

  final String id;
  final String kind;
  final List<String> references;
  final String status;
  final String confirmation;
  final String? label;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? sourceReferenceId;
  final String? targetReferenceId;
  final List<String> householdIds;
  final List<String> personIds;
  final String? placeEntityId;
  final String? evidenceSource;
  final bool reciprocal;
  final String? relationshipStatus;
  final String? marriageDate;
  final String? engagementDate;
  final String? planningConsequenceType;
  final DateTime? planningConsequenceStart;
  final DateTime? planningConsequenceEnd;
  final List<int> planningConsequenceWeekdays;
  final String? planningConsequenceStartTime;
  final String? planningConsequenceEndTime;
  final bool blocksResponsiblePerson;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'references': references,
        'status': status,
        'confirmation': confirmation,
        if (label != null) 'label': label,
        if (validFrom != null)
          'validFrom': validFrom!.toUtc().toIso8601String(),
        if (validUntil != null)
          'validUntil': validUntil!.toUtc().toIso8601String(),
        if (sourceReferenceId != null) 'sourceReferenceId': sourceReferenceId,
        if (targetReferenceId != null) 'targetReferenceId': targetReferenceId,
        if (householdIds.isNotEmpty) 'householdIds': householdIds,
        if (personIds.isNotEmpty) 'personIds': personIds,
        if (placeEntityId != null) 'placeEntityId': placeEntityId,
        if (evidenceSource != null) 'evidenceSource': evidenceSource,
        if (reciprocal) 'reciprocal': true,
        if (relationshipStatus != null)
          'relationshipStatus': relationshipStatus,
        if (marriageDate != null) 'marriageDate': marriageDate,
        if (engagementDate != null) 'engagementDate': engagementDate,
        if (planningConsequenceType != null)
          'planningConsequenceType': planningConsequenceType,
        if (planningConsequenceStart != null)
          'planningConsequenceStart':
              planningConsequenceStart!.toUtc().toIso8601String(),
        if (planningConsequenceEnd != null)
          'planningConsequenceEnd':
              planningConsequenceEnd!.toUtc().toIso8601String(),
        if (planningConsequenceWeekdays.isNotEmpty)
          'planningConsequenceWeekdays': planningConsequenceWeekdays,
        if (planningConsequenceStartTime != null)
          'planningConsequenceStartTime': planningConsequenceStartTime,
        if (planningConsequenceEndTime != null)
          'planningConsequenceEndTime': planningConsequenceEndTime,
        if (blocksResponsiblePerson) 'blocksResponsiblePerson': true,
      };
}

final class HumanContextSection extends LifeContextDomainSection {
  HumanContextSection({
    required super.metadata,
    required this.primaryPersonId,
    List<HumanContextPerson> persons = const [],
    List<HumanContextRecord> relationships = const [],
    List<HumanContextRecord> households = const [],
    List<HumanContextRecord> residences = const [],
    List<HumanContextRecord> memberships = const [],
    List<HumanContextRecord> responsibilities = const [],
  })  : persons = UnmodifiableListView(persons),
        relationships = UnmodifiableListView(relationships),
        households = UnmodifiableListView(households),
        residences = UnmodifiableListView(residences),
        memberships = UnmodifiableListView(memberships),
        responsibilities = UnmodifiableListView(responsibilities);

  final String? primaryPersonId;
  final List<HumanContextPerson> persons;
  final List<HumanContextRecord> relationships;
  final List<HumanContextRecord> households;
  final List<HumanContextRecord> residences;
  final List<HumanContextRecord> memberships;
  final List<HumanContextRecord> responsibilities;

  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': LifeContextDomainSection.currentSchemaVersion,
        'metadata': metadata.toJson(),
        if (primaryPersonId != null) 'primaryPersonId': primaryPersonId,
        'persons': persons.map((item) => item.toJson()).toList(),
        'relationships': relationships.map((item) => item.toJson()).toList(),
        'households': households.map((item) => item.toJson()).toList(),
        'residences': residences.map((item) => item.toJson()).toList(),
        'memberships': memberships.map((item) => item.toJson()).toList(),
        'responsibilities':
            responsibilities.map((item) => item.toJson()).toList(),
      };
}

final class IdentityContextLink {
  const IdentityContextLink({
    required this.humanPersonId,
    required this.entityId,
    required this.entityType,
    required this.confirmed,
  });

  final String humanPersonId;
  final String entityId;
  final String entityType;
  final bool confirmed;

  Map<String, Object?> toJson() => {
        'humanPersonId': humanPersonId,
        'entityId': entityId,
        'entityType': entityType,
        'confirmed': confirmed,
      };
}

final class IdentityDomainSection extends LifeContextDomainSection {
  IdentityDomainSection({
    required super.metadata,
    List<IdentityContextLink> links = const [],
  }) : links = UnmodifiableListView(links);

  final List<IdentityContextLink> links;

  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': LifeContextDomainSection.currentSchemaVersion,
        'metadata': metadata.toJson(),
        'links': links.map((item) => item.toJson()).toList(),
      };
}

final class EventContextItem {
  const EventContextItem({
    required this.id,
    required this.title,
    required this.startDateTimeIso,
    required this.endDateTimeIso,
    required this.durationMinutes,
    required this.travelGoMinutes,
    required this.travelBackMinutes,
    required this.marginMinutes,
    required this.isRecurring,
    required this.recurringType,
    required this.revision,
    required this.syncStatus,
    this.participantEntityId,
    this.parentRecurringId,
    this.location,
    this.locationEntityId,
  });

  final String id;
  final String title;
  final String startDateTimeIso;
  final String endDateTimeIso;
  final int durationMinutes;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final bool isRecurring;
  final String recurringType;
  final int revision;
  final String syncStatus;
  final String? participantEntityId;
  final String? parentRecurringId;
  final String? location;
  final String? locationEntityId;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'startDateTimeIso': startDateTimeIso,
        'endDateTimeIso': endDateTimeIso,
        'durationMinutes': durationMinutes,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        'isRecurring': isRecurring,
        'recurringType': recurringType,
        'revision': revision,
        'syncStatus': syncStatus,
        if (participantEntityId != null)
          'participantEntityId': participantEntityId,
        if (parentRecurringId != null) 'parentRecurringId': parentRecurringId,
        if (location != null) 'location': location,
        if (locationEntityId != null) 'locationEntityId': locationEntityId,
      };
}

final class EventDomainSection extends LifeContextDomainSection {
  EventDomainSection({
    required super.metadata,
    List<EventContextItem> events = const [],
  }) : events = UnmodifiableListView(events);

  final List<EventContextItem> events;

  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': LifeContextDomainSection.currentSchemaVersion,
        'metadata': metadata.toJson(),
        'events': events.map((item) => item.toJson()).toList(),
      };
}

final class TaskContextItem {
  const TaskContextItem({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.dueDate,
    required this.durationMinutes,
    required this.syncStatus,
  });

  final String id;
  final String title;
  final bool isCompleted;
  final String? dueDate;
  final int? durationMinutes;
  final String syncStatus;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        if (dueDate != null) 'dueDate': dueDate,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'syncStatus': syncStatus,
      };
}

final class TaskDomainSection extends LifeContextDomainSection {
  TaskDomainSection({
    required super.metadata,
    List<TaskContextItem> tasks = const [],
  }) : tasks = UnmodifiableListView(tasks);

  final List<TaskContextItem> tasks;

  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': LifeContextDomainSection.currentSchemaVersion,
        'metadata': metadata.toJson(),
        'tasks': tasks.map((item) => item.toJson()).toList(),
      };
}

final class RoutineContextItem {
  const RoutineContextItem({
    required this.id,
    required this.source,
    required this.label,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.travelMinutes,
    this.recurrenceType,
    this.anchorDateIso,
    this.weekOfMonth,
    this.travelGoMinutes = 0,
    this.travelBackMinutes = 0,
    this.marginMinutes = 0,
    this.humanPersonId,
  });

  final String id;
  final String source;
  final String? label;
  final List<String> days;
  final String? startTime;
  final String? endTime;
  final int? travelMinutes;
  final String? recurrenceType;
  final String? anchorDateIso;
  final int? weekOfMonth;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final String? humanPersonId;

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        if (label != null) 'label': label,
        'days': days,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (travelMinutes != null) 'travelMinutes': travelMinutes,
        if (recurrenceType != null) 'recurrenceType': recurrenceType,
        if (anchorDateIso != null) 'anchorDateIso': anchorDateIso,
        if (weekOfMonth != null) 'weekOfMonth': weekOfMonth,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        if (humanPersonId != null) 'humanPersonId': humanPersonId,
      };
}

final class RoutineDomainSection extends LifeContextDomainSection {
  RoutineDomainSection({
    required super.metadata,
    List<RoutineContextItem> routines = const [],
  }) : routines = UnmodifiableListView(routines);

  final List<RoutineContextItem> routines;

  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': LifeContextDomainSection.currentSchemaVersion,
        'metadata': metadata.toJson(),
        'routines': routines.map((item) => item.toJson()).toList(),
      };
}

final class MemoryContextItem {
  const MemoryContextItem({
    required this.id,
    required this.text,
    this.semanticType = 'unknown',
    required this.category,
    this.importance = 0,
    required this.status,
    required this.confirmation,
    required this.provenance,
    required this.sensitivity,
    required this.isExplicitHealth,
    this.createdAt,
    this.updatedAt,
    this.validFrom,
    this.validUntil,
    this.structuredDomain,
    this.structuredReferenceId,
    this.semanticIdentityKey,
    this.semanticValue,
    this.revision,
  });

  final String id;
  final String text;
  final String semanticType;
  final String category;
  final int importance;
  final String status;
  final String confirmation;
  final String provenance;
  final String sensitivity;
  final bool isExplicitHealth;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? structuredDomain;
  final String? structuredReferenceId;
  final String? semanticIdentityKey;
  final String? semanticValue;
  final int? revision;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'semanticType': semanticType,
        'category': category,
        'importance': importance,
        'status': status,
        'confirmation': confirmation,
        'provenance': provenance,
        'sensitivity': sensitivity,
        'isExplicitHealth': isExplicitHealth,
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null)
          'updatedAt': updatedAt!.toUtc().toIso8601String(),
        if (validFrom != null)
          'validFrom': validFrom!.toUtc().toIso8601String(),
        if (validUntil != null)
          'validUntil': validUntil!.toUtc().toIso8601String(),
        if (structuredDomain != null) 'structuredDomain': structuredDomain,
        if (structuredReferenceId != null)
          'structuredReferenceId': structuredReferenceId,
        if (semanticIdentityKey != null)
          'semanticIdentityKey': semanticIdentityKey,
        if (semanticValue != null) 'semanticValue': semanticValue,
        if (revision != null) 'revision': revision,
      };
}

final class MemoryDomainSection extends LifeContextDomainSection {
  MemoryDomainSection({
    required super.metadata,
    required this.policyGeneralMode,
    required this.policyHealthMode,
    required this.policyConfigured,
    this.pendingCount = 0,
    this.hasConflicts = false,
    this.policySynchronized = false,
    this.hasLastValidState = false,
    List<MemoryContextItem> memories = const [],
  }) : memories = UnmodifiableListView(memories);

  final String policyGeneralMode;
  final String policyHealthMode;
  final bool policyConfigured;
  final int pendingCount;
  final bool hasConflicts;
  final bool policySynchronized;
  final bool hasLastValidState;
  final List<MemoryContextItem> memories;

  @override
  Map<String, Object?> toJson() => {
        'schemaVersion': LifeContextDomainSection.currentSchemaVersion,
        'metadata': metadata.toJson(),
        'policyGeneralMode': policyGeneralMode,
        'policyHealthMode': policyHealthMode,
        'policyConfigured': policyConfigured,
        'pendingCount': pendingCount,
        'hasConflicts': hasConflicts,
        'policySynchronized': policySynchronized,
        'hasLastValidState': hasLastValidState,
        'memories': memories.map((item) => item.toJson()).toList(),
      };
}
