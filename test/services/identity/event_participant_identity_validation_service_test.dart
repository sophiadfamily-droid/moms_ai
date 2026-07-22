import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_normalizer.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/models/event_participant.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_read_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';
import 'package:moms_ai/repositories/identity/identity_repository_result.dart';
import 'package:moms_ai/services/identity/event_participant_identity_validation_service.dart';

void main() {
  final participant = EventParticipant(
    label: 'Person A',
    entityType: EventParticipantEntityType.person,
    evidence: EventParticipantEvidence.explicitUserInput,
  );
  final scope = IdentityAccountScope('account-a');

  test('active person in the explicit scope becomes a minimal link', () async {
    final repository = FakeIdentityRepository();
    await repository.seedAll(scope: scope, entities: [_entity('entity-1')]);
    final result = await EventParticipantIdentityValidationService(
      repository: repository,
    ).validate(scope: scope, entityId: 'entity-1', participant: participant);
    expect(result.status, EventParticipantIdentityValidationStatus.valid);
    expect(result.link?.identity.entityId, 'entity-1');
  });

  test('inactive, deleted, absent, and wrong-scope entities are blocked',
      () async {
    for (final status in [EntityStatus.inactive, EntityStatus.deleted]) {
      final repository = FakeIdentityRepository();
      await repository.seedAll(
        scope: scope,
        entities: [_entity('entity-1', status: status)],
      );
      final result = await EventParticipantIdentityValidationService(
        repository: repository,
      ).validate(scope: scope, entityId: 'entity-1', participant: participant);
      expect(result.status, EventParticipantIdentityValidationStatus.invalid);
    }
    final repository = FakeIdentityRepository();
    await repository.seedAll(
      scope: IdentityAccountScope('account-b'),
      entities: [_entity('entity-1')],
    );
    final result = await EventParticipantIdentityValidationService(
      repository: repository,
    ).validate(scope: scope, entityId: 'entity-1', participant: participant);
    expect(result.status, EventParticipantIdentityValidationStatus.invalid);
  });

  test('merged identities resolve only to a validated active person', () async {
    final repository = FakeIdentityRepository();
    await repository.seedAll(scope: scope, entities: [
      _entity(
        'merged',
        status: EntityStatus.merged,
        mergedIntoEntityId: 'target',
      ),
      _entity('target'),
    ]);
    final result = await EventParticipantIdentityValidationService(
      repository: repository,
    ).validate(scope: scope, entityId: 'merged', participant: participant);
    expect(result.status, EventParticipantIdentityValidationStatus.valid);
    expect(result.link?.identity.entityId, 'target');
  });

  test('a binding that no longer matches the structured participant is blocked',
      () async {
    final repository = FakeIdentityRepository();
    await repository.seedAll(
      scope: scope,
      entities: [_entity('entity-1', label: 'Different Person')],
    );
    final result = await EventParticipantIdentityValidationService(
      repository: repository,
    ).validate(scope: scope, entityId: 'entity-1', participant: participant);
    expect(result.status, EventParticipantIdentityValidationStatus.invalid);
    expect(
      result.diagnosticCode,
      'event_participant_identity_binding_mismatch',
    );
  });

  test('repository failures return a stable non-sensitive result', () async {
    final result = await EventParticipantIdentityValidationService(
      repository: const _FailingRepository(),
    ).validate(scope: scope, entityId: 'entity-1', participant: participant);
    expect(
      result.status,
      EventParticipantIdentityValidationStatus.repositoryFailure,
    );
    expect(
        result.diagnosticCode, 'event_participant_identity_repository_failure');
    expect(result.diagnosticCode, isNot(contains('entity-1')));
  });
}

LifeEntity _entity(
  String id, {
  String label = 'Person A',
  EntityStatus status = EntityStatus.active,
  String? mergedIntoEntityId,
}) {
  return LifeEntity(
    id: id,
    type: EntityType.person,
    canonicalLabel: label,
    normalizedLabel: EntityNormalizer.normalize(label).normalizedLabel,
    status: status,
    source: const EntitySource(type: EntitySourceType.user),
    createdAt: DateTime.utc(2026, 7, 22),
    updatedAt: DateTime.utc(2026, 7, 22),
    mergedIntoEntityId: mergedIntoEntityId,
  );
}

final class _FailingRepository implements IdentityReadRepository {
  const _FailingRepository();

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) =>
      throw StateError('not exposed');

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) =>
      throw StateError('not exposed');

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) =>
      throw StateError('not exposed');
}
