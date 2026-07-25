import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/models/life_context/identity_context.dart';
import 'package:moms_ai/models/life_context/intent_context.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/life_context_snapshot.dart';
import 'package:moms_ai/models/life_context/notes_context.dart';
import 'package:moms_ai/models/life_context/schedule_context.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/services/life_context/life_context_adapter.dart';
import 'package:moms_ai/services/life_context/life_context_domain_adapters.dart';
import 'package:moms_ai/services/life_context/life_context_projection_engine.dart';
import 'package:moms_ai/services/life_context/memory_projection_backend_serializer.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  test('adaptateur Memory conserve legacy, politique et ordre déterministe',
      () async {
    final section = await MemoryLifeContextAdapter(
      loadMemories: (_) async => [
        {
          'id': 'memory-b',
          'text': 'Préférence B',
          'category': 'preference',
          'source': 'user',
          'lifecycleState': 'active',
          'confirmationStatus': 'confirmed',
          'unknownLegacyField': 'préservé dans le lecteur legacy',
        },
        {
          'id': 'memory-a',
          'text': 'Préférence A',
          'category': 'preference',
          'source': 'user',
          'lifecycleState': 'proposed',
        },
        {
          'id': 'memory-chat-quarantined',
          'text': 'Préférence historique ambiguë',
          'normalizedText': 'préférence historique ambiguë',
          'category': 'preference',
          'importance': 2,
          'createdAt': now.subtract(const Duration(days: 30)),
          'updatedAt': now.subtract(const Duration(days: 30)),
          'source': 'chat',
        },
      ],
      loadPolicy: (scope) async => MemoryPolicy(
        accountScopeId: scope,
        generalMode: MemoryGeneralMode.paused,
        healthMode: MemoryHealthMode.disabled,
        healthConsentGranted: false,
        changedAt: now,
        changeSource: MemoryPolicyChangeSource.explicitUserSetting,
      ),
    ).load(
      LifeContextAdapterRequest(
        accountScopeId: 'account-a',
        readAt: now,
      ),
    );

    expect(section.domain, LifeContextDomain.memory);
    expect(section.memories.map((item) => item.id), ['memory-b']);
    expect(section.policyGeneralMode, 'paused');
    expect(section.metadata.syncStatus, 'paused');
    expect(section.metadata.itemCount, 1);
  });

  test('scope incorrect et corruption restent explicites', () async {
    final mismatch = await MemoryLifeContextAdapter(
      loadMemories: (_) async => const [],
      loadPolicy: (_) async => MemoryPolicy.restrictiveDefault(
        accountScopeId: 'account-b',
        changedAt: now,
      ),
    ).load(
      LifeContextAdapterRequest(
        accountScopeId: 'account-a',
        readAt: now,
      ),
    );
    expect(
      mismatch.metadata.availability,
      LifeContextAvailability.accountMismatch,
    );
  });

  test(
      'Conversation borne Memory et exclut santé, rejet, expiration et doublon',
      () {
    final snapshot = _snapshot(now);
    final projection = LifeContextProjectionEngine(
      projectionIdGenerator: const _Id(),
    ).build(
      snapshot: snapshot,
      contract: LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.conversation,
      ),
    );
    final memorySection = projection.sections.singleWhere(
      (section) => section.type == LifeContextProjectionSectionType.memory,
    );
    expect(
        memorySection.items.map((item) => item.id), ['memory:memory:active']);
    expect(memorySection.budgetUsed, lessThanOrEqualTo(30));
    final serialized =
        MemoryProjectionBackendSerializer.serializeProjection(memorySection);
    expect(serialized, hasLength(1));
    expect(serialized.single.keys, {
      'text',
      'category',
      'importance',
      'confirmationStatus',
      'source',
    });
    expect(serialized.toString(), isNot(contains('medical-secret')));
    expect(serialized.toString(), isNot(contains('conversation-source')));
  });

  test('Planning exclut toute mémoire libre et conserve Routine séparée', () {
    final projection = LifeContextProjectionEngine(
      projectionIdGenerator: const _Id(),
    ).build(
      snapshot: _snapshot(now),
      contract: LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.planning,
      ),
    );
    expect(
      projection.sections.where(
        (section) => section.type == LifeContextProjectionSectionType.memory,
      ),
      isEmpty,
    );
    expect(
      projection.sections.singleWhere(
        (section) => section.type == LifeContextProjectionSectionType.routine,
      ),
      isNotNull,
    );
  });
}

LifeContextSnapshot _snapshot(DateTime now) {
  LifeContextSourceMetadata metadata(
    LifeContextDomain domain,
    LifeContextSourceKind source, {
    int count = 0,
  }) =>
      LifeContextSourceMetadata(
        domain: domain,
        source: source,
        readAt: now,
        availability: count == 0
            ? LifeContextAvailability.empty
            : LifeContextAvailability.available,
        freshness: LifeContextFreshness.current,
        isLocal: false,
        itemCount: count,
      );

  return LifeContextSnapshot(
    generatedAt: now,
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
        ),
      ),
    ),
    constraints: const ConstraintContext(),
    notes: const NotesContext(),
    accountScopeId: 'account-a',
    snapshotId: 'snapshot-a',
    globalState: LifeContextGlobalState.complete,
    human: HumanContextSection(
      metadata: metadata(
        LifeContextDomain.human,
        LifeContextSourceKind.humanModelLocal,
      ),
      primaryPersonId: null,
    ),
    identityDomain: IdentityDomainSection(
      metadata: metadata(
        LifeContextDomain.identity,
        LifeContextSourceKind.identityLinks,
      ),
    ),
    eventDomain: EventDomainSection(
      metadata: metadata(
        LifeContextDomain.event,
        LifeContextSourceKind.eventService,
      ),
    ),
    taskDomain: TaskDomainSection(
      metadata: metadata(
        LifeContextDomain.task,
        LifeContextSourceKind.taskService,
      ),
    ),
    routineDomain: RoutineDomainSection(
      metadata: metadata(
        LifeContextDomain.routine,
        LifeContextSourceKind.legacyProfileRoutine,
      ),
    ),
    memoryDomain: MemoryDomainSection(
      metadata: metadata(
        LifeContextDomain.memory,
        LifeContextSourceKind.memoryFirestore,
        count: 5,
      ),
      policyGeneralMode: 'automatic',
      policyHealthMode: 'disabled',
      policyConfigured: true,
      memories: [
        MemoryContextItem(
          id: 'active',
          text: 'Préférence active',
          category: 'preference',
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'memory',
          sensitivity: 'standard',
          isExplicitHealth: false,
          createdAt: now,
        ),
        MemoryContextItem(
          id: 'health',
          text: 'medical-secret',
          category: 'health',
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'memory',
          sensitivity: 'sensitive',
          isExplicitHealth: true,
        ),
        const MemoryContextItem(
          id: 'rejected',
          text: 'Rejected',
          category: 'preference',
          status: 'rejected',
          confirmation: 'rejected',
          provenance: 'memory',
          sensitivity: 'standard',
          isExplicitHealth: false,
        ),
        MemoryContextItem(
          id: 'expired',
          text: 'Expired',
          category: 'preference',
          status: 'expired',
          confirmation: 'obsolete',
          provenance: 'memory',
          sensitivity: 'standard',
          isExplicitHealth: false,
          validUntil: now.subtract(const Duration(days: 1)),
        ),
        const MemoryContextItem(
          id: 'structured',
          text: 'Routine duplicate',
          category: 'routine',
          status: 'active',
          confirmation: 'confirmed',
          provenance: 'memory',
          sensitivity: 'standard',
          isExplicitHealth: false,
          structuredDomain: 'routine',
          structuredReferenceId: 'routine-a',
        ),
      ],
    ),
  );
}

final class _Id implements EntityIdGenerator {
  const _Id();

  @override
  String generate() => 'projection-a';
}
