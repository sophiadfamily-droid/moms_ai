import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/identity_engine.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_participant.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_read_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';
import 'package:moms_ai/repositories/identity/identity_repository_result.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/identity/identity_action_binding_service.dart';
import 'package:moms_ai/services/identity/identity_application_service.dart';
import 'package:moms_ai/services/identity/identity_clarification_service.dart';
import 'package:moms_ai/services/identity/identity_creation_service.dart';
import 'package:moms_ai/services/identity/event_participant_identity_validation_service.dart';

void main() {
  group('production event participant Identity flow', () {
    test('resolved participant resumes at event confirmation', () async {
      final fixture = await _fixture([_entity()]);

      final result = await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );

      expect(result.message, 'Confirmer cet événement ?');
      expect(
        result.identityActionBindingResult?.status,
        IdentityActionBindingStatus.attached,
      );
      final pending = fixture.coordinator.state.pendingAction;
      expect(pending?.type, PendingConversationActionType.eventConfirmation);
      expect(pending?.event.title, 'Rendez-vous');
      expect(pending?.eventParticipant, _participant());
      expect(pending?.participantIdentityEntityId, 'entity-1');
      expect(fixture.eventWrites, 0);

      EventModel? persisted;
      final confirmation =
          await fixture.coordinator.resolvePendingEventConfirmation(
        answer: 'oui',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (event) async {
          fixture.eventWrites++;
          persisted = event;
          return 'Événement créé';
        },
      );
      expect(confirmation?.message, 'Événement créé');
      expect(persisted?.participantIdentity?.identity.entityId, 'entity-1');
      expect(fixture.eventWrites, 1);
    });

    test('ambiguity keeps the draft then explicit selection resumes it',
        () async {
      final fixture = await _fixture([
        _entity(id: 'entity-1', label: 'First', alias: 'Shared'),
        _entity(id: 'entity-2', label: 'Second', alias: 'Shared'),
      ]);

      final started = await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(label: 'Shared'),
        confirmationMessage: 'Confirmer cet événement ?',
      );
      expect(
        started.identityActionBindingResult?.status,
        IdentityActionBindingStatus.pendingClarification,
      );
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityClarification,
      );

      final selected = await fixture.coordinator.send(
        input: ConversationInput(message: '1', profile: _profile()),
        executeAction: (_) async {
          fixture.eventWrites++;
          return const ConversationActionOutcome();
        },
      );

      expect(selected?.reply, contains('Confirmer cet événement ?'));
      final pending = fixture.coordinator.state.pendingAction;
      expect(pending?.type, PendingConversationActionType.eventConfirmation);
      expect(pending?.event.durationMinutes, 45);
      expect(pending?.event.travelGoMinutes, 10);
      expect(pending?.event.travelBackMinutes, 20);
      expect(pending?.participantIdentityEntityId, isNotEmpty);
      expect(fixture.eventWrites, 0);
    });

    test('notFound proposes then creates once without confirming the event',
        () async {
      final fixture = await _fixture(const []);

      final started = await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );
      expect(
        started.identityActionBindingResult?.status,
        IdentityActionBindingStatus.pendingCreation,
      );
      final createdEntityId =
          fixture.coordinator.state.pendingAction!.identityCreation!.entityId;
      expect(
        await fixture.repository.findById(
          scope: fixture.scope,
          entityId: createdEntityId,
        ),
        isNull,
      );

      final created = await fixture.coordinator.send(
        input: ConversationInput(message: 'oui', profile: _profile()),
        executeAction: (_) async {
          fixture.eventWrites++;
          return const ConversationActionOutcome();
        },
      );

      expect(created?.identityCreationResult?.status,
          IdentityCreationStatus.created);
      expect(created?.reply, contains('Confirmer cet événement ?'));
      expect(
        await fixture.repository.findById(
          scope: fixture.scope,
          entityId: createdEntityId,
        ),
        isNotNull,
      );
      expect(fixture.eventWrites, 0);
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventConfirmation,
      );

      final ambiguousEventAnswer =
          await fixture.coordinator.resolvePendingEventConfirmation(
        answer: 'peut-être',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Événement annulé',
        expectedAnswerMessage: () => 'Confirme l’événement séparément',
        execute: (_) async {
          fixture.eventWrites++;
          return 'Événement créé';
        },
      );
      expect(ambiguousEventAnswer?.message, 'Confirme l’événement séparément');
      expect(fixture.eventWrites, 0);

      EventModel? persisted;
      await fixture.coordinator.resolvePendingEventConfirmation(
        answer: 'oui',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (event) async {
          fixture.eventWrites++;
          persisted = event;
          return 'Événement créé';
        },
      );
      expect(
        persisted?.participantIdentity?.identity.entityId,
        createdEntityId,
      );
      expect(fixture.eventWrites, 1);
    });

    test('creation refusal and ambiguity write neither identity nor event',
        () async {
      final ambiguous = await _fixture(const []);
      await ambiguous.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );
      final stillPending = await ambiguous.coordinator.send(
        input: ConversationInput(message: 'peut-être', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      expect(stillPending?.identityCreationResult?.status,
          IdentityCreationStatus.stillPending);
      expect(ambiguous.coordinator.state.pendingAction?.identityCreation,
          isNotNull);

      final cancelled = await ambiguous.coordinator.send(
        input: ConversationInput(message: 'non', profile: _profile()),
        executeAction: (_) async => const ConversationActionOutcome(),
      );
      expect(cancelled?.identityCreationResult?.status,
          IdentityCreationStatus.cancelled);
      expect(
        await ambiguous.repository.findById(
          scope: ambiguous.scope,
          entityId: 'created-entity-1',
        ),
        isNull,
      );
      expect(ambiguous.eventWrites, 0);
      expect(ambiguous.coordinator.state.pendingAction, isNull);
    });

    test('missing production scope fails closed and preserves no false success',
        () async {
      final fixture = await _fixture([_entity()], includeScope: false);

      final result = await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );

      expect(result.message, contains('ne peut pas être vérifiée'));
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.eventWrites, 0);
    });

    test('expired creation performs no write and does not resume the event',
        () async {
      var clock = _now;
      final fixture = await _fixture(const [], now: () => clock);
      await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );
      final entityId =
          fixture.coordinator.state.pendingAction!.identityCreation!.entityId;
      clock = clock.add(const Duration(minutes: 16));

      final result = await fixture.coordinator.send(
        input: ConversationInput(message: 'oui', profile: _profile()),
        executeAction: (_) async {
          fixture.eventWrites++;
          return const ConversationActionOutcome();
        },
      );

      expect(result?.identityCreationResult?.status,
          IdentityCreationStatus.expired);
      expect(
        await fixture.repository.findById(
          scope: fixture.scope,
          entityId: entityId,
        ),
        isNull,
      );
      expect(fixture.eventWrites, 0);
      expect(fixture.coordinator.state.pendingAction, isNull);
    });

    test(
        'repository failure exposes no success and keeps the event unconfirmed',
        () async {
      final fixture = await _fixture(
        const [],
        readRepository: const _FailingReadRepository(),
      );

      final result = await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );

      expect(result.identityActionBindingResult?.diagnosticCode,
          'identity_repository_failure');
      expect(result.message, isNot(contains('Confirmer cet événement ?')));
      expect(fixture.coordinator.state.pendingAction, isNull);
      expect(fixture.eventWrites, 0);
    });

    test('passes the explicitly injected account scope to repository reads',
        () async {
      final repository = FakeIdentityRepository();
      final scope = IdentityAccountScope('account-a');
      await repository.seedAll(scope: scope, entities: [_entity()]);
      final spy = _ScopeSpyReadRepository(repository);
      final fixture = await _fixture(
        const [],
        readRepository: spy,
        repository: repository,
      );

      await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );

      expect(spy.scopes, isNotEmpty);
      expect(spy.scopes.toSet(), {scope});
    });

    test('deleted identity before event confirmation blocks the event write',
        () async {
      final fixture = await _fixture([_entity()]);
      await fixture.coordinator.beginEventParticipantIdentity(
        event: _event(),
        participant: _participant(),
        confirmationMessage: 'Confirmer cet événement ?',
      );
      await fixture.repository.seedAll(
        scope: fixture.scope,
        entities: [_entity(status: EntityStatus.deleted)],
      );

      final result = await fixture.coordinator.resolvePendingEventConfirmation(
        answer: 'oui',
        isPositiveAnswer: (value) => value == 'oui',
        isNegativeAnswer: (value) => value == 'non',
        cancellationMessage: (_) => 'Annulé',
        expectedAnswerMessage: () => 'Réponds oui ou non',
        execute: (_) async {
          fixture.eventWrites++;
          return 'Événement créé';
        },
      );

      expect(
        result?.diagnosticCode,
        'event_participant_identity_not_referenceable',
      );
      expect(fixture.eventWrites, 0);
      expect(
        fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventConfirmation,
      );
    });
  });
}

final _now = DateTime.utc(2026, 7, 22, 10);
const _source = EntitySource(type: EntitySourceType.user);

Future<_Fixture> _fixture(
  List<LifeEntity> entities, {
  bool includeScope = true,
  DateTime Function()? now,
  IdentityReadRepository? readRepository,
  FakeIdentityRepository? repository,
}) async {
  final scope = IdentityAccountScope('account-a');
  final fakeRepository = repository ?? FakeIdentityRepository();
  await fakeRepository.seedAll(scope: scope, entities: entities);
  final reads = readRepository ?? fakeRepository;
  final ids = _SequenceIdGenerator([
    'event-draft-1',
    'binding-1',
    'clarification-1',
    'proposal-1',
    'created-entity-1',
  ]);
  final coordinator = ConversationCoordinator(
    backend: const _Backend(),
    contextProvider: const _Context(),
    identityAccountScope: includeScope ? scope : null,
    actionDraftIdGenerator: ids,
    identityApplicationService: IdentityApplicationService(
      repository: reads,
      engine: const IdentityEngine(),
      now: now ?? () => _now,
    ),
    identityActionBindingService: IdentityActionBindingService(
      idGenerator: ids,
    ),
    identityClarificationService: IdentityClarificationService(
      idGenerator: ids,
      now: now ?? () => _now,
    ),
    identityCreationService: IdentityCreationService(
      readRepository: reads,
      writeRepository: fakeRepository,
      idGenerator: ids,
      now: now ?? () => _now,
    ),
    eventParticipantIdentityValidationService:
        EventParticipantIdentityValidationService(repository: reads),
  );
  return _Fixture(
    coordinator: coordinator,
    repository: fakeRepository,
    scope: scope,
  );
}

final class _ScopeSpyReadRepository implements IdentityReadRepository {
  final IdentityReadRepository delegate;
  final List<IdentityAccountScope> scopes = [];

  _ScopeSpyReadRepository(this.delegate);

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) {
    scopes.add(scope);
    return delegate.findById(scope: scope, entityId: entityId);
  }

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) {
    scopes.add(scope);
    return delegate.findByIds(scope: scope, entityIds: entityIds);
  }

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) {
    scopes.add(scope);
    return delegate.queryCandidates(scope: scope, query: query);
  }
}

final class _FailingReadRepository implements IdentityReadRepository {
  const _FailingReadRepository();

  Never _fail() => throw const IdentityRepositoryException(
        'repository_unavailable',
      );

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) async =>
      _fail();

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) async =>
      _fail();

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) async =>
      _fail();
}

final class _Fixture {
  final ConversationCoordinator coordinator;
  final FakeIdentityRepository repository;
  final IdentityAccountScope scope;
  int eventWrites = 0;

  _Fixture({
    required this.coordinator,
    required this.repository,
    required this.scope,
  });
}

final class _SequenceIdGenerator implements EntityIdGenerator {
  final List<String> _values;
  int _index = 0;

  _SequenceIdGenerator(this._values);

  @override
  String generate() => _values[_index++];
}

final class _Backend implements ChatBackendClient {
  const _Backend();

  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async =>
      const ChatBackendResponse(reply: '', actions: [], memories: []);
}

final class _Context implements ConversationContextProvider {
  const _Context();

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async =>
      ChatBackendRequest(
        message: message,
        profile: const {},
        profileContext: const {},
        memories: const [],
        memoryReasoning: const [],
        events: const [],
      );

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

EventParticipant _participant({String label = 'Person A'}) => EventParticipant(
      label: label,
      entityType: EventParticipantEntityType.person,
      evidence: EventParticipantEvidence.explicitUserInput,
    );

LifeEntity _entity({
  String id = 'entity-1',
  String label = 'Person A',
  String? alias,
  EntityStatus status = EntityStatus.active,
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
                source: _source,
                createdAt: _now,
              ),
            ],
      status: status,
      source: _source,
      createdAt: _now,
      updatedAt: _now,
    );

EventModel _event() => EventModel(
      title: 'Rendez-vous',
      date: '2026-07-23',
      time: '10:00',
      notes: 'Note',
      category: 'Personnel',
      createdAt: _now,
      startDateTimeIso: '2026-07-23T10:00:00Z',
      endTime: '10:45',
      endDateTimeIso: '2026-07-23T10:45:00Z',
      durationMinutes: 45,
      travelMinutes: 30,
      travelGoMinutes: 10,
      travelBackMinutes: 20,
      usesSeparateTravelTimes: true,
      marginMinutes: 5,
    );

UserProfile _profile() => UserProfile(
      firstName: 'User',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );
