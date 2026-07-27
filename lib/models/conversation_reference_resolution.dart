import 'dart:collection';

enum ConversationReferenceResolutionStatus {
  resolved,
  ambiguous,
  unresolved,
  unsupported,
}

enum ConversationReferenceType {
  explicitMention,
  pronoun,
  possessive,
  demonstrative,
  repetition,
  temporalTarget,
}

enum ConversationReferenceEntityType {
  person,
  household,
  residence,
  event,
  task,
  routine,
  structuredPlace,
}

enum ConversationReferenceSource {
  currentMessage,
  validatedConversationHistory,
  lifeContext,
  pendingAction,
  explicitEntityMention,
}

enum ConversationReferenceReasonCode {
  resolvedByExplicitMention,
  resolvedByPendingAction,
  resolvedByValidatedHistory,
  resolvedByUniqueLifeContextRelation,
  multipleExplicitCandidates,
  multiplePendingCandidates,
  multipleHistoryCandidates,
  multipleLifeContextCandidates,
  explicitMentionNotFound,
  missingAntecedent,
  staleOrUnvalidatedHistory,
  entityNotLocallyVerified,
  accountScopeMismatch,
  inactiveOrDeletedEntity,
  invalidStableId,
  unsupportedEntityType,
  unsupportedReference,
}

final class ConversationReferenceResolution {
  static const int currentSchemaVersion = 1;
  static const int maximumCandidateIds = 20;

  ConversationReferenceResolution({
    this.schemaVersion = currentSchemaVersion,
    required this.status,
    required this.referenceType,
    required this.entityType,
    this.entityId,
    List<String> candidateIds = const [],
    required this.source,
    required this.reasonCode,
  }) : candidateIds = UnmodifiableListView(
          List<String>.of(candidateIds)..sort(),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        candidateIds.length > maximumCandidateIds ||
        candidateIds.any((id) => !_isValidId(id)) ||
        candidateIds.toSet().length != candidateIds.length ||
        (status == ConversationReferenceResolutionStatus.resolved) !=
            _isValidId(entityId) ||
        status == ConversationReferenceResolutionStatus.ambiguous &&
            candidateIds.length < 2 ||
        status != ConversationReferenceResolutionStatus.resolved &&
            entityId != null) {
      throw const FormatException('invalid_conversation_reference_resolution');
    }
  }

  final int schemaVersion;
  final ConversationReferenceResolutionStatus status;
  final ConversationReferenceType referenceType;
  final ConversationReferenceEntityType entityType;
  final String? entityId;
  final List<String> candidateIds;
  final ConversationReferenceSource source;
  final ConversationReferenceReasonCode reasonCode;

  Map<String, Object> toDiagnosticMetadata() => {
        'referenceType': referenceType.name,
        'entityType': entityType.name,
        'candidateCount': candidateIds.length,
        'reasonCode': reasonCode.name,
        'resolved': status == ConversationReferenceResolutionStatus.resolved,
      };
}

bool _isValidId(String? value) => value != null && value.trim().isNotEmpty;
