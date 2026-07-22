import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/core/identity/entity_alias.dart';
import 'package:moms_ai/core/identity/entity_candidate.dart';
import 'package:moms_ai/core/identity/entity_reference.dart';
import 'package:moms_ai/core/identity/entity_resolution.dart';
import 'package:moms_ai/core/identity/entity_types.dart';
import 'package:moms_ai/core/identity/identity_engine.dart';
import 'package:moms_ai/core/identity/life_entity.dart';
import 'package:moms_ai/repositories/identity/fake_identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository.dart';
import 'package:moms_ai/repositories/identity/identity_repository_query.dart';
import 'package:moms_ai/repositories/identity/identity_repository_result.dart';
import 'package:moms_ai/services/identity/identity_application_models.dart';
import 'package:moms_ai/services/identity/identity_application_service.dart';

void main() {
  late _SpyRepository repository;
  late IdentityApplicationService service;
  late IdentityAccountScope scope;

  setUp(() {
    repository = _SpyRepository();
    service = IdentityApplicationService(
      repository: repository,
      engine: const IdentityEngine(),
      now: () => referenceDate,
    );
    scope = IdentityAccountScope('account-a');
  });

  group('request validation and immutability', () {
    test('accepts a valid request and uses the injected clock', () async {
      await repository.seed(scope, [_entity(alias: _alias('Temporary'))]);
      final result = await service.resolve(_textRequest(scope, 'Temporary'));

      expect(result.status, IdentityApplicationStatus.resolved);
      expect(repository.lastQuery?.referenceDate, referenceDate.toUtc());
    });

    test('rejects invalid scopes and candidate limits', () {
      expect(
        () => IdentityAccountScope('   '),
        throwsA(isA<IdentityRepositoryException>()),
      );
      expect(
        () => _textRequest(scope, 'Person A', candidateLimit: 0),
        throwsA(_applicationError('invalid_candidate_limit')),
      );
      expect(
        () => _textRequest(scope, 'Person A', candidateLimit: 21),
        throwsA(_applicationError('invalid_candidate_limit')),
      );
    });

    test('rejects invalid, mismatched, and contradictory evidence', () {
      expect(
        () => IdentityCandidateEvidence(entityId: '  '),
        throwsA(_applicationError('invalid_evidence_entity_id')),
      );
      final evidence = IdentityCandidateEvidence(entityId: 'entity-1');
      expect(
        () => IdentityResolutionRequest(
          scope: scope,
          reference: _textReference('Person A'),
          relationEvidenceByEntityId: {'entity-2': evidence},
        ),
        throwsA(_applicationError('invalid_evidence_entity_id')),
      );
      expect(
        () => IdentityCandidateEvidence(
          entityId: 'entity-1',
          relationSignals: [
            _relation('role', verified: true),
            _relation('role', verified: false),
          ],
        ),
        throwsA(_applicationError('contradictory_relation_evidence')),
      );
    });

    test('defensively freezes evidence, requests, and results', () async {
      final signals = [_relation('role', verified: true)];
      final evidence = IdentityCandidateEvidence(
        entityId: 'entity-1',
        relationSignals: signals,
      );
      final evidenceMap = {'entity-1': evidence};
      final request = IdentityResolutionRequest(
        scope: scope,
        reference: _relationReference('role'),
        relationEvidenceByEntityId: evidenceMap,
      );
      signals.clear();
      evidenceMap.clear();

      expect(evidence.relationSignals, hasLength(1));
      expect(request.relationEvidenceByEntityId, hasLength(1));
      expect(
        () => request.relationEvidenceByEntityId.clear(),
        throwsUnsupportedError,
      );

      await repository.seed(scope, [_entity()]);
      repository.indexRelation(scope, 'role', 'entity-1');
      final result = await service.resolve(request);
      expect(() => result.candidates.clear(), throwsUnsupportedError);
      expect(() => result.diagnosticCodes.clear(), throwsUnsupportedError);
    });
  });

  group('explicit ID', () {
    test('resolves an exact ID and transmits the account scope', () async {
      await repository.seed(scope, [_entity()]);
      final result = await service.resolve(_idRequest(scope, 'entity-1'));

      expect(result.status, IdentityApplicationStatus.resolved);
      expect(result.resolvedEntity?.id, 'entity-1');
      expect(repository.lastFindScope, scope);
    });

    test('returns notFound for an absent ID without text fallback', () async {
      await repository.seed(scope, [_entity(label: 'missing-id')]);
      final result = await service.resolve(_idRequest(scope, 'missing-id'));

      expect(result.status, IdentityApplicationStatus.notFound);
      expect(repository.queryCount, 0);
    });

    test('returns invalid for an incompatible expected type', () async {
      await repository.seed(scope, [_entity()]);
      final result = await service.resolve(
        _idRequest(scope, 'entity-1', expectedType: EntityType.place),
      );

      expect(result.status, IdentityApplicationStatus.invalid);
    });

    test('loads one merge target and resolves the safe redirect', () async {
      await repository.seed(scope, [
        _entity(
          id: 'entity-old',
          status: EntityStatus.merged,
          mergedIntoEntityId: 'entity-new',
        ),
        _entity(id: 'entity-new'),
      ]);
      final result = await service.resolve(_idRequest(scope, 'entity-old'));

      expect(result.status, IdentityApplicationStatus.resolved);
      expect(result.resolvedEntity?.id, 'entity-new');
      expect(repository.findCount, 2);
    });
  });

  group('text resolution', () {
    test('resolves exact aliases and canonical labels', () async {
      await repository.seed(scope, [
        _entity(id: 'entity-alias', label: 'Person A', alias: _alias('Friend')),
        _entity(
            id: 'entity-label', label: 'Primary Place', type: EntityType.place),
      ]);

      final alias = await service.resolve(_textRequest(scope, 'Friend'));
      final label = await service.resolve(
        _textRequest(scope, 'Primary Place', expectedType: EntityType.place),
      );

      expect(alias.resolvedEntity?.id, 'entity-alias');
      expect(label.resolvedEntity?.id, 'entity-label');
      expect(repository.lastQueryScope, scope);
    });

    test('preserves ambiguity and alias-label conflicts', () async {
      await repository.seed(scope, [
        _entity(id: 'entity-1', label: 'Shared'),
        _entity(id: 'entity-2', label: 'Person B', alias: _alias('Shared')),
      ]);

      final result = await service.resolve(_textRequest(scope, 'Shared'));
      expect(result.status, IdentityApplicationStatus.ambiguous);
      expect(result.candidates, hasLength(2));
    });

    test('applies expected type and requested limit to the query', () async {
      await repository.seed(scope, [
        _entity(id: 'person', label: 'Shared'),
        _entity(id: 'place', label: 'Shared', type: EntityType.place),
      ]);
      final result = await service.resolve(
        _textRequest(
          scope,
          'Shared',
          expectedType: EntityType.place,
          candidateLimit: 7,
        ),
      );

      expect(result.resolvedEntity?.id, 'place');
      expect(repository.lastQuery?.candidateLimit, 7);
      expect(repository.lastQuery?.expectedType, EntityType.place);
    });

    test('requires confirmation when the repository limit is reached',
        () async {
      await repository.seed(scope, [
        _entity(id: 'entity-1', label: 'Shared'),
        _entity(id: 'entity-2', label: 'Shared'),
      ]);

      final result = await service.resolve(
        _textRequest(scope, 'Shared', candidateLimit: 1),
      );

      expect(result.status, IdentityApplicationStatus.needsConfirmation);
      expect(result.diagnosticCodes, ['candidate_limit_reached']);
    });

    test('repository insertion order does not affect ambiguity', () async {
      final first = _entity(id: 'entity-1', label: 'Shared');
      final second = _entity(id: 'entity-2', label: 'Shared');
      await repository.seed(scope, [second, first]);
      final one = await service.resolve(_textRequest(scope, 'Shared'));

      final otherRepository = _SpyRepository();
      await otherRepository.seed(scope, [first, second]);
      final otherService = IdentityApplicationService(
        repository: otherRepository,
        engine: const IdentityEngine(),
        now: () => referenceDate,
      );
      final two = await otherService.resolve(_textRequest(scope, 'Shared'));

      expect(one.status, two.status);
      expect(
        one.candidates.map((candidate) => candidate.entity.id),
        two.candidates.map((candidate) => candidate.entity.id),
      );
    });
  });

  group('relations', () {
    test('resolves only explicitly verified relation evidence', () async {
      await repository.seed(scope, [_entity()]);
      repository.indexRelation(scope, 'role', 'entity-1');
      final result = await service.resolve(
        _relationRequest(scope, 'role', evidence: {
          'entity-1': IdentityCandidateEvidence(
            entityId: 'entity-1',
            relationSignals: [_relation('role', verified: true)],
          ),
        }),
      );

      expect(result.status, IdentityApplicationStatus.resolved);
    });

    test('does not turn repository relation matches into proof', () async {
      await repository.seed(scope, [_entity()]);
      repository.indexRelation(scope, 'role', 'entity-1');

      final absent = await service.resolve(_relationRequest(scope, 'role'));
      final unverified = await service.resolve(
        _relationRequest(scope, 'role', evidence: {
          'entity-1': IdentityCandidateEvidence(
            entityId: 'entity-1',
            relationSignals: [_relation('role', verified: false)],
          ),
        }),
      );

      expect(absent.status, IdentityApplicationStatus.notFound);
      expect(unverified.status, IdentityApplicationStatus.notFound);
    });

    test('preserves several verified relation candidates as ambiguous',
        () async {
      await repository.seed(scope, [
        _entity(id: 'entity-1'),
        _entity(id: 'entity-2'),
      ]);
      repository.indexRelation(scope, 'role', 'entity-1');
      repository.indexRelation(scope, 'role', 'entity-2');
      final result = await service.resolve(
        _relationRequest(scope, 'role', evidence: {
          for (final id in ['entity-1', 'entity-2'])
            id: IdentityCandidateEvidence(
              entityId: id,
              relationSignals: [_relation('role', verified: true)],
            ),
        }),
      );

      expect(result.status, IdentityApplicationStatus.ambiguous);
    });

    test('ignores evidence for an entity absent from repository results',
        () async {
      await repository.seed(scope, [_entity()]);
      final result = await service.resolve(
        _relationRequest(scope, 'role', evidence: {
          'entity-2': IdentityCandidateEvidence(
            entityId: 'entity-2',
            relationSignals: [_relation('role', verified: true)],
          ),
        }),
      );

      expect(result.status, IdentityApplicationStatus.notFound);
    });
  });

  group('pronouns and explicit targets', () {
    test('resolves one explicit target and never chooses by order', () async {
      await repository.seed(scope, [
        _entity(id: 'entity-1'),
        _entity(id: 'entity-2'),
      ]);
      final result = await service.resolve(
        _pronounRequest(scope, targetId: 'entity-2'),
      );

      expect(result.resolvedEntity?.id, 'entity-2');
      expect(repository.lastFindScope, scope);
    });

    test('returns notFound for an absent target and invalid for wrong type',
        () async {
      final absent = await service.resolve(
        _pronounRequest(scope, targetId: 'entity-2'),
      );
      await repository.seed(scope, [_entity(type: EntityType.person)]);
      final wrongType = await service.resolve(
        _pronounRequest(
          scope,
          targetId: 'entity-1',
          expectedType: EntityType.place,
        ),
      );

      expect(absent.status, IdentityApplicationStatus.notFound);
      expect(wrongType.status, IdentityApplicationStatus.notFound);
    });

    test('preserves several evidence targets as ambiguous', () async {
      await repository.seed(scope, [
        _entity(id: 'entity-1'),
        _entity(id: 'entity-2'),
      ]);
      final result = await service.resolve(
        _pronounRequest(scope, evidence: {
          for (final id in ['entity-1', 'entity-2'])
            id: IdentityCandidateEvidence(
              entityId: id,
              isExplicitConversationTarget: true,
            ),
        }),
      );

      expect(result.status, IdentityApplicationStatus.ambiguous);
    });
  });

  group('safe boundaries', () {
    test('maps repository exceptions without leaking their details', () async {
      repository.failReads = true;
      final result = await service.resolve(_textRequest(scope, 'Person A'));

      expect(result.status, IdentityApplicationStatus.repositoryFailure);
      expect(result.diagnosticCodes, ['repository_failure']);
      expect(result.diagnosticCodes.join(), isNot(contains('account-a')));
      expect(result.diagnosticCodes.join(), isNot(contains('Person A')));
    });

    test('maps an invalid domain resolution to invalid', () {
      final result = IdentityApplicationResult.fromResolution(
        EntityResolution.invalid(
          signals: const [EntityMatchSignal.duplicateEntityId],
          reasonCode: 'duplicate_candidate_id',
        ),
      );

      expect(result.status, IdentityApplicationStatus.invalid);
      expect(result.diagnosticCodes, contains('duplicate_candidate_id'));
    });

    test('never writes and does not mutate supplied entities', () async {
      final entity = _entity(metadata: {
        'nested': ['value'],
      });
      await repository.seed(scope, [entity]);
      repository.resetObservations();

      await service.resolve(_textRequest(scope, 'Person A'));

      expect(repository.saveCount, 0);
      expect(repository.saveAllCount, 0);
      expect(entity.metadata['nested'], ['value']);
    });

    test('keeps account scopes isolated', () async {
      final otherScope = IdentityAccountScope('account-b');
      await repository.seed(otherScope, [_entity()]);

      final result = await service.resolve(_textRequest(scope, 'Person A'));
      expect(result.status, IdentityApplicationStatus.notFound);
      expect(repository.lastQueryScope, scope);
    });
  });
}

final referenceDate = DateTime.utc(2026, 1, 15, 12);
const source = EntitySource(type: EntitySourceType.user);

LifeEntity _entity({
  String id = 'entity-1',
  String label = 'Person A',
  EntityType type = EntityType.person,
  EntityStatus status = EntityStatus.active,
  String? mergedIntoEntityId,
  EntityAlias? alias,
  Map<String, Object?> metadata = const {},
}) =>
    LifeEntity.fromLabel(
      id: id,
      type: type,
      canonicalLabel: label,
      aliases: alias == null ? const [] : [alias],
      status: status,
      source: source,
      createdAt: referenceDate,
      updatedAt: referenceDate,
      metadata: metadata,
      mergedIntoEntityId: mergedIntoEntityId,
    );

EntityAlias _alias(String value) => EntityAlias.fromValue(
      value: value,
      kind: EntityAliasKind.explicit,
      source: source,
      createdAt: referenceDate,
    );

EntityRelationSignal _relation(String key, {required bool verified}) =>
    EntityRelationSignal(
      relationKey: key,
      isVerified: verified,
      source: source,
    );

EntityReference _textReference(String value, {EntityType? expectedType}) =>
    EntityReference.text(
      value: value,
      kind: EntityReferenceKind.alias,
      expectedType: expectedType,
      source: source,
    );

EntityReference _relationReference(String key) => EntityReference.text(
      value: key,
      kind: EntityReferenceKind.relationalExpression,
      relationKey: key,
      source: source,
    );

IdentityResolutionRequest _textRequest(
  IdentityAccountScope scope,
  String value, {
  EntityType? expectedType,
  int candidateLimit = 20,
}) =>
    IdentityResolutionRequest(
      scope: scope,
      reference: _textReference(value, expectedType: expectedType),
      candidateLimit: candidateLimit,
    );

IdentityResolutionRequest _idRequest(
  IdentityAccountScope scope,
  String id, {
  EntityType? expectedType,
}) =>
    IdentityResolutionRequest(
      scope: scope,
      reference: EntityReference.byId(
        entityId: id,
        expectedType: expectedType,
        source: source,
      ),
    );

IdentityResolutionRequest _relationRequest(
  IdentityAccountScope scope,
  String key, {
  Map<String, IdentityCandidateEvidence> evidence = const {},
}) =>
    IdentityResolutionRequest(
      scope: scope,
      reference: _relationReference(key),
      relationEvidenceByEntityId: evidence,
    );

IdentityResolutionRequest _pronounRequest(
  IdentityAccountScope scope, {
  String? targetId,
  EntityType? expectedType,
  Map<String, IdentityCandidateEvidence> evidence = const {},
}) =>
    IdentityResolutionRequest(
      scope: scope,
      reference: EntityReference.text(
        value: 'them',
        kind: EntityReferenceKind.pronoun,
        expectedType: expectedType,
        source: source,
      ),
      explicitConversationTargetEntityId: targetId,
      relationEvidenceByEntityId: evidence,
    );

Matcher _applicationError(String code) => isA<IdentityApplicationException>()
    .having((error) => error.code, 'code', code);

final class _SpyRepository implements IdentityReadRepository {
  final FakeIdentityRepository _delegate = FakeIdentityRepository();
  int findCount = 0;
  int queryCount = 0;
  int saveCount = 0;
  int saveAllCount = 0;
  bool failReads = false;
  IdentityAccountScope? lastFindScope;
  IdentityAccountScope? lastQueryScope;
  IdentityRepositoryQuery? lastQuery;

  Future<void> seed(
    IdentityAccountScope scope,
    List<LifeEntity> entities,
  ) async {
    await _delegate.seedAll(scope: scope, entities: entities);
  }

  void indexRelation(
    IdentityAccountScope scope,
    String relationKey,
    String entityId,
  ) {
    _delegate.indexRelation(
      scope: scope,
      relationKey: relationKey,
      entityId: entityId,
    );
  }

  void resetObservations() {
    findCount = 0;
    queryCount = 0;
    saveCount = 0;
    saveAllCount = 0;
  }

  @override
  Future<LifeEntity?> findById({
    required IdentityAccountScope scope,
    required String entityId,
  }) {
    findCount++;
    lastFindScope = scope;
    if (failReads) {
      throw const IdentityRepositoryException('internal_name_or_alias');
    }
    return _delegate.findById(scope: scope, entityId: entityId);
  }

  @override
  Future<List<LifeEntity>> findByIds({
    required IdentityAccountScope scope,
    required List<String> entityIds,
  }) {
    lastFindScope = scope;
    if (failReads) {
      throw const IdentityRepositoryException('internal_name_or_alias');
    }
    return _delegate.findByIds(scope: scope, entityIds: entityIds);
  }

  @override
  Future<IdentityRepositoryQueryResult> queryCandidates({
    required IdentityAccountScope scope,
    required IdentityRepositoryQuery query,
  }) async {
    queryCount++;
    lastQueryScope = scope;
    lastQuery = query;
    if (failReads) {
      throw const IdentityRepositoryException('internal_name_or_alias');
    }
    return _delegate.queryCandidates(scope: scope, query: query);
  }
}
