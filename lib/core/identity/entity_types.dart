enum EntityType {
  person,
  place,
  organization,
  household,
  group,
  activity,
  vehicle,
  pet,
  product,
  unknown,
}

enum EntityStatus { active, inactive, merged, deleted }

enum EntitySourceType {
  profile,
  user,
  memory,
  conversation,
  imported,
  historical,
  system,
  unknown,
}

enum EntityAliasKind { explicit, learned, temporary }

enum EntityReferenceKind {
  explicitId,
  canonicalLabel,
  alias,
  relationalExpression,
  pronoun,
  genericLabel,
  unknown,
}

enum EntityResolutionStatus {
  resolved,
  ambiguous,
  notFound,
  needsConfirmation,
  invalid,
}

enum EntityResolutionConfidence { exact, strong, insufficient }

enum EntityMatchSignal {
  exactId,
  exactCanonicalLabel,
  exactAlias,
  expectedTypeMatched,
  explicitConversationTarget,
  verifiedRelation,
  mergedRedirect,
  inactiveAliasIgnored,
  expiredAliasIgnored,
  deletedEntityIgnored,
  inactiveEntityIgnored,
  multipleCandidates,
  missingContext,
  typeMismatch,
  duplicateEntityId,
  candidateLimitExceeded,
}

final class EntityDomainException implements Exception {
  final String code;

  const EntityDomainException(this.code);

  @override
  String toString() => 'EntityDomainException($code)';
}

final class EntitySource {
  final EntitySourceType type;
  final String? sourceId;

  const EntitySource({required this.type, this.sourceId});
}
