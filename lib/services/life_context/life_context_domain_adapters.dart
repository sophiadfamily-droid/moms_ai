import '../../models/event_model.dart';
import '../../models/action_autonomy_policy.dart';
import '../../models/app_settings.dart';
import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';
import '../../models/life_context/life_context_domains.dart';
import '../../models/task_model.dart';
import '../../models/local_notification_models.dart';
import '../../models/user_profile.dart';
import '../../models/memory_policy.dart';
import '../../models/memory_sync.dart';
import '../../models/routine_model.dart';
import '../../models/shopping_item_model.dart';
import '../memory_sync_local_repository.dart';
import '../memory_consumption_policy.dart';
import '../human/human_profile_facts_service.dart';
import '../school_schedule_metadata_service.dart';
import '../structured_schedule_profile_service.dart';
import 'life_context_adapter.dart';
import 'life_context_memory_projection.dart';

typedef HumanContextLoader = Future<HumanModelLocalState?> Function(
  String accountScopeId,
);
typedef EventContextLoader = Future<List<EventModel>> Function(
  String accountScopeId,
);
typedef EventContextSyncLoader = Future<Map<String, String>> Function(
  String accountScopeId,
);
typedef TaskContextLoader = Future<List<TaskModel>> Function(
  String accountScopeId,
);
typedef TaskContextSyncLoader = Future<TaskLifeContextSyncMetadata> Function(
  String accountScopeId,
);
typedef MemoryContextLoader = Future<List<Map<String, dynamic>>> Function(
  String accountScopeId,
);
typedef MemoryPolicyContextLoader = Future<MemoryPolicy> Function(
  String accountScopeId,
);
typedef MemorySyncStateLoader = Future<MemorySyncLocalState?> Function(
  String accountScopeId,
);
typedef RoutineContextLoader = Future<List<RoutineModel>> Function(
  String accountScopeId,
);
typedef AppSettingsContextLoader = Future<AppSettings> Function(
  String accountScopeId,
);
typedef NotificationSettingsContextLoader = Future<NotificationSettings>
    Function(String accountScopeId);
typedef ActionAutonomyContextLoader = Future<ActionAutonomyPolicy> Function(
  String accountScopeId,
);
typedef ShoppingContextLoader = Future<List<ShoppingItemModel>> Function(
  String accountScopeId,
);

abstract final class LifeContextSourceBudgets {
  static const int events = 200;
  static const int tasks = 200;
  static const int routines = 200;
  static const int memories = 500;
  static const int shoppingItems = 100;
}

final class HumanModelLifeContextAdapter implements LifeContextDomainAdapter {
  const HumanModelLifeContextAdapter({required HumanContextLoader load})
      : _load = load;

  final HumanContextLoader _load;

  @override
  LifeContextDomain get domain => LifeContextDomain.human;

  @override
  Future<HumanContextSection> load(LifeContextAdapterRequest request) async {
    try {
      final state = await _load(request.accountScopeId);
      if (state == null) {
        return HumanContextSection(
          metadata: _metadata(
            request,
            domain,
            LifeContextSourceKind.humanModelLocal,
            LifeContextAvailability.empty,
            LifeContextFreshness.unknown,
            true,
            0,
          ),
          primaryPersonId: null,
        );
      }
      final model = state.model;
      if (model.accountScopeId != request.accountScopeId) {
        return HumanContextSection(
          metadata: _metadata(
            request,
            domain,
            LifeContextSourceKind.humanModelLocal,
            LifeContextAvailability.accountMismatch,
            LifeContextFreshness.unknown,
            true,
            0,
            errorCode: 'account_mismatch',
          ),
          primaryPersonId: null,
        );
      }
      model.validate();
      final stale = state.syncStatus != HumanModelSyncStatus.synced;
      final availability = _humanAvailability(state.syncStatus);
      final count = model.persons.length +
          model.relationships.length +
          model.households.length +
          model.residences.length +
          model.memberships.length +
          model.responsibilities.length;
      return HumanContextSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.humanModelLocal,
          count == 0 ? LifeContextAvailability.empty : availability,
          stale ? LifeContextFreshness.stale : LifeContextFreshness.current,
          true,
          count,
          revision: state.knownCloudRevision,
          syncStatus: state.syncStatus.name,
          errorCode: switch (state.syncStatus) {
            HumanModelSyncStatus.migrationFailed => 'human_migration_failed',
            HumanModelSyncStatus.corruptedLocal => 'human_local_recovered',
            HumanModelSyncStatus.unsupportedVersion =>
              'unsupported_human_version',
            _ => null,
          },
        ),
        primaryPersonId: model.primaryPersonId,
        persons: model.persons
            .map(
              (person) => HumanContextPerson(
                id: person.id,
                displayName: person.displayName,
                status: person.status.name,
                confirmation: person.evidence.confirmation.name,
                identityEntityId: person.identityLink?.entityId,
                birthDate: _humanBirthDate(person),
                familyStatus: _humanTextField(person, 'familyStatus'),
                workStatus: _humanTextField(person, 'workStatus'),
                profileFacts: _humanProfileFacts(person),
              ),
            )
            .toList(),
        relationships: model.relationships
            .map(
              (record) => _record(
                record.id,
                record.customType ?? record.type,
                [record.sourcePersonId, record.targetPersonId],
                record.status.name,
                record.evidence,
                record.validity,
                sourceReferenceId: record.sourcePersonId,
                targetReferenceId: record.targetPersonId,
                evidenceSource: record.evidence.source.name,
                reciprocal: record.reciprocal,
                relationshipStatus:
                    _relationshipDetail(model, record, 'relationshipStatus'),
                marriageDate: _relationshipDate(
                  model,
                  record,
                  'marriageDate',
                ),
                engagementDate: _relationshipDate(
                  model,
                  record,
                  'engagementDate',
                ),
              ),
            )
            .toList(),
        households: model.households
            .map(
              (record) => _record(
                record.id,
                record.status.name,
                const [],
                record.status.name,
                record.evidence,
                record.validity,
                label: record.displayName,
                evidenceSource: record.evidence.source.name,
              ),
            )
            .toList(),
        residences: model.residences
            .map(
              (record) => _record(
                record.id,
                record.status.name,
                [...record.householdIds, ...record.personIds],
                record.status.name,
                record.evidence,
                record.validity,
                label: record.label,
                householdIds: record.householdIds,
                personIds: record.personIds,
                placeEntityId: record.placeEntityId,
                evidenceSource: record.evidence.source.name,
              ),
            )
            .toList(),
        memberships: model.memberships
            .map(
              (record) => _record(
                record.id,
                record.customRole ?? record.role,
                [record.householdId, record.personId],
                'declared',
                record.evidence,
                record.validity,
                sourceReferenceId: record.personId,
                targetReferenceId: record.householdId,
                evidenceSource: record.evidence.source.name,
              ),
            )
            .toList(),
        responsibilities: model.responsibilities
            .map(
              (record) => _record(
                record.id,
                record.customType ?? record.type,
                [record.responsiblePersonId, record.subjectPersonId],
                record.status.name,
                record.evidence,
                record.validity,
                label: record.scope,
                sourceReferenceId: record.responsiblePersonId,
                targetReferenceId: record.subjectPersonId,
                evidenceSource: record.evidence.source.name,
                planningConsequenceType: record.planningConsequence?.type ??
                    record.recurringPlanningConsequence?.type,
                planningConsequenceStart: record.planningConsequence?.start,
                planningConsequenceEnd: record.planningConsequence?.end,
                planningConsequenceWeekdays:
                    record.recurringPlanningConsequence?.weekdays ?? const [],
                planningConsequenceStartTime:
                    record.recurringPlanningConsequence?.startTime,
                planningConsequenceEndTime:
                    record.recurringPlanningConsequence?.endTime,
                blocksResponsiblePerson:
                    record.planningConsequence?.blocksResponsiblePerson ??
                        record.recurringPlanningConsequence
                            ?.blocksResponsiblePerson ??
                        false,
              ),
            )
            .toList(),
      );
    } on HumanModelException {
      return HumanContextSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.humanModelLocal,
          LifeContextAvailability.corrupted,
          LifeContextFreshness.unknown,
          true,
          0,
          errorCode: 'invalid_human_model',
        ),
        primaryPersonId: null,
      );
    } on Object {
      return HumanContextSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.humanModelLocal,
          LifeContextAvailability.unavailable,
          LifeContextFreshness.unknown,
          true,
          0,
          errorCode: 'human_domain_unavailable',
        ),
        primaryPersonId: null,
      );
    }
  }

  HumanContextRecord _record(
    String id,
    String kind,
    List<String> references,
    String status,
    HumanEvidence evidence,
    HumanValidityPeriod validity, {
    String? label,
    String? sourceReferenceId,
    String? targetReferenceId,
    List<String> householdIds = const [],
    List<String> personIds = const [],
    String? placeEntityId,
    String? evidenceSource,
    bool reciprocal = false,
    String? relationshipStatus,
    String? marriageDate,
    String? engagementDate,
    String? planningConsequenceType,
    DateTime? planningConsequenceStart,
    DateTime? planningConsequenceEnd,
    List<int> planningConsequenceWeekdays = const [],
    String? planningConsequenceStartTime,
    String? planningConsequenceEndTime,
    bool blocksResponsiblePerson = false,
  }) =>
      HumanContextRecord(
        id: id,
        kind: kind,
        references: List<String>.of(references)..sort(),
        status: status,
        confirmation: evidence.confirmation.name,
        label: label,
        validFrom: validity.validFrom,
        validUntil: validity.validUntil,
        sourceReferenceId: sourceReferenceId,
        targetReferenceId: targetReferenceId,
        householdIds: List<String>.of(householdIds)..sort(),
        personIds: List<String>.of(personIds)..sort(),
        placeEntityId: placeEntityId,
        evidenceSource: evidenceSource,
        reciprocal: reciprocal,
        relationshipStatus: relationshipStatus,
        marriageDate: marriageDate,
        engagementDate: engagementDate,
        planningConsequenceType: planningConsequenceType,
        planningConsequenceStart: planningConsequenceStart,
        planningConsequenceEnd: planningConsequenceEnd,
        planningConsequenceWeekdays: List<int>.of(planningConsequenceWeekdays)
          ..sort(),
        planningConsequenceStartTime: planningConsequenceStartTime,
        planningConsequenceEndTime: planningConsequenceEndTime,
        blocksResponsiblePerson: blocksResponsiblePerson,
      );
}

List<HumanContextProfileFact> _humanProfileFacts(HumanPerson person) {
  final facts = <HumanContextProfileFact>[];
  for (final entry in HumanProfileFactsV1.contextClasses.entries) {
    if (entry.value == HumanProfileFactContextClass.excluded) continue;
    final rawValue = person.customFields[entry.key];
    final value = switch (rawValue) {
      String text when text.trim().isNotEmpty => text.trim(),
      num number => number.toString(),
      bool flag => flag.toString(),
      _ => null,
    };
    if (value == null) continue;
    final evidence =
        HumanProfileFactsV1.evidenceFor(person, entry.key) ?? person.evidence;
    facts.add(
      HumanContextProfileFact(
        key: entry.key,
        value: value,
        source: evidence.source.name,
        confirmation: evidence.confirmation.name,
      ),
    );
  }
  facts.sort((first, second) => first.key.compareTo(second.key));
  return facts;
}

String? _structuredString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

String? _structuredDate(Map<String, Object?> values, String key) {
  final source = _structuredString(values, key);
  if (source == null) return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(source);
  final french = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(source);
  final year = int.tryParse(iso?.group(1) ?? french?.group(3) ?? '');
  final month = int.tryParse(iso?.group(2) ?? french?.group(2) ?? '');
  final day = int.tryParse(iso?.group(3) ?? french?.group(1) ?? '');
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${parsed.year.toString().padLeft(4, '0')}-'
      '${twoDigits(parsed.month)}-${twoDigits(parsed.day)}';
}

String? _relationshipDetail(
  HumanModel model,
  HumanRelationship relationship,
  String key,
) {
  final canonical = _structuredString(relationship.structuredNotes, key);
  if (canonical != null) return canonical;
  final person = model.personById(relationship.targetPersonId);
  return person == null ? null : _structuredString(person.customFields, key);
}

String? _relationshipDate(
  HumanModel model,
  HumanRelationship relationship,
  String key,
) {
  final canonical = _structuredDate(relationship.structuredNotes, key);
  if (canonical != null) return canonical;
  final person = model.personById(relationship.targetPersonId);
  return person == null ? null : _structuredDate(person.customFields, key);
}

String? _humanBirthDate(HumanPerson person) {
  final value = person.customFields['birthDate'] ??
      person.customFields['legacyBirthDate'];
  if (value is! String || value.trim().isEmpty) return null;
  final source = value.trim();
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(source);
  final french = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(source);
  final year = int.tryParse(iso?.group(1) ?? french?.group(3) ?? '');
  final month = int.tryParse(iso?.group(2) ?? french?.group(2) ?? '');
  final day = int.tryParse(iso?.group(3) ?? french?.group(1) ?? '');
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }

  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${parsed.year.toString().padLeft(4, '0')}-'
      '${twoDigits(parsed.month)}-${twoDigits(parsed.day)}';
}

String? _humanTextField(HumanPerson person, String key) {
  final value = person.customFields[key];
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

final class IdentityLifeContextAdapter implements LifeContextDomainAdapter {
  const IdentityLifeContextAdapter({required HumanContextLoader loadHuman})
      : _loadHuman = loadHuman;

  final HumanContextLoader _loadHuman;

  @override
  LifeContextDomain get domain => LifeContextDomain.identity;

  @override
  Future<IdentityDomainSection> load(
    LifeContextAdapterRequest request,
  ) async {
    try {
      final state = await _loadHuman(request.accountScopeId);
      if (state == null) return _empty(request);
      if (state.model.accountScopeId != request.accountScopeId) {
        return IdentityDomainSection(
          metadata: _metadata(
            request,
            domain,
            LifeContextSourceKind.identityLinks,
            LifeContextAvailability.accountMismatch,
            LifeContextFreshness.unknown,
            true,
            0,
            errorCode: 'account_mismatch',
          ),
        );
      }
      final links = state.model.persons
          .where((person) => person.identityLink != null)
          .map(
            (person) => IdentityContextLink(
              humanPersonId: person.id,
              entityId: person.identityLink!.entityId,
              entityType: person.identityLink!.entityType.name,
              confirmed: person.evidence.confirmation ==
                  HumanConfirmationStatus.confirmed,
            ),
          )
          .toList()
        ..sort((a, b) => a.humanPersonId.compareTo(b.humanPersonId));
      return IdentityDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.identityLinks,
          links.isEmpty
              ? LifeContextAvailability.empty
              : LifeContextAvailability.available,
          LifeContextFreshness.current,
          true,
          links.length,
          revision: state.knownCloudRevision,
          syncStatus: state.syncStatus.name,
        ),
        links: links,
      );
    } on Object {
      return IdentityDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.identityLinks,
          LifeContextAvailability.unavailable,
          LifeContextFreshness.unknown,
          true,
          0,
          errorCode: 'identity_domain_unavailable',
        ),
      );
    }
  }

  IdentityDomainSection _empty(LifeContextAdapterRequest request) =>
      IdentityDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.identityLinks,
          LifeContextAvailability.empty,
          LifeContextFreshness.unknown,
          true,
          0,
        ),
      );
}

final class EventLifeContextAdapter implements LifeContextDomainAdapter {
  const EventLifeContextAdapter({
    required EventContextLoader load,
    EventContextSyncLoader? loadSyncStatuses,
  })  : _load = load,
        _loadSyncStatuses = loadSyncStatuses;

  final EventContextLoader _load;
  final EventContextSyncLoader? _loadSyncStatuses;

  static const Duration _operationalPastWindow = Duration(days: 7);
  static const Duration _operationalFutureWindow = Duration(days: 60);

  @override
  LifeContextDomain get domain => LifeContextDomain.event;

  @override
  Future<EventDomainSection> load(LifeContextAdapterRequest request) async {
    try {
      final source = await _load(request.accountScopeId);
      final syncStatuses =
          await _loadSyncStatuses?.call(request.accountScopeId) ?? const {};
      final allItems = source.map((event) {
        final id = event.id;
        if (id == null || id.trim().isEmpty) {
          throw const FormatException('event_missing_stable_id');
        }
        final participant = event.participantIdentity;
        if (participant != null &&
            participant.accountScopeId != request.accountScopeId) {
          throw const FormatException('event_account_mismatch');
        }
        return EventContextItem(
          id: id,
          title: event.title,
          startDateTimeIso: event.startDateTimeIso,
          endDateTimeIso: event.endDateTimeIso,
          durationMinutes: event.durationMinutes,
          travelGoMinutes: event.resolvedTravelGoMinutes,
          travelBackMinutes: event.resolvedTravelBackMinutes,
          marginMinutes: event.marginMinutes,
          isRecurring: event.isRecurring,
          recurringType: event.recurringType,
          revision: event.eventRevision,
          syncStatus: syncStatuses[id] ?? 'unknown',
          participantEntityId: participant?.identity.entityId,
          parentRecurringId: _optional(event.parentRecurringId),
          location: _optional(event.location),
          locationEntityId: _optional(event.locationEntityId),
        );
      }).where((event) {
        final start = DateTime.tryParse(event.startDateTimeIso)?.toUtc();
        if (start == null) return true;
        final parsedEnd = DateTime.tryParse(event.endDateTimeIso)?.toUtc();
        final end = parsedEnd ??
            start.add(Duration(minutes: event.durationMinutes.clamp(0, 1440)));
        final lower = request.readAt.toUtc().subtract(_operationalPastWindow);
        final upper = request.readAt.toUtc().add(_operationalFutureWindow);
        return !end.isBefore(lower) && !start.isAfter(upper);
      }).toList()
        ..sort((a, b) {
          final date = a.startDateTimeIso.compareTo(b.startDateTimeIso);
          return date != 0 ? date : a.id.compareTo(b.id);
        });
      final truncated = allItems.length > LifeContextSourceBudgets.events;
      final items = allItems
          .take(LifeContextSourceBudgets.events)
          .toList(growable: false);
      return EventDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.eventService,
          items.isEmpty
              ? LifeContextAvailability.empty
              : LifeContextAvailability.available,
          LifeContextFreshness.current,
          false,
          items.length,
          syncStatus: syncStatuses.values.contains('conflict')
              ? 'conflicts'
              : syncStatuses.isEmpty
                  ? 'unknown'
                  : 'known',
          truncationState: truncated
              ? LifeContextTruncationState.truncated
              : LifeContextTruncationState.complete,
          warningCodes: truncated ? const ['event_source_truncated'] : const [],
        ),
        events: items,
      );
    } on FormatException {
      return EventDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.eventService,
          LifeContextAvailability.corrupted,
          LifeContextFreshness.unknown,
          false,
          0,
          errorCode: 'invalid_event_domain',
        ),
      );
    } on Object {
      return EventDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.eventService,
          LifeContextAvailability.unavailable,
          LifeContextFreshness.unknown,
          false,
          0,
          errorCode: 'event_domain_unavailable',
        ),
      );
    }
  }
}

final class TaskLifeContextAdapter implements LifeContextDomainAdapter {
  const TaskLifeContextAdapter({
    required TaskContextLoader load,
    TaskContextSyncLoader? loadSyncMetadata,
  })  : _load = load,
        _loadSyncMetadata = loadSyncMetadata;

  final TaskContextLoader _load;
  final TaskContextSyncLoader? _loadSyncMetadata;

  @override
  LifeContextDomain get domain => LifeContextDomain.task;

  @override
  Future<TaskDomainSection> load(LifeContextAdapterRequest request) async {
    try {
      final source = await _load(request.accountScopeId);
      final syncMetadata = await _loadSyncMetadata?.call(
        request.accountScopeId,
      );
      final allItems = source.map((task) {
        final id = task.id;
        if (id == null || id.trim().isEmpty) {
          throw const FormatException('task_missing_stable_id');
        }
        return TaskContextItem(
          id: id,
          title: task.title,
          isCompleted: task.isDone,
          dueDate: _normalizeTaskDueDate(task.dueDate),
          durationMinutes: task.durationMinutes,
          syncStatus: syncMetadata?.itemSyncStatuses[id] ?? 'unknown',
          importance: _taskImportance(task),
          urgency: _taskUrgency(task),
          category: _taskCategory(task.category),
          createdAt: task.createdAt.toUtc().toIso8601String(),
        );
      }).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final truncated = allItems.length > LifeContextSourceBudgets.tasks;
      final items =
          allItems.take(LifeContextSourceBudgets.tasks).toList(growable: false);
      return TaskDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.taskService,
          items.isEmpty
              ? LifeContextAvailability.empty
              : LifeContextAvailability.available,
          LifeContextFreshness.current,
          syncMetadata != null,
          items.length,
          revision: syncMetadata?.revision,
          syncStatus: syncMetadata?.syncStatus,
          truncationState: truncated
              ? LifeContextTruncationState.truncated
              : LifeContextTruncationState.complete,
          warningCodes: truncated ? const ['task_source_truncated'] : const [],
        ),
        tasks: items,
      );
    } on FormatException {
      return TaskDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.taskService,
          LifeContextAvailability.corrupted,
          LifeContextFreshness.unknown,
          false,
          0,
          errorCode: 'invalid_task_domain',
        ),
      );
    } on Object {
      return TaskDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.taskService,
          LifeContextAvailability.unavailable,
          LifeContextFreshness.unknown,
          false,
          0,
          errorCode: 'task_domain_unavailable',
        ),
      );
    }
  }

  static String? _normalizeTaskDueDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsedIso = DateTime.tryParse(trimmed);
    if (parsedIso != null) return trimmed;
    final french =
        RegExp(r'^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$').firstMatch(trimmed);
    if (french == null) return trimmed;
    final day = int.parse(french.group(1)!);
    final month = int.parse(french.group(2)!);
    final year = int.parse(french.group(3)!);
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return trimmed;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  static double? _taskImportance(TaskModel task) {
    final priority = task.priority.trim().toLowerCase();
    if (task.isImportant ||
        const {'haute', 'urgent', 'urgente', 'important', 'importante'}
            .contains(priority)) {
      return 1;
    }
    return null;
  }

  static double? _taskUrgency(TaskModel task) {
    final priority = task.priority.trim().toLowerCase();
    // The task UI exposes one "Urgent" switch. Historical and current
    // persistence can represent that same user choice as `isImportant`,
    // `Haute`, `Urgent` or `Urgente`. They must all project the same fact for
    // Zelia's canonical reasoning layer.
    if (task.isImportant ||
        const {'haute', 'high', 'urgent', 'urgente'}.contains(priority)) {
      return 1;
    }
    final planning = task.planning.trim().toLowerCase();
    if (planning == 'aujourd’hui' || planning == "aujourd'hui") return .9;
    return null;
  }

  static String _taskCategory(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('sant') || normalized.contains('médic')) {
      return 'health';
    }
    if (normalized.contains('administr')) return 'administrative';
    if (normalized.contains('financ') || normalized.contains('budget')) {
      return 'financial';
    }
    if (normalized.contains('travail') || normalized.contains('pro')) {
      return 'work';
    }
    if (normalized.contains('logist') || normalized.contains('course')) {
      return 'logistics';
    }
    if (normalized.contains('perso') || normalized.contains('famille')) {
      return 'personal';
    }
    return normalized.isEmpty ? 'unknown' : 'other';
  }
}

final class RoutineLifeContextAdapter implements LifeContextDomainAdapter {
  const RoutineLifeContextAdapter({
    required HumanContextLoader loadHuman,
    RoutineContextLoader? loadCanonical,
  })  : _loadHuman = loadHuman,
        _loadCanonical = loadCanonical;

  final HumanContextLoader _loadHuman;
  final RoutineContextLoader? _loadCanonical;

  @override
  LifeContextDomain get domain => LifeContextDomain.routine;

  @override
  Future<RoutineDomainSection> load(
    LifeContextAdapterRequest request,
  ) async {
    try {
      final state = await _loadHuman(request.accountScopeId);
      if (state != null &&
          state.model.accountScopeId != request.accountScopeId) {
        return RoutineDomainSection(
          metadata: _metadata(
            request,
            domain,
            LifeContextSourceKind.legacyProfileRoutine,
            LifeContextAvailability.accountMismatch,
            LifeContextFreshness.unknown,
            true,
            0,
            errorCode: 'account_mismatch',
          ),
        );
      }
      final profile = state == null
          ? null
          : UserProfile.fromJson(
              Map<String, dynamic>.from(state.model.legacyProfile),
            );
      final routines = <RoutineContextItem>[];
      var canonicalUnavailable = false;
      List<RoutineModel> canonical;
      try {
        canonical = await _loadCanonical?.call(request.accountScopeId) ??
            const <RoutineModel>[];
      } on Object {
        canonicalUnavailable = true;
        canonical = const [];
      }
      for (final routine in canonical) {
        if (routine.accountScopeId != request.accountScopeId ||
            routine.status != RoutineStatus.active) {
          throw const FormatException('invalid_canonical_routine');
        }
        routines.add(
          RoutineContextItem(
            id: routine.id,
            source: 'routine.v1',
            label: routine.title,
            days: routine.days.map((day) => '$day').toList(growable: false),
            startTime: routine.startTime,
            endTime: routine.endTime,
            travelMinutes: routine.travelGoMinutes + routine.travelBackMinutes,
            recurrenceType: switch (routine.recurrenceType) {
              RoutineRecurrenceType.weekly => 'weekly',
              RoutineRecurrenceType.weekdays => 'weekdays',
              RoutineRecurrenceType.biweekly => 'biweekly',
              RoutineRecurrenceType.monthlyNthWeekday => 'monthly_nth_weekday',
            },
            anchorDateIso: routine.anchorDateIso,
            weekOfMonth: routine.weekOfMonth,
            travelGoMinutes: routine.travelGoMinutes,
            travelBackMinutes: routine.travelBackMinutes,
            marginMinutes: routine.marginMinutes,
            humanPersonId: routine.humanPersonId,
          ),
        );
      }
      if (state != null) {
        for (final person in state.model.persons) {
          final imported = StructuredScheduleProfileService.entriesForPerson(
            person,
            at: request.readAt,
          );
          for (final entry in imported) {
            routines.add(
              RoutineContextItem(
                id: 'profileSchedule:${entry.sourceKey}',
                source: 'humanModel.structuredSchedulesV1',
                label: entry.title,
                days: entry.weekdays.map((day) => '$day').toList(),
                startTime: entry.startTime,
                endTime: entry.endTime,
                travelMinutes: null,
                recurrenceType: entry.isDated ? 'dated' : 'weekly',
                anchorDateIso: entry.dateIso,
                humanPersonId: person.id,
              ),
            );
          }
        }
      }
      for (var index = 0;
          index < (profile?.personalActivities.length ?? 0);
          index++) {
        final effectiveProfile = profile!;
        final activity = effectiveProfile.personalActivities[index];
        if (activity.timeRanges.isEmpty) {
          routines.add(
            RoutineContextItem(
              id: 'personalActivity:$index',
              source: 'legacyProfile.personalActivities',
              label: _optional(activity.title),
              days: List<String>.of(activity.days)..sort(),
              startTime: null,
              endTime: null,
              travelMinutes: int.tryParse(activity.travelMinutes),
              humanPersonId: state!.model.primaryPersonId,
            ),
          );
        } else {
          for (var rangeIndex = 0;
              rangeIndex < activity.timeRanges.length;
              rangeIndex++) {
            final range = activity.timeRanges[rangeIndex];
            final rangeDays =
                SchoolScheduleMetadataService.daysFromRange(range);
            routines.add(
              RoutineContextItem(
                id: 'personalActivity:$index:$rangeIndex',
                source: 'legacyProfile.personalActivities',
                label: _optional(activity.title),
                days: List<String>.of(
                  rangeDays.isEmpty ? activity.days : rangeDays,
                )..sort(),
                startTime: _optional(range.startTime),
                endTime: _optional(range.endTime),
                travelMinutes: int.tryParse(activity.travelMinutes),
                humanPersonId: state!.model.primaryPersonId,
              ),
            );
          }
        }
      }
      for (var rangeIndex = 0;
          rangeIndex < (profile?.workTimeRanges.length ?? 0);
          rangeIndex++) {
        final range = profile!.workTimeRanges[rangeIndex];
        if (range.startTime.trim().isEmpty || range.endTime.trim().isEmpty) {
          continue;
        }
        final rangeDays = SchoolScheduleMetadataService.daysFromRange(range);
        routines.add(
          RoutineContextItem(
            id: 'workSchedule:$rangeIndex',
            source: 'legacyProfile.workTimeRanges',
            label: _optional(range.label),
            days: List<String>.of(
              rangeDays.isEmpty ? profile.workDays : rangeDays,
            )..sort(),
            startTime: range.startTime.trim(),
            endTime: range.endTime.trim(),
            travelMinutes: int.tryParse(
              range.travelMinutes.trim().isNotEmpty
                  ? range.travelMinutes
                  : profile.workTravelMinutes,
            ),
            humanPersonId: state!.model.primaryPersonId,
          ),
        );
      }
      final legacyWorkRanges = [
        (
          id: 'workSchedule:legacyMorning',
          label: 'Travail matin',
          start: profile?.morningStart ?? '',
          end: profile?.morningEnd ?? '',
        ),
        (
          id: 'workSchedule:legacyAfternoon',
          label: 'Travail après-midi',
          start: profile?.afternoonStart ?? '',
          end: profile?.afternoonEnd ?? '',
        ),
      ];
      for (final range in legacyWorkRanges) {
        if (range.start.trim().isEmpty || range.end.trim().isEmpty) continue;
        routines.add(
          RoutineContextItem(
            id: range.id,
            source: 'legacyProfile.workSchedule',
            label: range.label,
            days: List<String>.of(profile?.workDays ?? const [])..sort(),
            startTime: range.start.trim(),
            endTime: range.end.trim(),
            travelMinutes: int.tryParse(profile?.workTravelMinutes ?? ''),
            humanPersonId: state!.model.primaryPersonId,
          ),
        );
      }
      for (var childIndex = 0;
          childIndex < (profile?.children.length ?? 0);
          childIndex++) {
        final child = profile!.children[childIndex];
        for (var rangeIndex = 0;
            rangeIndex < child.schoolTimeRanges.length;
            rangeIndex++) {
          final range = child.schoolTimeRanges[rangeIndex];
          routines.add(
            RoutineContextItem(
              id: 'schoolSchedule:$childIndex:$rangeIndex',
              source: 'legacyProfile.schoolTimeRanges',
              label: _optional(range.label),
              days: SchoolScheduleMetadataService.daysFromRange(range),
              startTime: _optional(range.startTime),
              endTime: _optional(range.endTime),
              travelMinutes: int.tryParse(range.travelMinutes),
              humanPersonId: _optional(child.humanPersonId),
            ),
          );
        }
        for (var activityIndex = 0;
            activityIndex < child.activities.length;
            activityIndex++) {
          final activity = child.activities[activityIndex];
          for (var rangeIndex = 0;
              rangeIndex < activity.timeRanges.length;
              rangeIndex++) {
            final range = activity.timeRanges[rangeIndex];
            if (range.startTime.trim().isEmpty ||
                range.endTime.trim().isEmpty) {
              continue;
            }
            final rangeDays =
                SchoolScheduleMetadataService.daysFromRange(range);
            routines.add(
              RoutineContextItem(
                id: 'childActivity:$childIndex:$activityIndex:$rangeIndex',
                source: 'legacyProfile.childActivities',
                label: _optional(activity.title),
                days: List<String>.of(
                  rangeDays.isEmpty ? activity.days : rangeDays,
                )..sort(),
                startTime: range.startTime.trim(),
                endTime: range.endTime.trim(),
                travelMinutes: int.tryParse(
                  activity.travelMinutes.trim().isNotEmpty
                      ? activity.travelMinutes
                      : range.travelMinutes,
                ),
                humanPersonId: _optional(child.humanPersonId),
              ),
            );
          }
        }
      }
      final canonicalProfileScheduleKeys = routines
          .where(
            (item) => item.source == 'humanModel.structuredSchedulesV1',
          )
          .map(_routineScheduleIdentity)
          .toSet();
      routines.removeWhere(
        (item) =>
            item.source.startsWith('legacyProfile.') &&
            canonicalProfileScheduleKeys.contains(
              _routineScheduleIdentity(item),
            ),
      );
      routines.sort((a, b) => a.id.compareTo(b.id));
      final sourceCount = routines.length;
      final legacyRoutineCount = sourceCount - canonical.length;
      final legacySourceFresh = legacyRoutineCount == 0 ||
          state?.syncStatus == HumanModelSyncStatus.synced;
      final availability = routines.isEmpty
          ? canonicalUnavailable
              ? LifeContextAvailability.unavailable
              : LifeContextAvailability.empty
          : legacySourceFresh && !canonicalUnavailable
              ? LifeContextAvailability.available
              : LifeContextAvailability.availableStale;
      final freshness = routines.isEmpty
          ? LifeContextFreshness.unknown
          : legacySourceFresh && !canonicalUnavailable
              ? LifeContextFreshness.current
              : LifeContextFreshness.stale;
      final truncated = sourceCount > LifeContextSourceBudgets.routines;
      final warningCodes = [
        if (canonicalUnavailable) 'canonical_routines_unavailable',
        if (truncated) 'routine_source_truncated',
      ];
      final boundedRoutines = routines
          .take(LifeContextSourceBudgets.routines)
          .toList(growable: false);
      return RoutineDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.legacyProfileRoutine,
          availability,
          freshness,
          true,
          boundedRoutines.length,
          revision: state?.knownCloudRevision,
          syncStatus:
              canonical.isNotEmpty ? 'canonical' : 'legacyCompatibility',
          errorCode: routines.isEmpty && canonicalUnavailable
              ? 'routine_domain_unavailable'
              : null,
          truncationState: truncated
              ? LifeContextTruncationState.truncated
              : LifeContextTruncationState.complete,
          warningCodes: warningCodes,
        ),
        routines: boundedRoutines,
      );
    } on Object {
      return RoutineDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.legacyProfileRoutine,
          LifeContextAvailability.unavailable,
          LifeContextFreshness.unknown,
          true,
          0,
          errorCode: 'routine_domain_unavailable',
        ),
      );
    }
  }
}

final class MemoryLifeContextAdapter implements LifeContextDomainAdapter {
  const MemoryLifeContextAdapter({
    required MemoryContextLoader loadMemories,
    required MemoryPolicyContextLoader loadPolicy,
    MemorySyncStateLoader? loadSyncState,
    LifeContextMemoryProjection projection =
        const HistoricalMemoryContextProjection(),
  })  : _loadMemories = loadMemories,
        _loadPolicy = loadPolicy,
        _loadSyncState = loadSyncState,
        _projection = projection;

  final MemoryContextLoader _loadMemories;
  final MemoryPolicyContextLoader _loadPolicy;
  final MemorySyncStateLoader? _loadSyncState;
  final LifeContextMemoryProjection _projection;

  @override
  LifeContextDomain get domain => LifeContextDomain.memory;

  @override
  Future<MemoryDomainSection> load(LifeContextAdapterRequest request) async {
    try {
      final policy = await _loadPolicy(request.accountScopeId);
      if (policy.accountScopeId != request.accountScopeId) {
        return _empty(
          request,
          LifeContextAvailability.accountMismatch,
          'account_mismatch',
        );
      }
      policy.validate();
      final raw = await _loadMemories(request.accountScopeId);
      final context = _projection.project(
        raw.where((item) => item['tombstone'] != true),
      );
      final syncState = await _loadSyncState?.call(request.accountScopeId);
      final allMemories = MemoryConsumptionPolicy.consumable(
        context.memories,
        referenceDate: request.readAt,
      )
          .map(
            (memory) => MemoryContextItem(
              id: memory.id,
              text: memory.text,
              semanticType: memory.semanticType.name,
              category: memory.category,
              importance: memory.importance,
              status: memory.lifecycleState.name,
              confirmation: memory.confirmationStatus.name,
              provenance: memory.sourceType.name,
              sensitivity: memory.sensitivity.name,
              isExplicitHealth: memory.isExplicitHealth,
              createdAt: memory.createdAt,
              updatedAt: memory.updatedAt,
              validFrom: memory.validFrom,
              validUntil: memory.validUntil,
              structuredDomain: memory.structuredDomain,
              structuredReferenceId: memory.structuredReferenceId,
              semanticIdentityKey:
                  memory.semanticIdentityRead.identity?.canonicalKey,
              semanticValue: memory.semanticValue,
              revision: memory.memoryRevision,
            ),
          )
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final truncated = allMemories.length > LifeContextSourceBudgets.memories;
      final memories = allMemories
          .take(LifeContextSourceBudgets.memories)
          .toList(growable: false);
      return MemoryDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.memoryFirestore,
          memories.isEmpty
              ? LifeContextAvailability.empty
              : LifeContextAvailability.available,
          LifeContextFreshness.current,
          false,
          memories.length,
          revision: syncState?.policy?.policyRevision,
          syncStatus: policy.generalMode == MemoryGeneralMode.paused
              ? 'paused'
              : syncState?.syncStatus.name ?? 'available',
          truncationState: truncated
              ? LifeContextTruncationState.truncated
              : LifeContextTruncationState.complete,
          warningCodes:
              truncated ? const ['memory_source_truncated'] : const [],
        ),
        policyGeneralMode: policy.generalMode.name,
        policyHealthMode: policy.healthMode.name,
        policyConfigured:
            policy.changeSource == MemoryPolicyChangeSource.explicitUserSetting,
        pendingCount: syncState?.mutations
                .where((mutation) =>
                    mutation.state != MemoryMutationState.completed &&
                    mutation.state != MemoryMutationState.abandoned)
                .length ??
            0,
        hasConflicts: syncState?.conflicts.isNotEmpty ?? false,
        policySynchronized: syncState?.syncStatus == MemorySyncStatus.synced,
        hasLastValidState: syncState != null,
        memories: memories,
      );
    } on MemoryPolicyException {
      return _empty(
        request,
        LifeContextAvailability.corrupted,
        'memory_policy_invalid',
      );
    } on Object {
      return _empty(
        request,
        LifeContextAvailability.unavailable,
        'memory_domain_unavailable',
      );
    }
  }

  MemoryDomainSection _empty(
    LifeContextAdapterRequest request,
    LifeContextAvailability availability,
    String errorCode,
  ) =>
      MemoryDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.memoryFirestore,
          availability,
          LifeContextFreshness.unknown,
          false,
          0,
          errorCode: errorCode,
        ),
        policyGeneralMode: MemoryGeneralMode.askEveryTime.name,
        policyHealthMode: MemoryHealthMode.disabled.name,
        policyConfigured: false,
      );
}

final class SettingsLifeContextAdapter implements LifeContextDomainAdapter {
  const SettingsLifeContextAdapter({
    required AppSettingsContextLoader loadAppSettings,
    required NotificationSettingsContextLoader loadNotifications,
    required ActionAutonomyContextLoader loadActionAutonomy,
    required MemoryPolicyContextLoader loadMemoryPolicy,
  })  : _loadAppSettings = loadAppSettings,
        _loadNotifications = loadNotifications,
        _loadActionAutonomy = loadActionAutonomy,
        _loadMemoryPolicy = loadMemoryPolicy;

  final AppSettingsContextLoader _loadAppSettings;
  final NotificationSettingsContextLoader _loadNotifications;
  final ActionAutonomyContextLoader _loadActionAutonomy;
  final MemoryPolicyContextLoader _loadMemoryPolicy;

  @override
  LifeContextDomain get domain => LifeContextDomain.settings;

  @override
  Future<SettingsContextSection> load(
    LifeContextAdapterRequest request,
  ) async {
    try {
      final results = await Future.wait<Object?>([
        _loadAppSettings(request.accountScopeId),
        _loadNotifications(request.accountScopeId),
        _loadActionAutonomy(request.accountScopeId),
        _loadMemoryPolicy(request.accountScopeId),
      ]);
      final appSettings = results[0] as AppSettings;
      final notifications = results[1] as NotificationSettings;
      final autonomy = results[2] as ActionAutonomyPolicy;
      final memory = results[3] as MemoryPolicy;
      if (appSettings.accountScopeId != request.accountScopeId ||
          notifications.accountScopeId != request.accountScopeId ||
          autonomy.accountScopeId != request.accountScopeId ||
          memory.accountScopeId != request.accountScopeId) {
        return _empty(
          request,
          LifeContextAvailability.accountMismatch,
          'settings_account_mismatch',
        );
      }
      appSettings.validate();
      notifications.validate();
      autonomy.validate();
      memory.validate();
      return SettingsContextSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.settingsRegistry,
          LifeContextAvailability.available,
          LifeContextFreshness.current,
          true,
          4,
          syncStatus: 'aggregated',
          revision: appSettings.revision,
        ),
        automaticTravelCalculationEnabled:
            appSettings.automaticTravelCalculationEnabled,
        notificationsEnabled: notifications.enabled,
        notificationSoundEnabled: notifications.soundEnabled,
        notificationVibrationEnabled: notifications.vibrationEnabled,
        notificationBadgeEnabled: notifications.badgeEnabled,
        actionAutonomyMode: autonomy.mode.name,
        memoryGeneralMode: memory.generalMode.name,
        memoryHealthMode: memory.healthMode.name,
        planningStyle: _optional(appSettings.planningStyle),
        notificationLevel: _optional(appSettings.notificationLevel),
        spokenLanguage: _optional(appSettings.spokenLanguage),
        country: _optional(appSettings.country),
        timeZone: _optional(appSettings.timeZone),
      );
    } on Object {
      return _empty(
        request,
        LifeContextAvailability.unavailable,
        'settings_domain_unavailable',
      );
    }
  }

  SettingsContextSection _empty(
    LifeContextAdapterRequest request,
    LifeContextAvailability availability,
    String errorCode,
  ) =>
      SettingsContextSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.settingsRegistry,
          availability,
          LifeContextFreshness.unknown,
          true,
          0,
          errorCode: errorCode,
        ),
        automaticTravelCalculationEnabled: false,
        notificationsEnabled: false,
        notificationSoundEnabled: false,
        notificationVibrationEnabled: false,
        notificationBadgeEnabled: false,
        actionAutonomyMode: ActionAutonomyMode.suggestions.name,
        memoryGeneralMode: MemoryGeneralMode.askEveryTime.name,
        memoryHealthMode: MemoryHealthMode.disabled.name,
      );
}

final class ShoppingLifeContextAdapter implements LifeContextDomainAdapter {
  const ShoppingLifeContextAdapter({required ShoppingContextLoader load})
      : _load = load;

  final ShoppingContextLoader _load;

  @override
  LifeContextDomain get domain => LifeContextDomain.shopping;

  @override
  Future<ShoppingDomainSection> load(
    LifeContextAdapterRequest request,
  ) async {
    try {
      final source = await _load(request.accountScopeId);
      final active = <ShoppingContextItem>[];
      var legacyIndex = 0;
      for (final item in source.where((item) => !item.isBought)) {
        final title = item.title.trim();
        if (title.isEmpty) continue;
        final stableId = item.id?.trim();
        final id = stableId != null && stableId.isNotEmpty
            ? stableId
            : 'legacy-shopping-'
                '${item.createdAt.toUtc().microsecondsSinceEpoch}-'
                '${legacyIndex++}';
        active.add(ShoppingContextItem(
          id: id,
          title: title,
          isUrgent: item.isUrgent,
          createdAt: item.createdAt.toUtc().toIso8601String(),
          quantity: _optional(item.quantity),
          notes: _optional(item.notes),
        ));
      }
      active.sort((first, second) {
        if (first.isUrgent != second.isUrgent) {
          return first.isUrgent ? -1 : 1;
        }
        final created = first.createdAt.compareTo(second.createdAt);
        return created != 0 ? created : first.id.compareTo(second.id);
      });
      final truncated = active.length > LifeContextSourceBudgets.shoppingItems;
      final items = active
          .take(LifeContextSourceBudgets.shoppingItems)
          .toList(growable: false);
      return ShoppingDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.shoppingService,
          items.isEmpty
              ? LifeContextAvailability.empty
              : LifeContextAvailability.available,
          LifeContextFreshness.current,
          false,
          items.length,
          syncStatus: 'activeOnly',
          truncationState: truncated
              ? LifeContextTruncationState.truncated
              : LifeContextTruncationState.complete,
          warningCodes:
              truncated ? const ['shopping_source_truncated'] : const [],
        ),
        activeItems: items,
      );
    } on FormatException {
      return _empty(
        request,
        LifeContextAvailability.corrupted,
        'invalid_shopping_domain',
      );
    } on Object {
      return _empty(
        request,
        LifeContextAvailability.unavailable,
        'shopping_domain_unavailable',
      );
    }
  }

  ShoppingDomainSection _empty(
    LifeContextAdapterRequest request,
    LifeContextAvailability availability,
    String errorCode,
  ) =>
      ShoppingDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.shoppingService,
          availability,
          LifeContextFreshness.unknown,
          false,
          0,
          errorCode: errorCode,
        ),
      );
}

LifeContextSourceMetadata _metadata(
  LifeContextAdapterRequest request,
  LifeContextDomain domain,
  LifeContextSourceKind source,
  LifeContextAvailability availability,
  LifeContextFreshness freshness,
  bool isLocal,
  int itemCount, {
  int? revision,
  String? syncStatus,
  String? errorCode,
  LifeContextTruncationState truncationState =
      LifeContextTruncationState.complete,
  List<String> warningCodes = const [],
}) =>
    LifeContextSourceMetadata(
      domain: domain,
      source: source,
      readAt: request.readAt,
      availability: availability,
      freshness: freshness,
      isLocal: isLocal,
      itemCount: itemCount,
      revision: revision,
      syncStatus: syncStatus,
      errorCode: errorCode,
      truncationState: truncationState,
      warningCodes: warningCodes,
    );

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _routineScheduleIdentity(RoutineContextItem item) {
  final days = item.days.map(_routineWeekday).whereType<int>().toSet().toList()
    ..sort();
  final recurrence = item.recurrenceType == 'dated' ? 'dated' : 'weekly';
  return [
    item.humanPersonId?.trim() ?? '',
    _normalizedScheduleText(item.label),
    days.join(','),
    item.startTime?.trim() ?? '',
    item.endTime?.trim() ?? '',
    recurrence,
    if (recurrence == 'dated') item.anchorDateIso?.trim() ?? '',
  ].join('|');
}

int? _routineWeekday(String value) => switch (_normalizedScheduleText(value)) {
      '1' || 'lundi' => DateTime.monday,
      '2' || 'mardi' => DateTime.tuesday,
      '3' || 'mercredi' => DateTime.wednesday,
      '4' || 'jeudi' => DateTime.thursday,
      '5' || 'vendredi' => DateTime.friday,
      '6' || 'samedi' => DateTime.saturday,
      '7' || 'dimanche' => DateTime.sunday,
      _ => null,
    };

String _normalizedScheduleText(String? value) => (value ?? '')
    .trim()
    .toLowerCase()
    .replaceAll('é', 'e')
    .replaceAll('è', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('à', 'a')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('ï', 'i')
    .replaceAll('ô', 'o')
    .replaceAll('ù', 'u')
    .replaceAll('û', 'u');

LifeContextAvailability _humanAvailability(HumanModelSyncStatus status) =>
    switch (status) {
      HumanModelSyncStatus.synced => LifeContextAvailability.available,
      HumanModelSyncStatus.localOnly ||
      HumanModelSyncStatus.pendingUpload ||
      HumanModelSyncStatus.remoteChanged =>
        LifeContextAvailability.availableStale,
      HumanModelSyncStatus.migrationFailed ||
      HumanModelSyncStatus.corruptedLocal =>
        LifeContextAvailability.corrupted,
      HumanModelSyncStatus.unsupportedVersion =>
        LifeContextAvailability.unsupported,
    };
