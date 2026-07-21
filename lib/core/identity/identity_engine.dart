import 'entity_candidate.dart';
import 'entity_identity.dart';
import 'entity_reference.dart';
import 'entity_resolution.dart';
import 'entity_types.dart';
import 'life_entity.dart';

final class IdentityEngine {
  static const int maxCandidates = 20;

  const IdentityEngine();

  EntityResolution resolve({
    required EntityReference reference,
    required List<EntityCandidate> candidates,
    required DateTime referenceDate,
  }) {
    if (candidates.length > maxCandidates) {
      return EntityResolution.invalid(
        signals: const [EntityMatchSignal.candidateLimitExceeded],
        reasonCode: 'candidate_limit_exceeded',
      );
    }
    final sorted = List<EntityCandidate>.of(candidates)
      ..sort((first, second) => first.entity.id.compareTo(second.entity.id));
    if (_hasDuplicateIds(sorted)) {
      return EntityResolution.invalid(
        signals: const [EntityMatchSignal.duplicateEntityId],
        reasonCode: 'duplicate_candidate_id',
      );
    }

    if (reference.kind == EntityReferenceKind.explicitId) {
      return _resolveExplicitId(reference, sorted);
    }
    if (reference.kind == EntityReferenceKind.pronoun ||
        reference.conversationTargetEntityId != null ||
        sorted.any((candidate) => candidate.isExplicitConversationTarget)) {
      final conversation = _resolveConversationTarget(reference, sorted);
      if (conversation != null) return conversation;
    }
    if (reference.kind == EntityReferenceKind.relationalExpression) {
      return _resolveRelation(reference, sorted);
    }
    return _resolveText(reference, sorted, referenceDate);
  }

  EntityResolution _resolveExplicitId(
    EntityReference reference,
    List<EntityCandidate> candidates,
  ) {
    final id = reference.explicitEntityId!;
    final matching =
        candidates.where((candidate) => candidate.entity.id == id).toList();
    if (matching.isEmpty) {
      return EntityResolution.notFound(reasonCode: 'explicit_id_not_found');
    }
    final candidate = matching.single;
    final entity = candidate.entity;
    if (!_typeMatches(reference, entity)) {
      return EntityResolution.invalid(
        signals: const [EntityMatchSignal.typeMismatch],
        reasonCode: 'explicit_id_type_mismatch',
      );
    }
    if (entity.status == EntityStatus.deleted) {
      return EntityResolution.notFound(
        signals: const [EntityMatchSignal.deletedEntityIgnored],
        reasonCode: 'explicit_id_deleted',
      );
    }
    if (entity.status == EntityStatus.inactive) {
      return EntityResolution.notFound(
        signals: const [EntityMatchSignal.inactiveEntityIgnored],
        reasonCode: 'explicit_id_inactive',
      );
    }
    if (entity.status == EntityStatus.merged) {
      return _redirectMerged(reference, candidate, candidates);
    }
    return _resolved(
      entity,
      EntityResolutionConfidence.exact,
      EntityMatchSignal.exactId,
      reference,
      'resolved_by_exact_id',
    );
  }

  EntityResolution _redirectMerged(
    EntityReference reference,
    EntityCandidate source,
    List<EntityCandidate> candidates,
  ) {
    final targetId = source.entity.mergedIntoEntityId!;
    if (!EntityIdentity.isValid(targetId) || targetId == source.entity.id) {
      return EntityResolution.invalid(
        signals: const [EntityMatchSignal.mergedRedirect],
        reasonCode: 'invalid_merge_redirect',
      );
    }
    final targets = candidates
        .where((candidate) => candidate.entity.id == targetId)
        .toList();
    if (targets.isEmpty) {
      return EntityResolution.needsConfirmation(
        candidates: [source],
        signals: const [EntityMatchSignal.mergedRedirect],
        reasonCode: 'merge_target_missing',
      );
    }
    final target = targets.single.entity;
    if (target.status == EntityStatus.merged) {
      final isCycle = target.mergedIntoEntityId == source.entity.id;
      return isCycle
          ? EntityResolution.invalid(
              signals: const [EntityMatchSignal.mergedRedirect],
              reasonCode: 'merge_cycle_detected',
            )
          : EntityResolution.needsConfirmation(
              candidates: [source, targets.single],
              signals: const [EntityMatchSignal.mergedRedirect],
              reasonCode: 'merge_depth_exceeded',
            );
    }
    if (target.status != EntityStatus.active ||
        !_typeMatches(reference, target)) {
      return EntityResolution.needsConfirmation(
        candidates: [source, targets.single],
        signals: [
          EntityMatchSignal.mergedRedirect,
          if (!_typeMatches(reference, target)) EntityMatchSignal.typeMismatch,
          if (target.status == EntityStatus.deleted)
            EntityMatchSignal.deletedEntityIgnored,
        ],
        reasonCode: 'merge_target_not_resolvable',
      );
    }
    return _resolved(
      target,
      EntityResolutionConfidence.strong,
      EntityMatchSignal.mergedRedirect,
      reference,
      'resolved_by_merge_redirect',
    );
  }

  EntityResolution? _resolveConversationTarget(
    EntityReference reference,
    List<EntityCandidate> candidates,
  ) {
    final active = _activeCompatible(reference, candidates);
    final targetId = reference.conversationTargetEntityId;
    final matches = targetId == null
        ? active
            .where((candidate) => candidate.isExplicitConversationTarget)
            .toList()
        : active.where((candidate) => candidate.entity.id == targetId).toList();
    if (matches.length == 1) {
      return _resolved(
        matches.single.entity,
        EntityResolutionConfidence.strong,
        EntityMatchSignal.explicitConversationTarget,
        reference,
        'resolved_by_explicit_conversation_target',
      );
    }
    if (matches.length > 1) {
      return EntityResolution.ambiguous(
        candidates: matches,
        signals: const [
          EntityMatchSignal.explicitConversationTarget,
          EntityMatchSignal.multipleCandidates,
        ],
        reasonCode: 'multiple_conversation_targets',
      );
    }
    if (reference.kind == EntityReferenceKind.pronoun || targetId != null) {
      return active.isEmpty
          ? EntityResolution.notFound(
              signals: const [EntityMatchSignal.missingContext],
              reasonCode: 'conversation_target_not_found',
            )
          : EntityResolution.needsConfirmation(
              candidates: active,
              signals: const [EntityMatchSignal.missingContext],
              reasonCode: 'conversation_target_missing',
            );
    }
    return null;
  }

  EntityResolution _resolveRelation(
    EntityReference reference,
    List<EntityCandidate> candidates,
  ) {
    final relationKey = reference.relationKey!.trim();
    final matches = _activeCompatible(reference, candidates).where((candidate) {
      return candidate.relationSignals.any(
        (signal) =>
            signal.isVerified && signal.relationKey.trim() == relationKey,
      );
    }).toList();
    if (matches.isEmpty) {
      return EntityResolution.notFound(
        signals: const [EntityMatchSignal.missingContext],
        reasonCode: 'verified_relation_not_found',
      );
    }
    if (matches.length > 1) {
      return EntityResolution.ambiguous(
        candidates: matches,
        signals: const [
          EntityMatchSignal.verifiedRelation,
          EntityMatchSignal.multipleCandidates,
        ],
        reasonCode: 'multiple_verified_relations',
      );
    }
    return _resolved(
      matches.single.entity,
      EntityResolutionConfidence.strong,
      EntityMatchSignal.verifiedRelation,
      reference,
      'resolved_by_verified_relation',
    );
  }

  EntityResolution _resolveText(
    EntityReference reference,
    List<EntityCandidate> candidates,
    DateTime referenceDate,
  ) {
    final key = reference.comparisonKey!;
    final aliasMatches = <EntityCandidate>[];
    final labelMatches = <EntityCandidate>[];
    final ignoredSignals = <EntityMatchSignal>[];

    for (final candidate in candidates) {
      final entity = candidate.entity;
      final labelMatchesKey = entity.comparisonKey == key;
      final aliasesMatchingKey =
          entity.aliases.where((alias) => alias.comparisonKey == key);
      if (entity.status == EntityStatus.deleted) {
        if (labelMatchesKey || aliasesMatchingKey.isNotEmpty) {
          ignoredSignals.add(EntityMatchSignal.deletedEntityIgnored);
        }
        continue;
      }
      if (entity.status != EntityStatus.active) {
        if (labelMatchesKey || aliasesMatchingKey.isNotEmpty) {
          ignoredSignals.add(EntityMatchSignal.inactiveEntityIgnored);
        }
        continue;
      }
      if (!_typeMatches(reference, entity)) {
        if (labelMatchesKey || aliasesMatchingKey.isNotEmpty) {
          ignoredSignals.add(EntityMatchSignal.typeMismatch);
        }
        continue;
      }
      for (final alias in aliasesMatchingKey) {
        if ((alias.removedAt != null &&
                !referenceDate.isBefore(alias.removedAt!)) ||
            (alias.validFrom != null &&
                referenceDate.isBefore(alias.validFrom!))) {
          ignoredSignals.add(EntityMatchSignal.inactiveAliasIgnored);
        } else if (alias.validUntil != null &&
            referenceDate.isAfter(alias.validUntil!)) {
          ignoredSignals.add(EntityMatchSignal.expiredAliasIgnored);
        } else {
          aliasMatches.add(candidate);
          break;
        }
      }
      if (labelMatchesKey) labelMatches.add(candidate);
    }

    final plausible = <String, EntityCandidate>{};
    for (final candidate in [...aliasMatches, ...labelMatches]) {
      plausible[candidate.entity.id] = candidate;
    }
    if (plausible.length > 1) {
      return EntityResolution.ambiguous(
        candidates: plausible.values.toList()
          ..sort((a, b) => a.entity.id.compareTo(b.entity.id)),
        signals: [
          if (aliasMatches.isNotEmpty) EntityMatchSignal.exactAlias,
          if (labelMatches.isNotEmpty) EntityMatchSignal.exactCanonicalLabel,
          EntityMatchSignal.multipleCandidates,
          ...ignoredSignals,
        ],
        reasonCode: 'multiple_exact_text_candidates',
      );
    }
    if (aliasMatches.length == 1) {
      return _resolved(
        aliasMatches.single.entity,
        EntityResolutionConfidence.strong,
        EntityMatchSignal.exactAlias,
        reference,
        'resolved_by_exact_alias',
        additionalSignals: [
          if (labelMatches.isNotEmpty) EntityMatchSignal.exactCanonicalLabel,
          ...ignoredSignals,
        ],
      );
    }
    if (labelMatches.length == 1) {
      return _resolved(
        labelMatches.single.entity,
        EntityResolutionConfidence.strong,
        EntityMatchSignal.exactCanonicalLabel,
        reference,
        'resolved_by_exact_canonical_label',
        additionalSignals: ignoredSignals,
      );
    }
    return EntityResolution.notFound(
      signals: ignoredSignals,
      reasonCode: 'no_exact_identity_match',
    );
  }

  List<EntityCandidate> _activeCompatible(
    EntityReference reference,
    List<EntityCandidate> candidates,
  ) {
    return candidates.where((candidate) {
      return candidate.entity.status == EntityStatus.active &&
          _typeMatches(reference, candidate.entity);
    }).toList();
  }

  bool _typeMatches(EntityReference reference, LifeEntity entity) {
    return reference.expectedType == null ||
        reference.expectedType == entity.type;
  }

  EntityResolution _resolved(
    LifeEntity entity,
    EntityResolutionConfidence confidence,
    EntityMatchSignal signal,
    EntityReference reference,
    String reasonCode, {
    List<EntityMatchSignal> additionalSignals = const [],
  }) {
    return EntityResolution.resolved(
      entity: entity,
      confidence: confidence,
      signals: [
        signal,
        if (reference.expectedType != null)
          EntityMatchSignal.expectedTypeMatched,
        ...additionalSignals,
      ],
      reasonCode: reasonCode,
    );
  }

  bool _hasDuplicateIds(List<EntityCandidate> candidates) {
    final ids = <String>{};
    return candidates.any((candidate) => !ids.add(candidate.entity.id));
  }
}
