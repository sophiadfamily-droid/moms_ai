import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/identity_engine.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/core/identity/persisted_identity_link.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/models/event_model.dart';
import 'package:moms_ai/models/event_mutation_models.dart';
import 'package:moms_ai/models/event_participant.dart';
import 'package:moms_ai/models/event_participant_identity_link.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:moms_ai/services/conversation_coordinator.dart';
import 'package:moms_ai/services/event_conversation_mutation_service.dart';
import 'package:moms_ai/services/event_mutation_service.dart';
import 'package:moms_ai/services/event_mutation_result.dart';
import 'package:moms_ai/services/identity/event_participant_identity_validation_service.dart';
import 'package:moms_ai/services/identity/identity_action_binding_service.dart';
import 'package:moms_ai/services/identity/identity_application_service.dart';
import 'package:moms_ai/services/identity/identity_clarification_service.dart';
import 'package:moms_ai/services/identity/identity_creation_service.dart';

void main() {
  test('resolved replacement waits for Event confirmation and writes once',
      () async {
    final fixture = await _fixture([_entity('new-id', 'Person B')]);

    final started = await fixture.coordinator.beginEventMutation(
      _replaceRequest(),
    );

    expect(started.message, contains('Person B'));
    expect(fixture.writes, 0);
    expect(
        fixture.events.single.participantIdentity!.identity.entityId, 'old-id');
    expect(fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventMutationConfirmation);

    final confirmed = await fixture.coordinator.resolvePendingEventMutation(
      answer: 'oui',
    );
    expect(confirmed?.diagnosticCode, 'event_mutation_updated');
    expect(fixture.writes, 1);
    expect(
        fixture.events.single.participantIdentity!.identity.entityId, 'new-id');
    expect(fixture.events.single.participantIdentityRevision, 2);

    expect(await fixture.coordinator.resolvePendingEventMutation(answer: 'oui'),
        isNull);
    expect(fixture.writes, 1);
  });

  test(
      'ambiguous Identity and creation remain separate from Event confirmation',
      () async {
    final ambiguous = await _fixture([
      _entity('new-id-1', 'First', alias: 'Person B'),
      _entity('new-id-2', 'Second', alias: 'Person B'),
    ]);
    await ambiguous.coordinator.beginEventMutation(_replaceRequest());
    expect(ambiguous.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityClarification);
    final selected = await ambiguous.coordinator.send(
      input: ConversationInput(message: '1', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(selected?.reply, contains('Confirmer ?'));
    expect(ambiguous.writes, 0);

    final created = await _fixture(const []);
    await created.coordinator.beginEventMutation(_replaceRequest());
    expect(created.coordinator.state.pendingAction?.type,
        PendingConversationActionType.identityCreation);
    final identityConfirmed = await created.coordinator.send(
      input: ConversationInput(message: 'oui', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(identityConfirmed?.identityCreationResult?.status,
        IdentityCreationStatus.created);
    expect(created.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventMutationConfirmation);
    expect(created.writes, 0);
  });

  test('Event clarification preserves replacement operation and participant',
      () async {
    final fixture = await _fixture([_entity('new-id', 'Person B')]);
    fixture.events.add(_event().copyWith(id: 'event-2'));

    await fixture.coordinator.beginEventMutation(_replaceRequest());
    final clarification =
        fixture.coordinator.state.pendingAction!.eventTargetClarification!;
    expect(clarification.request.operation,
        EventMutationOperation.replaceParticipant);
    expect(clarification.request.participant!.label, 'Person B');
    expect(fixture.writes, 0);

    final selected = await fixture.coordinator.resolvePendingEventMutation(
      answer: '1',
    );
    expect(selected?.message, contains('Person B'));
    expect(fixture.coordinator.state.pendingAction?.type,
        PendingConversationActionType.eventMutationConfirmation);
    expect(fixture.writes, 0);
  });

  test('refused Identity and replacement without an existing link never write',
      () async {
    final fixture = await _fixture(const []);
    await fixture.coordinator.beginEventMutation(_replaceRequest());
    await fixture.coordinator.send(
      input: ConversationInput(message: 'non', profile: _profile()),
      executeAction: (_) async => const ConversationActionOutcome(),
    );
    expect(fixture.writes, 0);
    expect(
        fixture.events.single.participantIdentity!.identity.entityId, 'old-id');

    final noLink = await _fixture(
      [_entity('new-id', 'Person B')],
      event: _event(withParticipant: false),
    );
    final rejected =
        await noLink.coordinator.beginEventMutation(_replaceRequest());
    expect(rejected.diagnosticCode,
        'event_participant_mutation_requires_existing_link');
    expect(noLink.writes, 0);
  });

  test(
      'removal is confirmed, preserves other fields, and never touches Identity',
      () async {
    final fixture = await _fixture(
      [_entity('old-id', 'Person A')],
      includeIdentityServices: false,
    );
    final original = fixture.events.single.toJson();

    final started = await fixture.coordinator.beginEventMutation(
      EventMutationRequest.removeParticipant(
        target: EventMutationTarget(date: '2026-07-23', time: '10:00'),
      ),
    );
    expect(started.message, contains('retirer le participant'));
    expect(fixture.writes, 0);

    await fixture.coordinator.resolvePendingEventMutation(answer: 'oui');
    expect(fixture.writes, 1);
    expect(fixture.events.single.participantIdentity, isNull);
    expect(fixture.events.single.participantIdentityRevision, 2);
    final next = fixture.events.single.toJson()..remove('participantIdentity');
    final expected = Map<String, dynamic>.from(original)
      ..remove('participantIdentity');
    expected['participantIdentityRevision'] = 2;
    expected['eventRevision'] = 2;
    expect(next, expected);
    expect(
      (await fixture.repository.findById(
        scope: fixture.scope,
        entityId: 'old-id',
      ))
          ?.status,
      EntityStatus.active,
    );
  });

  test('removal refusal, ambiguity, expiration and missing link never write',
      () async {
    final fixture = await _fixture(const [], includeIdentityServices: false);
    final request = EventMutationRequest.removeParticipant(
      target: EventMutationTarget(date: '2026-07-23', time: '10:00'),
    );
    await fixture.coordinator.beginEventMutation(request);
    await fixture.coordinator.resolvePendingEventMutation(answer: 'peut-être');
    expect(fixture.coordinator.state.pendingAction, isNotNull);
    await fixture.coordinator.resolvePendingEventMutation(answer: 'non');
    expect(fixture.writes, 0);

    final expired = await _fixture(const [], includeIdentityServices: false);
    await expired.coordinator.beginEventMutation(request);
    expired.now = expired.now.add(const Duration(minutes: 16));
    final expiration =
        await expired.coordinator.resolvePendingEventMutation(answer: 'oui');
    expect(expiration?.diagnosticCode, 'event_mutation_expired');
    expect(expired.writes, 0);

    final missing = await _fixture(const [],
        includeIdentityServices: false, event: _event(withParticipant: false));
    final result = await missing.coordinator.beginEventMutation(request);
    expect(result.diagnosticCode,
        'event_participant_mutation_requires_existing_link');
    expect(missing.writes, 0);
  });

  test('concurrent participant change blocks replacement', () async {
    final fixture = await _fixture([_entity('new-id', 'Person B')]);
    await fixture.coordinator.beginEventMutation(_replaceRequest());
    fixture.events[0] = EventMutationService.apply(
      existing: fixture.events[0],
      proposed: fixture.events[0],
      participantIntent: ReplaceEventParticipant(
        _link('concurrent-id'),
      ),
    );

    final result = await fixture.coordinator.resolvePendingEventMutation(
      answer: 'oui',
    );
    expect(result?.diagnosticCode, 'event_mutation_concurrent_change');
    expect(fixture.writes, 0);
    expect(fixture.events.single.participantIdentity!.identity.entityId,
        'concurrent-id');
  });

  test('participant mutation refuses a foreign event scope', () async {
    final foreignEvent = _event().copyWith(
      participantIdentity: _link('old-id', scope: 'account-b'),
    );
    final fixture = await _fixture(
      [_entity('new-id', 'Person B')],
      event: foreignEvent,
    );

    final result =
        await fixture.coordinator.beginEventMutation(_replaceRequest());
    expect(result.diagnosticCode, 'event_participant_identity_scope_mismatch');
    expect(fixture.writes, 0);
  });

  test('Identity invalidated before final confirmation blocks replacement',
      () async {
    final fixture = await _fixture([_entity('new-id', 'Person B')]);
    await fixture.coordinator.beginEventMutation(_replaceRequest());
    await fixture.repository.seedAll(
      scope: fixture.scope,
      entities: [
        _entity('new-id', 'Person B', status: EntityStatus.deleted),
      ],
    );

    final result = await fixture.coordinator.resolvePendingEventMutation(
      answer: 'oui',
    );
    expect(
        result?.diagnosticCode, 'event_participant_identity_not_referenceable');
    expect(fixture.writes, 0);
    expect(
        fixture.events.single.participantIdentity!.identity.entityId, 'old-id');
  });
}

EventMutationRequest _replaceRequest() =>
    EventMutationRequest.replaceParticipant(
      target: EventMutationTarget(date: '2026-07-23', time: '10:00'),
      participant: EventParticipant(
        label: 'Person B',
        entityType: EventParticipantEntityType.person,
        evidence: EventParticipantEvidence.explicitUserInput,
      ),
    );

Future<_Fixture> _fixture(
  List<LifeEntity> identities, {
  EventModel? event,
  bool includeIdentityServices = true,
}) async {
  final scope = IdentityAccountScope('account-a');
  final repository = FakeIdentityRepository();
  await repository.seedAll(scope: scope, entities: identities);
  final events = [event ?? _event()];
  final fixture = _Fixture(events, repository, scope);
  final ids = _Ids();
  fixture.coordinator = ConversationCoordinator(
    backend: const _Backend(),
    contextProvider: const _Context(),
    identityAccountScope: scope,
    identityApplicationService: includeIdentityServices
        ? IdentityApplicationService(
            repository: repository,
            engine: const IdentityEngine(),
            now: () => _now,
          )
        : null,
    identityActionBindingService: IdentityActionBindingService(
      idGenerator: ids,
    ),
    identityClarificationService: IdentityClarificationService(
      idGenerator: ids,
      now: () => _now,
    ),
    identityCreationService: includeIdentityServices
        ? IdentityCreationService(
            readRepository: repository,
            writeRepository: repository,
            idGenerator: ids,
            now: () => _now,
          )
        : null,
    eventParticipantIdentityValidationService: includeIdentityServices
        ? EventParticipantIdentityValidationService(repository: repository)
        : null,
    actionDraftIdGenerator: ids,
    clock: () => fixture.now,
    eventConversationMutationService: EventConversationMutationService(
      loadEvents: () async => List.of(events),
      write: (
          {required existing,
          required proposed,
          required expectedEventRevision,
          required participantIntent}) async {
        fixture.writes++;
        final index = events.indexWhere((value) => value.id == existing.id);
        events[index] = EventMutationService.apply(
          existing: existing,
          proposed: proposed,
          participantIntent: participantIntent,
        );
        events[index] = events[index].copyWith(
          eventRevision: expectedEventRevision + 1,
        );
        return EventMutationResult.success(events[index]);
      },
    ),
  );
  return fixture;
}

final class _Fixture {
  final List<EventModel> events;
  final FakeIdentityRepository repository;
  final IdentityAccountScope scope;
  late ConversationCoordinator coordinator;
  int writes = 0;
  DateTime now = _now;

  _Fixture(this.events, this.repository, this.scope);
}

final class _Ids implements EntityIdGenerator {
  int _value = 0;
  @override
  String generate() => 'generated-${++_value}';
}

final class _Backend implements ChatBackendClient {
  const _Backend();
  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async =>
      const ChatBackendResponse(
        reply: 'Aucune action',
        actions: [],
        memories: [],
      );
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
        profile: profile.toJson(),
        profileContext: const {},
        memories: const [],
        memoryReasoning: const [],
        events: const [],
      );
  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}

final _now = DateTime.utc(2026, 7, 22, 10);

LifeEntity _entity(
  String id,
  String label, {
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
                source: const EntitySource(type: EntitySourceType.user),
                createdAt: _now,
              ),
            ],
      status: status,
      source: const EntitySource(type: EntitySourceType.user),
      createdAt: _now,
      updatedAt: _now,
    );

EventParticipantIdentityLink _link(
  String entityId, {
  String scope = 'account-a',
}) =>
    EventParticipantIdentityLink(
      identity: PersistedIdentityLink(
        entityId: entityId,
        entityType: EntityType.person,
      ),
      accountScopeId: scope,
    );

EventModel _event({bool withParticipant = true}) => EventModel(
      id: 'event-1',
      title: 'Rendez-vous médecin',
      date: '2026-07-23',
      time: '10:00',
      durationMinutes: 45,
      travelGoMinutes: 10,
      travelBackMinutes: 20,
      usesSeparateTravelTimes: true,
      travelMinutes: 30,
      marginMinutes: 5,
      notes: 'Notes',
      createdAt: _now,
      startDateTimeIso: '2026-07-23T10:00:00.000Z',
      category: 'Santé',
      participantIdentity: withParticipant ? _link('old-id') : null,
      participantIdentityRevision: withParticipant ? 1 : 0,
    );

UserProfile _profile() => UserProfile(
      firstName: 'Person',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: false,
      children: const [],
    );
