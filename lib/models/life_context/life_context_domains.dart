import 'dart:collection';

enum LifeContextDomain { human, identity, event, task, routine }

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

enum LifeContextSourceKind {
  humanModelLocal,
  identityLinks,
  eventService,
  taskService,
  legacyProfileRoutine,
}

enum LifeContextGlobalState { complete, partial, unavailable }

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
  });

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

  Map<String, Object?> toJson() => {
        'domain': domain.name,
        'source': source.name,
        'readAt': readAt.toUtc().toIso8601String(),
        'availability': availability.name,
        'freshness': freshness.name,
        'isLocal': isLocal,
        'itemCount': itemCount,
        if (revision != null) 'revision': revision,
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
  });

  final String id;
  final String? displayName;
  final String status;
  final String confirmation;
  final String? identityEntityId;

  Map<String, Object?> toJson() => {
        'id': id,
        if (displayName != null) 'displayName': displayName,
        'status': status,
        'confirmation': confirmation,
        if (identityEntityId != null) 'identityEntityId': identityEntityId,
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
  });

  final String id;
  final String kind;
  final List<String> references;
  final String status;
  final String confirmation;
  final String? label;
  final DateTime? validFrom;
  final DateTime? validUntil;

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
    this.humanPersonId,
  });

  final String id;
  final String source;
  final String? label;
  final List<String> days;
  final String? startTime;
  final String? endTime;
  final int? travelMinutes;
  final String? humanPersonId;

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        if (label != null) 'label': label,
        'days': days,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (travelMinutes != null) 'travelMinutes': travelMinutes,
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
