import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_reference.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/identity_engine.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';
import 'package:moms_ai/repositories/identity/identity_repository_result.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/identity/identity_action_binding_service.dart';
import 'package:moms_ai/services/identity/identity_application_models.dart';
import 'package:moms_ai/services/identity/identity_application_service.dart';
import 'package:moms_ai/services/identity/identity_clarification_service.dart';
import 'package:moms_ai/services/identity/identity_creation_service.dart';

void main() {
  group('event participant action binding', () {
    test('attaches a directly resolved identity without pending state',
        () async {
      final fixture = await _fixture([_entity()]);
      final result = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(fixture.scope, 'entity-1'),
        continuation: _continuation(),
        creationRequest: _creationRequest(fixture.scope, 'Person A'),
      );

      expect(
        result.identityActionBindingResult?.status,
        IdentityActionBindingStatus.attached,
      );
      expect(result.identityActionBindingResult?.resolvedEntityId, 'entity-1');
      expect(
          result.identityActionBindingResult?.actionDraftId, 'event-draft-1');
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.repository.writeCalls, 0);
      expect(fixture.backend.calls, 0);
    });

    test('returns alreadyApplied for a repeated direct draft binding',
        () async {
      final fixture = await _fixture([_entity()]);
      final request = _idRequest(fixture.scope, 'entity-1');
      final continuation = _continuation();

      final first = await fixture.coordinator.beginIdentityActionBinding(
        request: request,
        continuation: continuation,
      );
      final repeated = await fixture.coordinator.beginIdentityActionBinding(
        request: request,
        continuation: continuation,
      );

      expect(
        first.identityActionBindingResult?.status,
        IdentityActionBindingStatus.attached,
      );
      expect(
        repeated.identityActionBindingResult?.status,
        IdentityActionBindingStatus.alreadyApplied,
      );
      expect(repeated.identityActionBindingResult?.resolvedEntityId, isNull);
      expect(fixture.repository.writeCalls, 0);
    });

    test('does not attach missing, incompatible, or failed resolutions',
        () async {
      final fixture = await _fixture([_entity()]);
      final missing = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(fixture.scope, 'missing'),
        continuation: _continuation(actionDraftId: 'event-draft-missing'),
      );
      final wrongType = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(
          fixture.scope,
          'entity-1',
          expectedType: EntityType.place,
        ),
        continuation: _continuation(actionDraftId: 'event-draft-type'),
        creationRequest: _creationRequest(fixture.scope, 'Person A'),
      );
      fixture.repository.failReads = true;
      final failed = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(fixture.scope, 'entity-1'),
        continuation: _continuation(actionDraftId: 'event-draft-failure'),
      );

      for (final result in [missing, wrongType, failed]) {
        expect(
          result.identityActionBindingResult?.status,
          IdentityActionBindingStatus.invalid,
        );
        expect(result.identityActionBindingResult?.resolvedEntityId, isNull);
      }
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.repository.writeCalls, 0);
    });

    test('notFound starts creation only with compatible explicit facts',
        () async {
      final fixture = await _fixture(const []);
      final request = _textRequest(fixture.scope, 'Person A');
      final started = await fixture.coordinator.beginIdentityActionBinding(
        request: request,
        continuation: _continuation(),
        creationRequest: _creationRequest(fixture.scope, 'Person A'),
      );

      expect(
        started.identityActionBindingResult?.status,
        IdentityActionBindingStatus.pendingCreation,
      );
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityCreation,
      );
      expect(
        fixture.coordinator.state.pendingAction?.identityCreation?.actionBinding
            ?.continuation.actionDraftId,
        'event-draft-1',
      );
      expect(fixture.repository.writeCalls, 0);

      final absentFacts = await (await _fixture(const []))
          .coordinator
          .beginIdentityActionBinding(
            request: request,
            continuation: _continuation(actionDraftId: 'event-draft-2'),
          );
      expect(
        absentFacts.identityActionBindingResult?.status,
        IdentityActionBindingStatus.invalid,
      );
    });

    test('mismatched creation facts never start a proposal', () async {
      final fixture = await _fixture(const []);
      final result = await fixture.coordinator.beginIdentityActionBinding(
        request: _textRequest(fixture.scope, 'Person A'),
        continuation: _continuation(),
        creationRequest: _creationRequest(fixture.scope, 'Person B'),
      );

      expect(result.identityActionBindingResult?.status,
          IdentityActionBindingStatus.invalid);
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.repository.writeCalls, 0);
    });

    test('confirmed creation attaches the draft without executing its action',
        () async {
      final fixture = await _fixture(const []);
      await fixture.coordinator.beginIdentityActionBinding(
        request: _textRequest(fixture.scope, 'Person A'),
        continuation: _continuation(),
        creationRequest: _creationRequest(fixture.scope, 'Person A'),
      );
      var actionCalls = 0;

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: 'oui', profile: _profile()),
        executeAction: (_) async {
          actionCalls++;
          return const ConversationActionOutcome();
        },
      );

      expect(outcome?.identityCreationResult?.status,
          IdentityCreationStatus.created);
      expect(outcome?.identityActionBindingResult?.status,
          IdentityActionBindingStatus.attached);
      expect(outcome?.identityActionBindingResult?.resolvedEntityId,
          'entity-created');
      expect(
          outcome?.identityActionBindingResult?.actionDraftId, 'event-draft-1');
      expect(fixture.repository.writeCalls, 1);
      expect(actionCalls, 0);
      expect(fixture.backend.calls, 0);
      expect(fixture.context.buildCalls, 0);
      final repeated = await fixture.coordinator.beginIdentityActionBinding(
        request: _textRequest(fixture.scope, 'Person A'),
        continuation: _continuation(),
        creationRequest: _creationRequest(fixture.scope, 'Person A'),
      );
      expect(repeated.identityActionBindingResult?.status,
          IdentityActionBindingStatus.alreadyApplied);
      expect(fixture.repository.writeCalls, 1);
    });

    test('creation refusal, ambiguity, and expiration execute no action',
        () async {
      for (final answer in ['non', 'peut-être']) {
        final fixture = await _fixture(const []);
        await fixture.coordinator.beginIdentityActionBinding(
          request: _textRequest(fixture.scope, 'Person A'),
          continuation: _continuation(),
          creationRequest: _creationRequest(fixture.scope, 'Person A'),
        );
        final outcome = await fixture.coordinator.send(
          input: ConversationInput(message: answer, profile: _profile()),
          executeAction: (_) async => throw StateError('must not execute'),
        );
        expect(fixture.repository.writeCalls, 0);
        expect(fixture.backend.calls, 0);
        expect(outcome?.identityActionBindingResult?.resolvedEntityId, isNull);
      }

      var clock = now;
      final expired = await _fixture(const [], now: () => clock);
      await expired.coordinator.beginIdentityActionBinding(
        request: _textRequest(expired.scope, 'Person A'),
        continuation: _continuation(),
        creationRequest: _creationRequest(expired.scope, 'Person A'),
      );
      clock = now.add(const Duration(minutes: 15));
      final outcome = await expired.coordinator.send(
        input: ConversationInput(message: 'oui', profile: _profile()),
        executeAction: (_) async => throw StateError('must not execute'),
      );
      expect(outcome?.identityCreationResult?.status,
          IdentityCreationStatus.expired);
      expect(expired.repository.writeCalls, 0);
      expect(expired.backend.calls, 0);
    });

    test('keeps a continuation through ambiguity and attaches after selection',
        () async {
      final fixture = await _fixture([
        _entity(id: 'entity-1', label: 'Person A', alias: 'Shared'),
        _entity(id: 'entity-2', label: 'Person B', alias: 'Shared'),
      ]);
      final started = await fixture.coordinator.beginIdentityActionBinding(
        request: _textRequest(fixture.scope, 'Shared'),
        continuation: _continuation(),
        creationRequest: _creationRequest(fixture.scope, 'Shared'),
      );

      expect(
        started.identityActionBindingResult?.status,
        IdentityActionBindingStatus.pendingClarification,
      );
      final pending = fixture.coordinator.state.pendingAction
          ?.identityClarification?.actionBinding;
      expect(pending?.continuation.actionDraftId, 'event-draft-1');
      expect(
          pending?.continuation.target, IdentityActionTarget.eventParticipant);

      var actionCalls = 0;
      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: '2', profile: _profile()),
        executeAction: (_) async {
          actionCalls++;
          return const ConversationActionOutcome();
        },
      );

      expect(
        outcome?.identityActionBindingResult?.status,
        IdentityActionBindingStatus.attached,
      );
      expect(
          outcome?.identityActionBindingResult?.resolvedEntityId, 'entity-2');
      expect(
          outcome?.identityActionBindingResult?.actionDraftId, 'event-draft-1');
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(actionCalls, 0);
      expect(fixture.backend.calls, 0);
      expect(fixture.context.buildCalls, 0);
      expect(fixture.repository.writeCalls, 0);
    });

    test('cancellation preserves an unresolved draft and executes nothing',
        () async {
      final fixture = await _ambiguousFixture();
      await fixture.coordinator.beginIdentityActionBinding(
        request: _textRequest(fixture.scope, 'Shared'),
        continuation: _continuation(),
      );

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: 'annule', profile: _profile()),
        executeAction: (_) async => throw StateError('must not execute'),
      );

      expect(
        outcome?.identityActionBindingResult?.status,
        IdentityActionBindingStatus.cancelled,
      );
      expect(outcome?.identityActionBindingResult?.resolvedEntityId, isNull);
      expect(
          outcome?.identityActionBindingResult?.actionDraftId, 'event-draft-1');
      expect(fixture.backend.calls, 0);
      expect(fixture.repository.writeCalls, 0);
    });

    test('expiration preserves an unresolved draft and executes nothing',
        () async {
      var clock = now;
      final fixture = await _ambiguousFixture(now: () => clock);
      await fixture.coordinator.beginIdentityActionBinding(
        request: _textRequest(fixture.scope, 'Shared'),
        continuation: _continuation(),
      );
      clock = now.add(const Duration(minutes: 15));

      final outcome = await fixture.coordinator.send(
        input: ConversationInput(message: '1', profile: _profile()),
        executeAction: (_) async => throw StateError('must not execute'),
      );

      expect(
        outcome?.identityActionBindingResult?.status,
        IdentityActionBindingStatus.expired,
      );
      expect(outcome?.identityActionBindingResult?.resolvedEntityId, isNull);
      expect(fixture.backend.calls, 0);
    });

    test('does not replace an existing event confirmation', () async {
      final fixture = await _fixture([_entity()]);
      fixture.coordinator.setPendingEventConfirmation(_event());

      final result = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(fixture.scope, 'entity-1'),
        continuation: _continuation(),
      );

      expect(
        result.identityActionBindingResult?.diagnosticCode,
        'pending_action_exists',
      );
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventConfirmation,
      );
    });

    test('isolates accounts and distinct action drafts', () async {
      final fixture = await _fixture([_entity()]);
      final otherScope = IdentityAccountScope('account-b');
      final foreign = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(otherScope, 'entity-1'),
        continuation: _continuation(actionDraftId: 'event-draft-2'),
      );
      final local = await fixture.coordinator.beginIdentityActionBinding(
        request: _idRequest(fixture.scope, 'entity-1'),
        continuation: _continuation(actionDraftId: 'event-draft-1'),
      );

      expect(foreign.identityActionBindingResult?.resolvedEntityId, isNull);
      expect(local.identityActionBindingResult?.resolvedEntityId, 'entity-1');
      expect(
        local.identityActionBindingResult?.actionDraftId,
        isNot(foreign.identityActionBindingResult?.actionDraftId),
      );
    });
  });
}

final now = DateTime.utc(2026, 7, 21, 10);
const source = EntitySource(type: EntitySourceType.user);

Future<_Fixture> _ambiguousFixture({DateTime Function()? now}) => _fixture([
      _entity(id: 'entity-1', label: 'Person A', alias: 'Shared'),
      _entity(id: 'entity-2', label: 'Person B', alias: 'Shared'),
    ], now: now);

Future<_Fixture> _fixture(
  List<LifeEntity> entities, {
  DateTime Function()? now,
}) async {
  final scope = IdentityAccountScope('account-a');
  final repository = _ReadSpyRepository();
  await repository.seed(scope, entities);
  final backend = _FakeBackend();
  final context = _FakeContext();
  final coordinator = ConversationCoordinator(
    backend: backend,
    contextProvider: context,
    identityApplicationService: IdentityApplicationService(
      repository: repository,
      engine: const IdentityEngine(),
      now: now ?? () => IdentityActionBindingTestClock.value,
    ),
    identityClarificationService: IdentityClarificationService(
      idGenerator: const _FixedIdGenerator('clarification-1'),
      now: now ?? () => IdentityActionBindingTestClock.value,
    ),
    identityActionBindingService: const IdentityActionBindingService(
      idGenerator: _FixedIdGenerator('binding-1'),
    ),
    identityCreationService: IdentityCreationService(
      readRepository: repository,
      writeRepository: repository,
      idGenerator: _CreationIdGenerator(),
      now: now ?? () => IdentityActionBindingTestClock.value,
    ),
  );
  return _Fixture(
    scope: scope,
    repository: repository,
    backend: backend,
    context: context,
    coordinator: coordinator,
  );
}

abstract final class IdentityActionBindingTestClock {
  static DateTime get value => now;
}

IdentityResolutionRequest _idRequest(
  IdentityAccountScope scope,
  String entityId, {
  EntityType? expectedType = EntityType.person,
}) =>
    IdentityResolutionRequest(
      scope: scope,
      reference: EntityReference.byId(
        entityId: entityId,
        expectedType: expectedType,
        source: source,
      ),
    );

IdentityResolutionRequest _textRequest(
  IdentityAccountScope scope,
  String value,
) =>
    IdentityResolutionRequest(
      scope: scope,
      reference: EntityReference.text(
        value: value,
        kind: EntityReferenceKind.alias,
        expectedType: EntityType.person,
        source: source,
      ),
    );

IdentityCreationRequest _creationRequest(
  IdentityAccountScope scope,
  String label,
) =>
    IdentityCreationRequest(
      scope: scope,
      entityType: EntityType.person,
      canonicalLabel: label,
      source: source,
    );

IdentityActionContinuation _continuation({
  String actionDraftId = 'event-draft-1',
}) =>
    IdentityActionContinuation(
      actionKind: IdentityActionKind.event,
      actionDraftId: actionDraftId,
      target: IdentityActionTarget.eventParticipant,
    );

LifeEntity _entity({
  String id = 'entity-1',
  String label = 'Person A',
  String? alias,
}) =>
    LifeEntity.fromLabel(
      id: id,
      type: EntityType.person,
      canonicalLabel: label,
      aliases: alias == null
          ? const []
          : [
              EntityAlias.fromValue(
                value: alias,
                kind: EntityAliasKind.explicit,
                source: source,
                createdAt: now,
              ),
            ],
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

final class _FixedIdGenerator implements EntityIdGenerator {
  final String value;

  const _FixedIdGenerator(this.value);

  @override
  String generate() => value;
}

final class _CreationIdGenerator implements EntityIdGenerator {
  var _index = 0;

  @override
  String generate() => ['proposal-created', 'entity-created'][_index++];
}

final class _ReadSpyRepository implements IdentityRepository {
  final FakeIdentityRepository _delegate = FakeIdentityRepository();
  int writeCalls = 0;
  bool failReads = false;

  Future<void> seed(
    IdentityAccountScope scope,
    List<LifeEntity> entities,
  ) =>
      _delegate.seedAll(scope: scope, entities: entities);

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) {
    if (failReads) throw const IdentityRepositoryException('read_failed');
    return _delegate.findById(scope: scope, entityId: entityId);
  }

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) {
    if (failReads) throw const IdentityRepositoryException('read_failed');
    return _delegate.findByIds(scope: scope, entityIds: entityIds);
  }

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) {
    if (failReads) throw const IdentityRepositoryException('read_failed');
    return _delegate.queryCandidates(scope: scope, query: query);
  }

  @override
  Future<RevisionedIdentity> create({
    required IdentityAccountScope scope,
    required LifeEntity entity,
  }) {
    writeCalls++;
    return _delegate.create(scope: scope, entity: entity);
  }

  @override
  Future<RevisionedIdentity> softDelete({
    required IdentityAccountScope scope,
    required String entityId,
    required int expectedRevision,
    required DateTime updatedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<RevisionedIdentity> update({
    required IdentityAccountScope scope,
    required LifeEntity entity,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();
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
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final class _Fixture {
  final IdentityAccountScope scope;
  final _ReadSpyRepository repository;
  final _FakeBackend backend;
  final _FakeContext context;
  final ConversationCoordinator coordinator;

  const _Fixture({
    required this.scope,
    required this.repository,
    required this.backend,
    required this.context,
    required this.coordinator,
  });
}
