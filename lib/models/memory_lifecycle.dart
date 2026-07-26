import 'dart:collection';

import 'life_context/life_context_provenance.dart';
import 'life_context/memory_context.dart';
import 'memory_evidence.dart';
import 'memory_contradiction.dart';
import 'memory_lifecycle_state.dart';
import 'memory_semantic_identity.dart';

enum MemoryLifecycleDecisionType {
  createProposal,
  confirmExistingProposal,
  rejectProposal,
  createNewMemory,
  replaceExistingMemory,
  markExistingObsolete,
  deleteExistingMemory,
  noChange,
  needsUserConfirmation,
  ambiguous,
  invalidTransition,
}

enum MemoryLifecycleSignal {
  duplicate,
  possibleConflict,
  possibleReplacement,
  profileConflict,
  sensitiveData,
  ambiguousTimeRange,
  invalidInput,
}

final class MemoryLifecycleRecord {
  final MemoryLifecycleAction action;
  final MemoryLifecycleState? previousState;
  final MemoryLifecycleState newState;
  final DateTime occurredAt;
  final String source;
  final MemoryLifecycleActor actor;
  final String memoryId;
  final String? replacementMemoryId;
  final String? reason;
  final Map<String, Object?> _metadata;

  MemoryLifecycleRecord({
    required this.action,
    required this.previousState,
    required this.newState,
    required this.occurredAt,
    required this.source,
    required this.actor,
    required this.memoryId,
    this.replacementMemoryId,
    this.reason,
    Map<String, Object?> metadata = const {},
  }) : _metadata = _freezeMap(metadata);

  Map<String, Object?> get metadata => UnmodifiableMapView(_metadata);

  String get idempotencyKey => [
        action.name,
        previousState?.name ?? '',
        newState.name,
        memoryId,
        replacementMemoryId ?? '',
      ].join(':');

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'previousState': previousState?.name,
        'newState': newState.name,
        'occurredAt': occurredAt.toIso8601String(),
        'source': source,
        'actor': actor.name,
        'memoryId': memoryId,
        if (replacementMemoryId != null)
          'replacementMemoryId': replacementMemoryId,
        if (reason != null) 'reason': reason,
        if (_metadata.isNotEmpty) 'metadata': _copyMap(_metadata),
      };
}

final class MemoryProposal {
  final String id;
  final String text;
  final String normalizedText;
  final LifeMemorySemanticType semanticType;
  final String category;
  final int importance;
  final LifeContextSensitivity sensitivity;
  final String source;
  final DateTime proposedAt;
  final bool confirmationRequired;
  final String? potentiallyReplacesMemoryId;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? expiresAt;
  final String? evidence;
  final MemoryEvidenceClassification evidenceClassification;
  final MemoryEvidenceSubjectType evidenceSubjectType;
  final String? subjectEntityId;
  final List<MemoryEvidenceRisk> evidenceRisks;
  final bool isCorrection;
  final MemorySemanticIdentity? semanticIdentity;
  final String? semanticValue;
  final double? confidence;

  const MemoryProposal({
    required this.id,
    required this.text,
    required this.normalizedText,
    required this.semanticType,
    required this.category,
    required this.importance,
    required this.sensitivity,
    required this.source,
    required this.proposedAt,
    required this.confirmationRequired,
    this.potentiallyReplacesMemoryId,
    this.validFrom,
    this.validUntil,
    this.expiresAt,
    this.evidence,
    this.evidenceClassification = MemoryEvidenceClassification.unknown,
    this.evidenceSubjectType = MemoryEvidenceSubjectType.unknown,
    this.subjectEntityId,
    this.evidenceRisks = const [],
    this.isCorrection = false,
    this.semanticIdentity,
    this.semanticValue,
    this.confidence,
  });

  bool get hasValidDates =>
      validFrom == null ||
      validUntil == null ||
      !validUntil!.isBefore(validFrom!);
}

final class MemoryLifecycleMutation {
  final String memoryId;
  final MemoryLifecycleState newState;
  final MemoryLifecycleRecord record;
  final String? replacedByMemoryId;
  final String? supersedesMemoryId;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;
  final DateTime? deletedAt;
  final DateTime? expiresAt;

  const MemoryLifecycleMutation({
    required this.memoryId,
    required this.newState,
    required this.record,
    this.replacedByMemoryId,
    this.supersedesMemoryId,
    this.confirmedAt,
    this.rejectedAt,
    this.deletedAt,
    this.expiresAt,
  });
}

final class MemoryConfirmationRequest {
  final MemoryLifecycleAction action;
  final String? proposalId;
  final String? memoryId;
  final String prompt;
  final String? previousValue;
  final String? newValue;
  final String changeType;
  final LifeContextSensitivity sensitivity;
  final String consequence;
  final MemoryContradictionCandidate? contradictionCandidate;
  final MemoryReplacementPendingAction? replacementPendingAction;

  const MemoryConfirmationRequest({
    required this.action,
    required this.prompt,
    required this.changeType,
    required this.sensitivity,
    required this.consequence,
    this.proposalId,
    this.memoryId,
    this.previousValue,
    this.newValue,
    this.contradictionCandidate,
    this.replacementPendingAction,
  });
}

final class MemoryLifecycleDecision {
  final MemoryLifecycleDecisionType type;
  final List<String> memoryIds;
  final List<String> reasons;
  final List<MemoryLifecycleSignal> risks;
  final List<MemoryLifecycleMutation> mutations;
  final MemoryConfirmationRequest? confirmationRequest;
  final MemoryProposal? proposal;
  final MemoryContradictionCandidate? contradictionCandidate;
  final MemoryContradictionMatch? contradictionMatch;

  MemoryLifecycleDecision({
    required this.type,
    List<String> memoryIds = const [],
    List<String> reasons = const [],
    List<MemoryLifecycleSignal> risks = const [],
    List<MemoryLifecycleMutation> mutations = const [],
    this.confirmationRequest,
    this.proposal,
    this.contradictionCandidate,
    this.contradictionMatch,
  })  : memoryIds = List.unmodifiable(memoryIds),
        reasons = List.unmodifiable(reasons),
        risks = List.unmodifiable(risks),
        mutations = List.unmodifiable(mutations);

  bool get hasMutations => mutations.isNotEmpty;
}

final class MemoryLifecycleCommand {
  final MemoryLifecycleAction action;
  final DateTime referenceDate;
  final MemoryLifecycleActor actor;
  final String source;
  final LifeMemoryFact? target;
  final MemoryProposal? proposal;
  final LifeMemoryFact? replacement;
  final MemoryLifecycleState? targetState;
  final List<MemoryLifecycleRecord> history;
  final String? reason;
  final String? conflictingProfileField;

  MemoryLifecycleCommand({
    required this.action,
    required this.referenceDate,
    required this.actor,
    required this.source,
    this.target,
    this.proposal,
    this.replacement,
    this.targetState,
    List<MemoryLifecycleRecord> history = const [],
    this.reason,
    this.conflictingProfileField,
  }) : history = List.unmodifiable(history);
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    Map.unmodifiable(
      source.map((key, value) => MapEntry(key, _freeze(value))),
    );

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map.unmodifiable(
      value.map((key, child) => MapEntry(key.toString(), _freeze(child))),
    );
  }
  if (value is List) return List.unmodifiable(value.map(_freeze));
  if (value is Set) return Set.unmodifiable(value.map(_freeze));
  return value;
}

Map<String, Object?> _copyMap(Map<String, Object?> source) =>
    source.map((key, value) => MapEntry(key, _copy(value)));

Object? _copy(Object? value) {
  if (value is Map) {
    return value.map((key, child) => MapEntry(key.toString(), _copy(child)));
  }
  if (value is Iterable) return value.map(_copy).toList();
  return value;
}
