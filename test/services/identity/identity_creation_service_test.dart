import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_id_generator.dart';
import 'package:moms_ai/core/identity/entity_resolution.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/conversation_models.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';
import 'package:moms_ai/repositories/identity/identity_repository_result.dart';
import 'package:moms_ai/services/identity/identity_application_models.dart';
import 'package:moms_ai/services/identity/identity_creation_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22, 10);

  test('a proposal stores supplied facts and performs no write', () {
    final fixture = _fixture(now);
    final pending = fixture.service.propose(
      applicationResult: _notFound(),
      request: _request(),
    );

    expect(pending.entityId, 'entity-1');
    expect(pending.entityType, EntityType.person);
    expect(pending.canonicalLabel, 'Person A');
    expect(pending.source, same(source));
    expect(pending.accountScopeId, 'account-a');
    expect(fixture.repository.createCalls, 0);
    expect(fixture.service.question(pending), isNot(contains('entity-1')));
  });

  test('explicit confirmation creates exactly one minimal identity', () async {
    final fixture = _fixture(now);
    final pending = _propose(fixture);
    final result = await fixture.service.process(
      pending: pending,
      answer: 'oui',
    );

    expect(result.status, IdentityCreationStatus.created);
    expect(result.createdEntityId, 'entity-1');
    expect(fixture.repository.createCalls, 1);
    expect(fixture.repository.lastScope, IdentityAccountScope('account-a'));
    final created = await fixture.repository.findById(
      scope: IdentityAccountScope('account-a'),
      entityId: 'entity-1',
    );
    expect(created?.aliases, isEmpty);
    expect(created?.metadata, isEmpty);
    expect(created?.source, same(source));
    expect(created?.createdAt, now);
  });

  test('refusal and ambiguous answers never write', () async {
    for (final answer in ['non', 'peut-être']) {
      final fixture = _fixture(now);
      final result = await fixture.service.process(
        pending: _propose(fixture),
        answer: answer,
      );
      expect(
        result.status,
        answer == 'non'
            ? IdentityCreationStatus.cancelled
            : IdentityCreationStatus.stillPending,
      );
      expect(fixture.repository.createCalls, 0);
    }
  });

  test('repeated confirmation cannot create a second identity', () async {
    final fixture = _fixture(now);
    final pending = _propose(fixture);
    final first =
        await fixture.service.process(pending: pending, answer: 'oui');
    final second =
        await fixture.service.process(pending: pending, answer: 'oui');

    expect(first.status, IdentityCreationStatus.created);
    expect(second.status, IdentityCreationStatus.alreadyExists);
    expect(fixture.repository.createCalls, 1);
  });

  test('an exact identity appearing before confirmation is not duplicated',
      () async {
    final fixture = _fixture(now);
    final pending = _propose(fixture);
    await fixture.repository.seed(
      _entity(id: 'existing', label: 'Person A', now: now),
    );

    final result = await fixture.service.process(
      pending: pending,
      answer: 'confirme',
    );

    expect(result.status, IdentityCreationStatus.alreadyExists);
    expect(fixture.repository.createCalls, 0);
  });

  test('repository failures never produce a success result', () async {
    final fixture = _fixture(now, failCreate: true);
    final result = await fixture.service.process(
      pending: _propose(fixture),
      answer: 'oui',
    );

    expect(result.status, IdentityCreationStatus.repositoryFailure);
    expect(result.createdEntityId, isNull);
    expect(result.followUpMessage, isNot(contains('bien été enregistrée')));
  });

  test('expired proposals never query or write', () async {
    final fixture = _fixture(now);
    final result = await fixture.service.process(
      pending: _propose(fixture),
      answer: 'oui',
      referenceDate: now.add(const Duration(minutes: 15)),
    );

    expect(result.status, IdentityCreationStatus.expired);
    expect(fixture.repository.readCalls, 0);
    expect(fixture.repository.createCalls, 0);
  });

  test('creation requires notFound and complete explicit facts', () {
    final fixture = _fixture(now);
    expect(
      () => fixture.service.propose(
        applicationResult: IdentityApplicationResult.fromResolution(
          EntityResolution.invalid(
            signals: const [],
            reasonCode: 'invalid',
          ),
        ),
        request: _request(),
      ),
      throwsA(isA<ConversationIdentityException>()),
    );
    expect(
      () => IdentityCreationRequest(
        scope: IdentityAccountScope('account-a'),
        entityType: EntityType.unknown,
        canonicalLabel: '',
        source: source,
      ),
      throwsA(isA<ConversationIdentityException>()),
    );
    expect(
      () => IdentityCreationRequest(
        scope: IdentityAccountScope('account-a'),
        entityType: EntityType.person,
        canonicalLabel: 'Person A',
        source: const EntitySource(type: EntitySourceType.unknown),
      ),
      throwsA(isA<ConversationIdentityException>()),
    );
  });
}

const source = EntitySource(type: EntitySourceType.conversation);

IdentityApplicationResult _notFound() =>
    IdentityApplicationResult.fromResolution(
      EntityResolution.notFound(reasonCode: 'not_found'),
    );

IdentityCreationRequest _request() => IdentityCreationRequest(
      scope: IdentityAccountScope('account-a'),
      entityType: EntityType.person,
      canonicalLabel: ' Person A ',
      source: source,
    );

PendingIdentityCreation _propose(_Fixture fixture) => fixture.service.propose(
      applicationResult: _notFound(),
      request: _request(),
    );

_Fixture _fixture(DateTime now, {bool failCreate = false}) {
  final repository = _SpyRepository(failCreate: failCreate);
  return _Fixture(
    repository,
    IdentityCreationService(
      readRepository: repository,
      writeRepository: repository,
      idGenerator: _SequenceIdGenerator(['proposal-1', 'entity-1']),
      now: () => now,
    ),
  );
}

LifeEntity _entity({
  required String id,
  required String label,
  required DateTime now,
}) =>
    LifeEntity.fromLabel(
      id: id,
      type: EntityType.person,
      canonicalLabel: label,
      source: source,
      createdAt: now,
      updatedAt: now,
    );

final class _Fixture {
  final _SpyRepository repository;
  final IdentityCreationService service;

  const _Fixture(this.repository, this.service);
}

final class _SequenceIdGenerator implements EntityIdGenerator {
  final List<String> _values;
  var _index = 0;

  _SequenceIdGenerator(this._values);

  @override
  String generate() => _values[_index++];
}

final class _SpyRepository implements IdentityRepository {
  final FakeIdentityRepository _delegate = FakeIdentityRepository();
  final bool failCreate;
  var createCalls = 0;
  var readCalls = 0;
  IdentityAccountScope? lastScope;

  _SpyRepository({this.failCreate = false});

  Future<void> seed(LifeEntity entity) => _delegate.seedAll(
        scope: IdentityAccountScope('account-a'),
        entities: [entity],
      );

  @override
  Future<RevisionedIdentity> create({
    required IdentityAccountScope scope,
    required LifeEntity entity,
  }) async {
    createCalls++;
    lastScope = scope;
    if (failCreate) {
      throw const IdentityRepositoryException('repository_unavailable');
    }
    return _delegate.create(scope: scope, entity: entity);
  }

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) {
    readCalls++;
    return _delegate.findById(scope: scope, entityId: entityId);
  }

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) =>
      _delegate.findByIds(scope: scope, entityIds: entityIds);

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) {
    readCalls++;
    return _delegate.queryCandidates(scope: scope, query: query);
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
