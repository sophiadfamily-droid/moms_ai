import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_candidate.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_reference.dart';
import 'package:moms_ai/core/identity/entity_resolution.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_lifecycle_state.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/identity/identity_application_models.dart';
import 'package:moms_ai/services/identity/identity_clarification_service.dart';
import 'package:moms_ai/services/identity/identity_creation_service.dart';

void main() {
  group('ConversationCoordinator Identity clarification', () {
    test('stores one typed clarification and returns its safe question', () {
      final fixture = _fixture();
      final started = fixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );

      expect(started?.message, contains('1. Person A'));
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityClarification,
      );
      expect(
        fixture.coordinator.state.pendingAction?.identityClarification
            ?.clarificationId,
        'clarification-1',
      );
    });

    test('intercepts a selection before context, backend, and actions',
        () async {
      final fixture = _fixture();
      fixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );
      var actionCalls = 0;

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: '2', profile: _profile()),
        executeAction: (_) async {
          actionCalls++;
          return const ConversationActionOutcome();
        },
      );

      expect(
        outcome?.identityClarificationResult?.status,
        IdentityClarificationStatus.resolved,
      );
      expect(
        outcome?.identityClarificationResult?.resolvedEntityId,
        'entity-2',
      );
      expect(outcome?.request, isNull);
      expect(fixture.backend.calls, 0);
      expect(fixture.context.buildCalls, 0);
      expect(fixture.context.savedMemories, isEmpty);
      expect(actionCalls, 0);
      expect(fixture.coordinator.state.pendingAction, isNull);
    });

    test('keeps an ambiguous answer pending and asks for a number', () async {
      final fixture = _fixture();
      fixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: 'maybe', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(
        outcome?.identityClarificationResult?.status,
        IdentityClarificationStatus.stillAmbiguous,
      );
      expect(outcome?.reply, contains('numéro'));
      expect(fixture.coordinator.state.pendingAction, isNotNull);
      expect(fixture.backend.calls, 0);
    });

    test('cancels without resolving or resuming an action', () async {
      final fixture = _fixture();
      fixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: 'annule', profile: _profile()),
        executeAction: (_) async => throw StateError('must not execute'),
      );

      expect(
        outcome?.identityClarificationResult?.status,
        IdentityClarificationStatus.cancelled,
      );
      expect(outcome?.identityClarificationResult?.resolvedEntityId, isNull);
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.backend.calls, 0);
    });

    test('expires and clears without calling the backend', () async {
      var clock = now;
      final fixture = _fixture(now: () => clock);
      fixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );
      clock = now.add(const Duration(minutes: 15));

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: '1', profile: _profile()),
        executeAction: (_) async => throw StateError('must not execute'),
      );

      expect(
        outcome?.identityClarificationResult?.status,
        IdentityClarificationStatus.expired,
      );
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.backend.calls, 0);
    });

    test('a repeated direct resolution is ignored after success', () async {
      final fixture = _fixture();
      fixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );

      final first = await fixture.coordinator
          .resolvePendingIdentityClarification(answer: '1');
      final repeated = await fixture.coordinator
          .resolvePendingIdentityClarification(answer: '1');

      expect(first?.identityClarificationResult?.resolvedEntityId, 'entity-1');
      expect(repeated, isNull);
    });

    test('does not collide with event or memory confirmations', () {
      final eventFixture = _fixture();
      eventFixture.coordinator.setPendingEventConfirmation(_event());
      expect(
        eventFixture.coordinator.beginIdentityClarification(
          applicationResult: _ambiguousResult(),
          request: _identityRequest(),
        ),
        isNull,
      );
      expect(
        eventFixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventConfirmation,
      );

      final memoryFixture = _fixture();
      memoryFixture.coordinator.setPendingMemoryConfirmation(
        const MemoryConfirmationRequest(
          action: MemoryLifecycleAction.confirm,
          proposalId: 'proposal-1',
          prompt: 'Confirm',
          changeType: 'proposal',
          sensitivity: LifeContextSensitivity.standard,
          consequence: 'Activate after confirmation',
        ),
        createdAt: now,
      );
      expect(
        memoryFixture.coordinator.beginIdentityClarification(
          applicationResult: _ambiguousResult(),
          request: _identityRequest(),
        ),
        isNull,
      );
      expect(
        memoryFixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.memoryConfirmation,
      );

      final identityFixture = _fixture();
      identityFixture.coordinator.beginIdentityClarification(
        applicationResult: _ambiguousResult(),
        request: _identityRequest(),
      );
      identityFixture.coordinator.setPendingMemoryConfirmation(
        const MemoryConfirmationRequest(
          action: MemoryLifecycleAction.confirm,
          proposalId: 'proposal-1',
          prompt: 'Confirm',
          changeType: 'proposal',
          sensitivity: LifeContextSensitivity.standard,
          consequence: 'Activate after confirmation',
        ),
        createdAt: now,
      );
      expect(
        identityFixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityClarification,
      );
    });
  });

  group('ConversationCoordinator Identity creation', () {
    test('stores a proposal without writing and confirms exactly once',
        () async {
      final fixture = _creationFixture();
      final started = fixture.coordinator.beginIdentityCreation(
        applicationResult: _notFoundResult(),
        request: _creationRequest(),
      );

      expect(started?.message, contains('Person A'));
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityCreation,
      );
      expect(
        await fixture.repository.findById(
          scope: IdentityAccountScope('account-a'),
          entityId: 'entity-new',
        ),
        isNull,
      );

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: 'oui', profile: _profile()),
        executeAction: (_) async => throw StateError('must not execute'),
      );
      expect(
        outcome?.identityCreationResult?.status,
        IdentityCreationStatus.created,
      );
      expect(outcome?.reply, contains('bien été enregistrée'));
      expect(fixture.backend.calls, 0);
      expect(fixture.context.buildCalls, 0);
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(
        await fixture.repository.findById(
          scope: IdentityAccountScope('account-a'),
          entityId: 'entity-new',
        ),
        isNotNull,
      );
      expect(
        await fixture.coordinator.resolvePendingIdentityCreation(answer: 'oui'),
        isNull,
      );
    });

    test('ambiguous response stays pending and refusal writes nothing',
        () async {
      final fixture = _creationFixture();
      fixture.coordinator.beginIdentityCreation(
        applicationResult: _notFoundResult(),
        request: _creationRequest(),
      );

      final ambiguous = await fixture.coordinator.send(
        input: ConversationInput(message: 'peut-être', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      expect(
        ambiguous?.identityCreationResult?.status,
        IdentityCreationStatus.stillPending,
      );
      expect(fixture.coordinator.state.pendingAction, isNotNull);

      final refused = await fixture.coordinator.send(
        input: ConversationInput(message: 'non', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      expect(
        refused?.identityCreationResult?.status,
        IdentityCreationStatus.cancelled,
      );
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(
        await fixture.repository.findById(
          scope: IdentityAccountScope('account-a'),
          entityId: 'entity-new',
        ),
        isNull,
      );
      expect(fixture.backend.calls, 0);
    });

    test('a normal mention cannot initiate Identity creation', () async {
      final fixture = _creationFixture();
      final outcome = await fixture.coordinator.send(
        input: ConversationInput(
          message: 'J’ai parlé avec Person A',
          profile: _profile(),
        ),
        executeAction: (_) async => const ConversationActionOutcome(),
      );

      expect(outcome?.reply, 'Backend');
      expect(outcome?.identityCreationResult, isNull);
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(
        await fixture.repository.findById(
          scope: IdentityAccountScope('account-a'),
          entityId: 'entity-new',
        ),
        isNull,
      );
    });
  });
}

final now = DateTime.utc(2026, 7, 21, 10);
const source = EntitySource(type: EntitySourceType.user);

_CoordinatorFixture _fixture({DateTime Function()? now}) {
  final backend = _FakeBackend();
  final context = _FakeContext();
  return _CoordinatorFixture(
    backend: backend,
    context: context,
    coordinator: ConversationCoordinator(
      backend: backend,
      contextProvider: context,
      identityClarificationService: IdentityClarificationService(
        idGenerator: _FakeIdGenerator(),
        now: now ?? () => IdentityConversationTestClock.value,
      ),
    ),
  );
}

abstract final class IdentityConversationTestClock {
  static DateTime get value => now;
}

IdentityApplicationResult _ambiguousResult() =>
    IdentityApplicationResult.fromResolution(
      EntityResolution.ambiguous(
        candidates: [
          EntityCandidate(entity: _entity('entity-1', 'Person A')),
          EntityCandidate(entity: _entity('entity-2', 'Person B')),
        ],
        signals: const [EntityMatchSignal.multipleCandidates],
        reasonCode: 'multiple_candidates',
      ),
    );

IdentityApplicationResult _notFoundResult() =>
    IdentityApplicationResult.fromResolution(
      EntityResolution.notFound(reasonCode: 'not_found'),
    );

IdentityCreationRequest _creationRequest() => IdentityCreationRequest(
      scope: IdentityAccountScope('account-a'),
      entityType: EntityType.person,
      canonicalLabel: 'Person A',
      source: source,
    );

IdentityResolutionRequest _identityRequest() => IdentityResolutionRequest(
      scope: IdentityAccountScope('account-a'),
      reference: EntityReference.text(
        value: 'Person',
        kind: EntityReferenceKind.alias,
        source: source,
      ),
    );

LifeEntity _entity(String id, String label) => LifeEntity.fromLabel(
      id: id,
      type: EntityType.person,
      canonicalLabel: label,
      source: source,
      createdAt: now,
      updatedAt: now,
    );

UserProfile _profile() => UserProfile(
      firstName: 'User',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );

EventModel _event() => EventModel(
      title: 'Activity',
      date: '2026-07-21',
      time: '10:00',
      notes: '',
      category: 'Personal',
      createdAt: now,
      startDateTimeIso: '2026-07-21T10:00:00Z',
      durationMinutes: 30,
    );

final class _FakeIdGenerator implements EntityIdGenerator {
  @override
  String generate() => 'clarification-1';
}

final class _CreationIdGenerator implements EntityIdGenerator {
  var _index = 0;

  @override
  String generate() => ['proposal-new', 'entity-new'][_index++];
}

final class _FakeBackend implements ChatBackendClient {
  int calls = 0;

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    calls++;
    return const ChatBackendResponse(
        reply: 'Backend', actions: [], memories: []);
  }
}

final class _FakeContext implements ConversationContextProvider {
  int buildCalls = 0;
  final List<Object?> savedMemories = [];

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    buildCalls++;
    return ChatBackendRequest(
      message: message,
      profile: const {},
      profileContext: const {},
      memories: const [],
      memoryReasoning: const [],
      events: const [],
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {
    savedMemories.add(memory);
  }
}

final class _CoordinatorFixture {
  final ConversationCoordinator coordinator;
  final _FakeBackend backend;
  final _FakeContext context;

  const _CoordinatorFixture({
    required this.coordinator,
    required this.backend,
    required this.context,
  });
}

final class _CreationFixture {
  final ConversationCoordinator coordinator;
  final FakeIdentityRepository repository;
  final _FakeBackend backend;
  final _FakeContext context;

  const _CreationFixture({
    required this.coordinator,
    required this.repository,
    required this.backend,
    required this.context,
  });
}

_CreationFixture _creationFixture() {
  final repository = FakeIdentityRepository();
  final backend = _FakeBackend();
  final context = _FakeContext();
  return _CreationFixture(
    repository: repository,
    backend: backend,
    context: context,
    coordinator: ConversationCoordinator(
      backend: backend,
      contextProvider: context,
      identityCreationService: IdentityCreationService(
        readRepository: repository,
        writeRepository: repository,
        idGenerator: _CreationIdGenerator(),
        now: () => now,
      ),
    ),
  );
}
