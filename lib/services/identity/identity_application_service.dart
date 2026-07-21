import '../../core/identity/entity_candidate.dart';
import '../../core/identity/entity_identity.dart';
import '../../core/identity/entity_resolution.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/identity_engine.dart';
import '../../core/identity/life_entity.dart';
import '../../repositories/identity/identity_repository.dart';
import '../../repositories/identity/identity_repository_query.dart';
import 'identity_application_models.dart';

final class IdentityApplicationService {
  final IdentityRepository _repository;
  final IdentityEngine _engine;
  final DateTime Function() _now;

  IdentityApplicationService({
    required IdentityRepository repository,
    required IdentityEngine engine,
    DateTime Function()? now,
  })  : _repository = repository,
        _engine = engine,
        _now = now ?? DateTime.now;

  Future<IdentityApplicationResult> resolve(
    IdentityResolutionRequest request,
  ) async {
    final referenceDate = request.resolveReferenceDate(_now);
    try {
      final loaded = await _loadEntities(request, referenceDate);
      final candidates = _buildCandidates(request, loaded.entities);
      if (loaded.limitReached) {
        return IdentityApplicationResult.fromResolution(
          EntityResolution.needsConfirmation(
            candidates: candidates,
            signals: const [EntityMatchSignal.multipleCandidates],
            reasonCode: 'candidate_limit_reached',
          ),
        );
      }
      final resolution = _engine.resolve(
        reference: request.reference,
        candidates: candidates,
        referenceDate: referenceDate,
      );
      return IdentityApplicationResult.fromResolution(resolution);
    } on IdentityRepositoryException {
      return IdentityApplicationResult.repositoryFailure();
    } on EntityDomainException catch (error) {
      return IdentityApplicationResult.fromResolution(
        EntityResolution.invalid(signals: const [], reasonCode: error.code),
      );
    }
  }

  Future<({List<LifeEntity> entities, bool limitReached})> _loadEntities(
    IdentityResolutionRequest request,
    DateTime referenceDate,
  ) async {
    final reference = request.reference;
    if (reference.kind == EntityReferenceKind.explicitId) {
      return (
        entities: await _loadExplicitId(request, reference.explicitEntityId!),
        limitReached: false,
      );
    }

    final targetId = request.explicitConversationTargetEntityId ??
        reference.conversationTargetEntityId;
    if (targetId != null) {
      final target = await _repository.findById(
        scope: request.scope,
        entityId: targetId,
      );
      return (
        entities: target == null ? const <LifeEntity>[] : [target],
        limitReached: false,
      );
    }

    if (reference.kind == EntityReferenceKind.pronoun) {
      final evidenceIds = request.relationEvidenceByEntityId.values
          .where((evidence) => evidence.isExplicitConversationTarget)
          .map((evidence) => evidence.entityId)
          .toList(growable: false);
      if (evidenceIds.isEmpty) {
        return (entities: const <LifeEntity>[], limitReached: false);
      }
      return (
        entities: await _repository.findByIds(
          scope: request.scope,
          entityIds: evidenceIds,
        ),
        limitReached: false,
      );
    }

    if (reference.kind == EntityReferenceKind.relationalExpression) {
      final result = await _repository.queryCandidates(
        scope: request.scope,
        query: IdentityRepositoryQuery.forRelations(
          relationKeys: [reference.relationKey!],
          expectedType: reference.expectedType,
          candidateLimit: request.candidateLimit,
        ),
      );
      return (
        entities: result.entities,
        limitReached: result.limitReached,
      );
    }

    final comparisonKey = reference.comparisonKey;
    if (comparisonKey == null || comparisonKey.isEmpty) {
      return (entities: const <LifeEntity>[], limitReached: false);
    }
    final result = await _repository.queryCandidates(
      scope: request.scope,
      query: IdentityRepositoryQuery.byComparisonKey(
        comparisonKey: comparisonKey,
        expectedType: reference.expectedType,
        candidateLimit: request.candidateLimit,
        referenceDate: referenceDate,
      ),
    );
    return (
      entities: result.entities,
      limitReached: result.limitReached,
    );
  }

  Future<List<LifeEntity>> _loadExplicitId(
    IdentityResolutionRequest request,
    String entityId,
  ) async {
    final entity = await _repository.findById(
      scope: request.scope,
      entityId: entityId,
    );
    if (entity == null) return const [];
    if (entity.status != EntityStatus.merged ||
        !EntityIdentity.isValid(entity.mergedIntoEntityId)) {
      return [entity];
    }
    final target = await _repository.findById(
      scope: request.scope,
      entityId: entity.mergedIntoEntityId!,
    );
    return target == null ? [entity] : [entity, target];
  }

  List<EntityCandidate> _buildCandidates(
    IdentityResolutionRequest request,
    List<LifeEntity> entities,
  ) {
    final targetId = request.explicitConversationTargetEntityId ??
        request.reference.conversationTargetEntityId;
    return List.unmodifiable(entities.map((entity) {
      final evidence = request.relationEvidenceByEntityId[entity.id];
      return EntityCandidate(
        entity: entity,
        relationSignals: evidence?.relationSignals ?? const [],
        isExplicitConversationTarget: targetId == entity.id ||
            (evidence?.isExplicitConversationTarget ?? false),
      );
    }));
  }
}
