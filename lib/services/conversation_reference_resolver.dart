import 'dart:collection';

import '../core/identity/entity_identity.dart';
import '../core/identity/entity_types.dart';
import '../models/conversation_reference_resolution.dart';
import 'event_target_selector.dart';
import 'identity/identity_application_models.dart';

final class ConversationReferenceCandidate {
  ConversationReferenceCandidate({
    required this.entityId,
    required this.entityType,
    required String accountScopeId,
    required this.source,
    this.isActive = true,
    this.isLocallyVerified = true,
  }) : accountScopeId = accountScopeId.trim() {
    if (!EntityIdentity.isValid(entityId) || this.accountScopeId.isEmpty) {
      throw const FormatException('invalid_conversation_reference_candidate');
    }
  }

  final String entityId;
  final ConversationReferenceEntityType entityType;
  final String accountScopeId;
  final ConversationReferenceSource source;
  final bool isActive;
  final bool isLocallyVerified;
}

final class ValidatedConversationReference {
  static const int currentSchemaVersion = 1;
  static const Duration maximumLifetime = Duration(minutes: 15);

  ValidatedConversationReference({
    this.schemaVersion = currentSchemaVersion,
    required this.entityId,
    required this.entityType,
    required String accountScopeId,
    required this.validatedAt,
    required this.expiresAt,
    this.source = ConversationReferenceSource.validatedConversationHistory,
  }) : accountScopeId = accountScopeId.trim() {
    if (schemaVersion != currentSchemaVersion ||
        !EntityIdentity.isValid(entityId) ||
        this.accountScopeId.isEmpty ||
        !expiresAt.isAfter(validatedAt) ||
        expiresAt.difference(validatedAt) > maximumLifetime) {
      throw const FormatException('invalid_validated_conversation_reference');
    }
  }

  final int schemaVersion;
  final String entityId;
  final ConversationReferenceEntityType entityType;
  final String accountScopeId;
  final DateTime validatedAt;
  final DateTime expiresAt;
  final ConversationReferenceSource source;

  bool isValidAt(DateTime value) =>
      !value.isBefore(validatedAt) && value.isBefore(expiresAt);

  Map<String, Object> toPersistedJson() => {
        'schemaVersion': schemaVersion,
        'entityType': entityType.name,
        'entityId': entityId,
        'validatedAt': validatedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'source': source.name,
      };

  static ValidatedConversationReference fromPersistedJson(
    Map<String, dynamic> json, {
    required String accountScopeId,
  }) {
    final entityType = ConversationReferenceEntityType.values
        .where((value) => value.name == json['entityType'])
        .firstOrNull;
    final source = ConversationReferenceSource.values
        .where((value) => value.name == json['source'])
        .firstOrNull;
    final validatedAt =
        DateTime.tryParse(json['validatedAt']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (entityType == null ||
        source == null ||
        validatedAt == null ||
        expiresAt == null ||
        json['schemaVersion'] is! int ||
        json['entityId'] is! String) {
      throw const FormatException('invalid_validated_reference_payload');
    }
    return ValidatedConversationReference(
      schemaVersion: json['schemaVersion'] as int,
      entityId: json['entityId'] as String,
      entityType: entityType,
      accountScopeId: accountScopeId,
      validatedAt: validatedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      source: source,
    );
  }
}

final class ConversationReferenceRequest {
  ConversationReferenceRequest({
    required String accountScopeId,
    required this.referenceType,
    required this.entityType,
    this.hasExplicitMention = false,
    this.allowLifeContextRelation = false,
    this.isSupported = true,
    this.backendProposedEntityId,
    List<ConversationReferenceCandidate> explicitCandidates = const [],
    List<ConversationReferenceCandidate> pendingCandidates = const [],
    List<ValidatedConversationReference> validatedHistory = const [],
    List<ConversationReferenceCandidate> lifeContextCandidates = const [],
  })  : accountScopeId = accountScopeId.trim(),
        explicitCandidates = UnmodifiableListView(explicitCandidates),
        pendingCandidates = UnmodifiableListView(pendingCandidates),
        validatedHistory = UnmodifiableListView(validatedHistory),
        lifeContextCandidates = UnmodifiableListView(lifeContextCandidates) {
    if (this.accountScopeId.isEmpty ||
        backendProposedEntityId != null &&
            !EntityIdentity.isValid(backendProposedEntityId)) {
      throw const FormatException('invalid_conversation_reference_request');
    }
  }

  final String accountScopeId;
  final ConversationReferenceType referenceType;
  final ConversationReferenceEntityType entityType;
  final bool hasExplicitMention;
  final bool allowLifeContextRelation;
  final bool isSupported;
  final String? backendProposedEntityId;
  final List<ConversationReferenceCandidate> explicitCandidates;
  final List<ConversationReferenceCandidate> pendingCandidates;
  final List<ValidatedConversationReference> validatedHistory;
  final List<ConversationReferenceCandidate> lifeContextCandidates;
}

final class ConversationReferenceResolver {
  static const int maximumCandidates =
      ConversationReferenceResolution.maximumCandidateIds;

  const ConversationReferenceResolver();

  ConversationReferenceResolution fromIdentityApplication({
    required IdentityApplicationResult application,
    required ConversationReferenceType referenceType,
    required ConversationReferenceSource source,
    EntityType? expectedType,
  }) {
    final entityType = _conversationType(
      application.resolvedEntity?.type ??
          application.candidates.firstOrNull?.entity.type ??
          expectedType,
    );
    if (entityType == null) {
      return ConversationReferenceResolution(
        status: ConversationReferenceResolutionStatus.unsupported,
        referenceType: referenceType,
        entityType: ConversationReferenceEntityType.person,
        source: source,
        reasonCode: ConversationReferenceReasonCode.unsupportedEntityType,
      );
    }
    final candidateIds = application.candidates
        .map((candidate) => candidate.entity.id)
        .where(EntityIdentity.isValid)
        .take(maximumCandidates)
        .toList(growable: false);
    return switch (application.status) {
      IdentityApplicationStatus.resolved => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.resolved,
          referenceType: referenceType,
          entityType: entityType,
          entityId: application.resolvedEntity!.id,
          source: source,
          reasonCode: source == ConversationReferenceSource.pendingAction
              ? ConversationReferenceReasonCode.resolvedByPendingAction
              : ConversationReferenceReasonCode.resolvedByExplicitMention,
        ),
      IdentityApplicationStatus.ambiguous => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.ambiguous,
          referenceType: referenceType,
          entityType: entityType,
          candidateIds: candidateIds,
          source: source,
          reasonCode:
              ConversationReferenceReasonCode.multipleExplicitCandidates,
        ),
      IdentityApplicationStatus.needsConfirmation =>
        ConversationReferenceResolution(
          status: candidateIds.length > 1
              ? ConversationReferenceResolutionStatus.ambiguous
              : ConversationReferenceResolutionStatus.unresolved,
          referenceType: referenceType,
          entityType: entityType,
          candidateIds: candidateIds.length > 1 ? candidateIds : const [],
          source: source,
          reasonCode: candidateIds.length > 1
              ? ConversationReferenceReasonCode.multipleExplicitCandidates
              : ConversationReferenceReasonCode.entityNotLocallyVerified,
        ),
      IdentityApplicationStatus.notFound => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.unresolved,
          referenceType: referenceType,
          entityType: entityType,
          source: source,
          reasonCode: ConversationReferenceReasonCode.explicitMentionNotFound,
        ),
      IdentityApplicationStatus.invalid ||
      IdentityApplicationStatus.repositoryFailure =>
        ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.unresolved,
          referenceType: referenceType,
          entityType: entityType,
          source: source,
          reasonCode: ConversationReferenceReasonCode.entityNotLocallyVerified,
        ),
    };
  }

  ConversationReferenceResolution fromEventSelection({
    required EventTargetSelectionResult selection,
    required String accountScopeId,
    required ConversationReferenceType referenceType,
    ConversationReferenceSource source =
        ConversationReferenceSource.currentMessage,
  }) {
    final candidates = selection.candidates
        .where((event) => EntityIdentity.isValid(event.id))
        .map(
          (event) => ConversationReferenceCandidate(
            entityId: event.id!,
            entityType: ConversationReferenceEntityType.event,
            accountScopeId: accountScopeId,
            source: source,
          ),
        )
        .toList(growable: false);
    final selected = selection.selected;
    return switch (selection.status) {
      EventTargetSelectionStatus.selected => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.resolved,
          referenceType: referenceType,
          entityType: ConversationReferenceEntityType.event,
          entityId: selected!.id!,
          source: source,
          reasonCode: switch (source) {
            ConversationReferenceSource.pendingAction =>
              ConversationReferenceReasonCode.resolvedByPendingAction,
            ConversationReferenceSource.validatedConversationHistory =>
              ConversationReferenceReasonCode.resolvedByValidatedHistory,
            ConversationReferenceSource.lifeContext =>
              ConversationReferenceReasonCode
                  .resolvedByUniqueLifeContextRelation,
            ConversationReferenceSource.currentMessage ||
            ConversationReferenceSource.explicitEntityMention =>
              ConversationReferenceReasonCode.resolvedByExplicitMention,
          },
        ),
      EventTargetSelectionStatus.ambiguous => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.ambiguous,
          referenceType: referenceType,
          entityType: ConversationReferenceEntityType.event,
          candidateIds:
              candidates.map((candidate) => candidate.entityId).toList(),
          source: source,
          reasonCode:
              ConversationReferenceReasonCode.multipleExplicitCandidates,
        ),
      EventTargetSelectionStatus.notFound => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.unresolved,
          referenceType: referenceType,
          entityType: ConversationReferenceEntityType.event,
          source: source,
          reasonCode: ConversationReferenceReasonCode.missingAntecedent,
        ),
      EventTargetSelectionStatus.invalid => ConversationReferenceResolution(
          status: ConversationReferenceResolutionStatus.unresolved,
          referenceType: referenceType,
          entityType: ConversationReferenceEntityType.event,
          source: source,
          reasonCode: ConversationReferenceReasonCode.invalidStableId,
        ),
    };
  }

  ConversationReferenceResolution resolve(
    ConversationReferenceRequest request, {
    required DateTime referenceDate,
  }) {
    if (!request.isSupported) {
      return ConversationReferenceResolution(
        status: ConversationReferenceResolutionStatus.unsupported,
        referenceType: request.referenceType,
        entityType: request.entityType,
        source: ConversationReferenceSource.currentMessage,
        reasonCode: ConversationReferenceReasonCode.unsupportedReference,
      );
    }
    final explicit = _eligible(
      request.explicitCandidates,
      request,
    );
    if (request.hasExplicitMention) {
      return _resolveLevel(
        explicit,
        request,
        ConversationReferenceSource.explicitEntityMention,
        ConversationReferenceReasonCode.resolvedByExplicitMention,
        ConversationReferenceReasonCode.multipleExplicitCandidates,
        emptyReason: _candidateFailureReason(
          request.explicitCandidates,
          request,
          fallback: ConversationReferenceReasonCode.explicitMentionNotFound,
        ),
      );
    }

    final pending = _eligible(request.pendingCandidates, request);
    if (pending.isNotEmpty) {
      return _resolveLevel(
        pending,
        request,
        ConversationReferenceSource.pendingAction,
        ConversationReferenceReasonCode.resolvedByPendingAction,
        ConversationReferenceReasonCode.multiplePendingCandidates,
      );
    }

    final history = request.validatedHistory
        .where((item) => item.isValidAt(referenceDate))
        .where((item) => item.accountScopeId == request.accountScopeId)
        .where((item) => item.entityType == request.entityType)
        .map(
          (item) => ConversationReferenceCandidate(
            entityId: item.entityId,
            entityType: item.entityType,
            accountScopeId: item.accountScopeId,
            source: ConversationReferenceSource.validatedConversationHistory,
          ),
        )
        .toList(growable: false);
    if (history.isNotEmpty) {
      return _resolveLevel(
        history,
        request,
        ConversationReferenceSource.validatedConversationHistory,
        ConversationReferenceReasonCode.resolvedByValidatedHistory,
        ConversationReferenceReasonCode.multipleHistoryCandidates,
      );
    }

    if (request.allowLifeContextRelation) {
      final life = _eligible(request.lifeContextCandidates, request);
      if (life.isNotEmpty) {
        return _resolveLevel(
          life,
          request,
          ConversationReferenceSource.lifeContext,
          ConversationReferenceReasonCode.resolvedByUniqueLifeContextRelation,
          ConversationReferenceReasonCode.multipleLifeContextCandidates,
        );
      }
    }

    final allCandidates = [
      ...request.explicitCandidates,
      ...request.pendingCandidates,
      ...request.lifeContextCandidates,
    ];
    if (request.backendProposedEntityId != null &&
        !allCandidates.any(
          (candidate) =>
              candidate.entityId == request.backendProposedEntityId &&
              candidate.accountScopeId == request.accountScopeId &&
              candidate.entityType == request.entityType &&
              candidate.isActive &&
              candidate.isLocallyVerified,
        )) {
      return _unresolved(
        request,
        ConversationReferenceReasonCode.entityNotLocallyVerified,
      );
    }
    final hasStaleHistory = request.validatedHistory.any(
      (item) =>
          item.entityType == request.entityType &&
          item.accountScopeId == request.accountScopeId &&
          !item.isValidAt(referenceDate),
    );
    return _unresolved(
      request,
      hasStaleHistory
          ? ConversationReferenceReasonCode.staleOrUnvalidatedHistory
          : ConversationReferenceReasonCode.missingAntecedent,
    );
  }

  ConversationReferenceReasonCode _candidateFailureReason(
    List<ConversationReferenceCandidate> values,
    ConversationReferenceRequest request, {
    required ConversationReferenceReasonCode fallback,
  }) {
    if (values.any(
      (candidate) => candidate.accountScopeId != request.accountScopeId,
    )) {
      return ConversationReferenceReasonCode.accountScopeMismatch;
    }
    if (values.any((candidate) => !candidate.isActive)) {
      return ConversationReferenceReasonCode.inactiveOrDeletedEntity;
    }
    if (values.any((candidate) => !candidate.isLocallyVerified)) {
      return ConversationReferenceReasonCode.entityNotLocallyVerified;
    }
    return fallback;
  }

  List<ConversationReferenceCandidate> _eligible(
    List<ConversationReferenceCandidate> values,
    ConversationReferenceRequest request,
  ) {
    final candidates = <String, ConversationReferenceCandidate>{};
    for (final candidate in values) {
      if (candidate.accountScopeId != request.accountScopeId ||
          candidate.entityType != request.entityType ||
          !candidate.isActive ||
          !candidate.isLocallyVerified) {
        continue;
      }
      final backendId = request.backendProposedEntityId;
      if (backendId != null && candidate.entityId != backendId) continue;
      candidates[candidate.entityId] = candidate;
    }
    return candidates.values.take(maximumCandidates).toList(growable: false)
      ..sort((first, second) => first.entityId.compareTo(second.entityId));
  }

  ConversationReferenceResolution _resolveLevel(
    List<ConversationReferenceCandidate> candidates,
    ConversationReferenceRequest request,
    ConversationReferenceSource source,
    ConversationReferenceReasonCode resolvedReason,
    ConversationReferenceReasonCode ambiguousReason, {
    ConversationReferenceReasonCode? emptyReason,
  }) {
    if (candidates.length == 1) {
      return ConversationReferenceResolution(
        status: ConversationReferenceResolutionStatus.resolved,
        referenceType: request.referenceType,
        entityType: request.entityType,
        entityId: candidates.single.entityId,
        source: source,
        reasonCode: resolvedReason,
      );
    }
    if (candidates.length > 1) {
      return ConversationReferenceResolution(
        status: ConversationReferenceResolutionStatus.ambiguous,
        referenceType: request.referenceType,
        entityType: request.entityType,
        candidateIds:
            candidates.map((candidate) => candidate.entityId).toList(),
        source: source,
        reasonCode: ambiguousReason,
      );
    }
    return _unresolved(
      request,
      emptyReason ?? ConversationReferenceReasonCode.missingAntecedent,
      source: source,
    );
  }

  ConversationReferenceResolution _unresolved(
    ConversationReferenceRequest request,
    ConversationReferenceReasonCode reason, {
    ConversationReferenceSource source =
        ConversationReferenceSource.currentMessage,
  }) =>
      ConversationReferenceResolution(
        status: ConversationReferenceResolutionStatus.unresolved,
        referenceType: request.referenceType,
        entityType: request.entityType,
        source: source,
        reasonCode: reason,
      );

  static ConversationReferenceEntityType? _conversationType(EntityType? type) {
    return switch (type) {
      EntityType.person => ConversationReferenceEntityType.person,
      EntityType.household => ConversationReferenceEntityType.household,
      EntityType.place => ConversationReferenceEntityType.structuredPlace,
      _ => null,
    };
  }
}
