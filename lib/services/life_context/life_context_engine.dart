import 'dart:async';

import '../../core/identity/entity_id_generator.dart';
import '../../core/identity/uuid_v7_entity_id_generator.dart';
import '../../models/life_context/identity_context.dart';
import '../../models/life_context/intent_context.dart';
import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_provenance.dart';
import '../../models/life_context/life_context_snapshot.dart';
import '../../models/life_context/notes_context.dart';
import '../../models/life_context/schedule_context.dart';
import '../../models/user_profile.dart';
import 'life_context_adapter.dart';
import 'life_context_memory_projection.dart';
import 'user_profile_life_context_mapper.dart';

typedef LifeContextProfileProjection = LifeContextSnapshot Function({
  required UserProfile profile,
  required DateTime generatedAt,
});

/// Read-only Life Context entry point.
///
/// Composes profile facts and normalized historical memories without owning
/// either source or persisting the resulting snapshot.
final class LifeContextEngine {
  final LifeContextProfileProjection _profileProjection;
  final LifeContextMemoryProjection _memoryProjection;
  final List<LifeContextDomainAdapter> _adapters;
  final String? Function()? _currentAccountScopeId;
  final EntityIdGenerator _snapshotIdGenerator;
  final Duration _adapterTimeout;

  LifeContextEngine({
    LifeContextProfileProjection? profileProjection,
    LifeContextMemoryProjection? memoryProjection,
    List<LifeContextDomainAdapter> adapters = const [],
    String? Function()? currentAccountScopeId,
    EntityIdGenerator snapshotIdGenerator = const UuidV7EntityIdGenerator(),
    Duration adapterTimeout = const Duration(seconds: 5),
  })  : _memoryProjection =
            memoryProjection ?? const HistoricalMemoryContextProjection(),
        _profileProjection =
            profileProjection ?? const UserProfileLifeContextMapper().map,
        _adapters = List.unmodifiable(adapters),
        _currentAccountScopeId = currentAccountScopeId,
        _snapshotIdGenerator = snapshotIdGenerator,
        _adapterTimeout = adapterTimeout;

  LifeContextSnapshot buildSnapshot({
    required UserProfile profile,
    required DateTime generatedAt,
    Iterable<Map<String, dynamic>> memories = const [],
  }) {
    final profileSnapshot =
        _profileProjection(profile: profile, generatedAt: generatedAt);
    if (memories.isEmpty) return profileSnapshot;
    return profileSnapshot.withMemory(_memoryProjection.project(memories));
  }

  Future<LifeContextSnapshot> buildCanonicalSnapshot({
    required String accountScopeId,
    DateTime? generatedAt,
    LifeContextCancellationToken? cancellationToken,
  }) async {
    final scope = accountScopeId.trim();
    final authenticatedScope = _currentAccountScopeId?.call()?.trim();
    if (scope.isEmpty ||
        authenticatedScope == null ||
        authenticatedScope.isEmpty) {
      throw const LifeContextEngineException('unauthenticated');
    }
    if (authenticatedScope != scope) {
      throw const LifeContextEngineException('account_mismatch');
    }
    if (cancellationToken?.isCancelled == true) {
      throw const LifeContextEngineException('cancelled');
    }
    final byDomain = <LifeContextDomain, LifeContextDomainAdapter>{};
    for (final adapter in _adapters) {
      if (byDomain.containsKey(adapter.domain)) {
        throw const LifeContextEngineException('duplicate_context_adapter');
      }
      byDomain[adapter.domain] = adapter;
    }
    if (byDomain.length != LifeContextDomain.values.length) {
      throw const LifeContextEngineException('missing_context_adapter');
    }

    final readAt = (generatedAt ?? DateTime.now()).toUtc();
    final request = LifeContextAdapterRequest(
      accountScopeId: scope,
      readAt: readAt,
    );
    final sections = await Future.wait(
      LifeContextDomain.values.map(
        (domain) => _loadBounded(
          byDomain[domain]!,
          request,
          cancellationToken,
        ),
      ),
    );
    if (cancellationToken?.isCancelled == true) {
      throw const LifeContextEngineException('cancelled');
    }

    final sectionByDomain = {
      for (final section in sections) section.domain: section,
    };
    _validateSharedHumanRevision(sectionByDomain);
    final globalState = _globalState(sections);
    final snapshot = LifeContextSnapshot(
      generatedAt: readAt,
      identity: const IdentityContext(),
      household: HouseholdContext(),
      places: const PlaceContext(),
      mobility: const MobilityContext(),
      work: WorkContext(),
      agenda: AgendaContext(),
      routines: RoutineContext(),
      goals: GoalContext(),
      preferences: PreferenceContext(
        wantsNotifications: LifeContextFact(
          value: false,
          provenance: LifeContextProvenance(
            sourceType: LifeContextSourceType.derived,
            evidenceType: LifeContextEvidenceType.derived,
            sourceId: 'canonicalCompatibilityShell',
          ),
        ),
      ),
      constraints: const ConstraintContext(),
      notes: const NotesContext(),
      accountScopeId: scope,
      snapshotId: _snapshotIdGenerator.generate(),
      globalState: globalState,
      human: sectionByDomain[LifeContextDomain.human]! as HumanContextSection,
      identityDomain:
          sectionByDomain[LifeContextDomain.identity]! as IdentityDomainSection,
      eventDomain:
          sectionByDomain[LifeContextDomain.event]! as EventDomainSection,
      taskDomain: sectionByDomain[LifeContextDomain.task]! as TaskDomainSection,
      routineDomain:
          sectionByDomain[LifeContextDomain.routine]! as RoutineDomainSection,
      memoryDomain:
          sectionByDomain[LifeContextDomain.memory]! as MemoryDomainSection,
    );
    snapshot.validateCanonical();
    return snapshot;
  }

  void _validateSharedHumanRevision(
    Map<LifeContextDomain, LifeContextDomainSection> sections,
  ) {
    final revisions = {
      sections[LifeContextDomain.human]?.metadata.revision,
      sections[LifeContextDomain.identity]?.metadata.revision,
      sections[LifeContextDomain.routine]?.metadata.revision,
    }..remove(null);
    if (revisions.length > 1) {
      throw const LifeContextEngineException(
        'source_changed_during_snapshot',
      );
    }
  }

  Future<LifeContextDomainSection> _loadBounded(
    LifeContextDomainAdapter adapter,
    LifeContextAdapterRequest request,
    LifeContextCancellationToken? cancellationToken,
  ) async {
    if (cancellationToken?.isCancelled == true) {
      throw const LifeContextEngineException('cancelled');
    }
    try {
      return await adapter.load(request).timeout(_adapterTimeout);
    } on TimeoutException {
      return _unavailable(adapter.domain, request, 'context_timeout');
    }
  }

  LifeContextGlobalState _globalState(
    List<LifeContextDomainSection> sections,
  ) {
    final unavailable = sections.where(
      (section) => {
        LifeContextAvailability.unavailable,
        LifeContextAvailability.corrupted,
        LifeContextAvailability.accountMismatch,
      }.contains(section.metadata.availability),
    );
    if (unavailable.length == sections.length) {
      return LifeContextGlobalState.unavailable;
    }
    return unavailable.isEmpty
        ? LifeContextGlobalState.complete
        : LifeContextGlobalState.partial;
  }

  LifeContextDomainSection _unavailable(
    LifeContextDomain domain,
    LifeContextAdapterRequest request,
    String errorCode,
  ) {
    final metadata = LifeContextSourceMetadata(
      domain: domain,
      source: switch (domain) {
        LifeContextDomain.human => LifeContextSourceKind.humanModelLocal,
        LifeContextDomain.identity => LifeContextSourceKind.identityLinks,
        LifeContextDomain.event => LifeContextSourceKind.eventService,
        LifeContextDomain.task => LifeContextSourceKind.taskService,
        LifeContextDomain.routine => LifeContextSourceKind.legacyProfileRoutine,
        LifeContextDomain.memory => LifeContextSourceKind.memoryFirestore,
      },
      readAt: request.readAt,
      availability: LifeContextAvailability.unavailable,
      freshness: LifeContextFreshness.unknown,
      isLocal: domain == LifeContextDomain.human ||
          domain == LifeContextDomain.identity ||
          domain == LifeContextDomain.routine,
      itemCount: 0,
      errorCode: errorCode,
    );
    return switch (domain) {
      LifeContextDomain.human =>
        HumanContextSection(metadata: metadata, primaryPersonId: null),
      LifeContextDomain.identity => IdentityDomainSection(metadata: metadata),
      LifeContextDomain.event => EventDomainSection(metadata: metadata),
      LifeContextDomain.task => TaskDomainSection(metadata: metadata),
      LifeContextDomain.routine => RoutineDomainSection(metadata: metadata),
      LifeContextDomain.memory => MemoryDomainSection(
          metadata: metadata,
          policyGeneralMode: 'askEveryTime',
          policyHealthMode: 'disabled',
          policyConfigured: false,
        ),
    };
  }
}

final class LifeContextCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

final class LifeContextEngineException implements Exception {
  const LifeContextEngineException(this.code);

  final String code;
}
