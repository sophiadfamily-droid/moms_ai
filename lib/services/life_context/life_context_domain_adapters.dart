import '../../models/event_model.dart';
import '../../models/human/human_model.dart';
import '../../models/human/human_model_persistence.dart';
import '../../models/life_context/life_context_domains.dart';
import '../../models/task_model.dart';
import '../../models/user_profile.dart';
import '../../models/memory_policy.dart';
import '../../models/memory_sync.dart';
import '../memory_sync_local_repository.dart';
import '../memory_consumption_policy.dart';
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
      );
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

  @override
  LifeContextDomain get domain => LifeContextDomain.event;

  @override
  Future<EventDomainSection> load(LifeContextAdapterRequest request) async {
    try {
      final source = await _load(request.accountScopeId);
      final syncStatuses =
          await _loadSyncStatuses?.call(request.accountScopeId) ?? const {};
      final items = source.map((event) {
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
        );
      }).toList()
        ..sort((a, b) {
          final date = a.startDateTimeIso.compareTo(b.startDateTimeIso);
          return date != 0 ? date : a.id.compareTo(b.id);
        });
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
      final items = source.map((task) {
        final id = task.id;
        if (id == null || id.trim().isEmpty) {
          throw const FormatException('task_missing_stable_id');
        }
        return TaskContextItem(
          id: id,
          title: task.title,
          isCompleted: task.isDone,
          dueDate: _optional(task.dueDate),
          durationMinutes: null,
          syncStatus: syncMetadata?.itemSyncStatuses[id] ?? 'unknown',
        );
      }).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
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
}

final class RoutineLifeContextAdapter implements LifeContextDomainAdapter {
  const RoutineLifeContextAdapter({required HumanContextLoader loadHuman})
      : _loadHuman = loadHuman;

  final HumanContextLoader _loadHuman;

  @override
  LifeContextDomain get domain => LifeContextDomain.routine;

  @override
  Future<RoutineDomainSection> load(
    LifeContextAdapterRequest request,
  ) async {
    try {
      final state = await _loadHuman(request.accountScopeId);
      if (state == null) {
        return RoutineDomainSection(
          metadata: _metadata(
            request,
            domain,
            LifeContextSourceKind.legacyProfileRoutine,
            LifeContextAvailability.empty,
            LifeContextFreshness.unknown,
            true,
            0,
          ),
        );
      }
      if (state.model.accountScopeId != request.accountScopeId) {
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
      final profile = UserProfile.fromJson(
        Map<String, dynamic>.from(state.model.legacyProfile),
      );
      final routines = <RoutineContextItem>[];
      for (var index = 0; index < profile.personalActivities.length; index++) {
        final activity = profile.personalActivities[index];
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
            ),
          );
        } else {
          for (var rangeIndex = 0;
              rangeIndex < activity.timeRanges.length;
              rangeIndex++) {
            final range = activity.timeRanges[rangeIndex];
            routines.add(
              RoutineContextItem(
                id: 'personalActivity:$index:$rangeIndex',
                source: 'legacyProfile.personalActivities',
                label: _optional(activity.title),
                days: List<String>.of(activity.days)..sort(),
                startTime: _optional(range.startTime),
                endTime: _optional(range.endTime),
                travelMinutes: int.tryParse(activity.travelMinutes),
              ),
            );
          }
        }
      }
      for (var childIndex = 0;
          childIndex < profile.children.length;
          childIndex++) {
        final child = profile.children[childIndex];
        for (var rangeIndex = 0;
            rangeIndex < child.schoolTimeRanges.length;
            rangeIndex++) {
          final range = child.schoolTimeRanges[rangeIndex];
          routines.add(
            RoutineContextItem(
              id: 'schoolSchedule:$childIndex:$rangeIndex',
              source: 'legacyProfile.schoolTimeRanges',
              label: _optional(range.label),
              days: const [],
              startTime: _optional(range.startTime),
              endTime: _optional(range.endTime),
              travelMinutes: int.tryParse(range.travelMinutes),
              humanPersonId: _optional(child.humanPersonId),
            ),
          );
        }
      }
      routines.sort((a, b) => a.id.compareTo(b.id));
      return RoutineDomainSection(
        metadata: _metadata(
          request,
          domain,
          LifeContextSourceKind.legacyProfileRoutine,
          routines.isEmpty
              ? LifeContextAvailability.empty
              : LifeContextAvailability.availableStale,
          routines.isEmpty
              ? LifeContextFreshness.unknown
              : LifeContextFreshness.stale,
          true,
          routines.length,
          revision: state.knownCloudRevision,
          syncStatus: 'legacyCompatibility',
        ),
        routines: routines,
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
      final memories = MemoryConsumptionPolicy.consumable(
        context.memories,
        referenceDate: request.readAt,
      )
          .map(
            (memory) => MemoryContextItem(
              id: memory.id,
              text: memory.text,
              category: memory.category,
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
            ),
          )
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
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
    );

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

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
