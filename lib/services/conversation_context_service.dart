import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import '../models/chat_backend_request.dart';
import '../models/conversation_context_envelope.dart';
import '../models/event_model.dart';
import '../models/life_context/life_context_projection.dart';
import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_contradiction.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_policy.dart';
import '../models/memory_evidence.dart';
import '../models/memory_semantic_identity.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'memory_pipeline_service.dart';
import 'life_context/life_context_engine.dart';
import 'life_context_production_factory.dart';
import 'memory_lifecycle_engine.dart';
import 'memory_lifecycle_repository.dart';
import 'ledgered_memory_lifecycle_repository.dart';
import 'action_ledger_service.dart';
import 'action_autonomy_policy_service.dart';
import 'memory_policy_engine.dart';
import 'memory_policy_service.dart';
import 'memory_proposal_factory.dart';
import 'memory_evidence_classifier.dart';
import 'conversation_context_assembler.dart';

typedef ConversationMemoryPolicyLoader = Future<MemoryPolicy> Function();
typedef ConversationMemoryLoader = Future<List<Map<String, dynamic>>>
    Function();
typedef ConversationEventLoader = Future<List<EventModel>> Function();
typedef ConversationProjectionLoader = Future<LifeContextProjection> Function(
  String accountScopeId,
);
typedef ConversationAccountScopeLoader = Future<String> Function();

abstract class ConversationContextProvider {
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  });

  Future<void> saveResponseMemory(dynamic memory);
}

abstract interface class MemoryConversationContextProvider {
  MemoryLifecycleRepository get memoryLifecycleRepository;

  Future<MemoryConfirmationRequest?> proposeUserMemory(
    String message, {
    String? logicalRequestId,
    String? resolvedSubjectEntityId,
    MemorySemanticSubjectScope? semanticSubjectScope,
    MemorySemanticContextType? semanticContextType,
    String? semanticContextEntityId,
  });

  Future<MemoryConfirmationRequest?> proposeResponseMemory(dynamic memory);
}

abstract interface class MemoryConversationAttemptStatusProvider {
  bool get lastMemoryProposalWasAttempted;
  bool get lastMemoryProposalWasPersistedOrPending;
  bool get lastMemoryProposalWasActivated;
}

abstract interface class PriorityConversationContextProvider {
  Future<LifeContextProjection> loadPriorityProjection();
}

class DefaultConversationContextProvider
    implements
        ConversationContextProvider,
        MemoryConversationContextProvider,
        MemoryConversationAttemptStatusProvider,
        PriorityConversationContextProvider {
  final ConversationProjectionLoader? _loadProjection;
  final ConversationAccountScopeLoader _loadAccountScope;
  final MemoryLifecycleEngine _memoryLifecycleEngine;
  final MemoryProposalFactory _memoryProposalFactory;
  final MemoryLifecycleRepository? _memoryLifecycleRepository;
  final MemoryPolicyEngine _memoryPolicyEngine;
  final MemoryEvidenceClassifier _memoryEvidenceClassifier;
  final ConversationMemoryPolicyLoader? _loadMemoryPolicy;

  DefaultConversationContextProvider({
    ConversationProjectionLoader? loadProjection,
    ConversationAccountScopeLoader loadAccountScope =
        AuthService.ensureAuthenticatedUid,
    @Deprecated('Use loadProjection') ConversationMemoryLoader? loadMemories,
    @Deprecated('Use loadProjection') ConversationEventLoader? loadEvents,
    MemoryLifecycleEngine memoryLifecycleEngine = const MemoryLifecycleEngine(),
    MemoryProposalFactory memoryProposalFactory = const MemoryProposalFactory(),
    MemoryLifecycleRepository? memoryLifecycleRepository,
    MemoryPolicyEngine memoryPolicyEngine = const MemoryPolicyEngine(),
    MemoryEvidenceClassifier memoryEvidenceClassifier =
        const MemoryEvidenceClassifier(),
    ConversationMemoryPolicyLoader? loadMemoryPolicy,
  })  : _loadProjection = loadProjection,
        _loadAccountScope = loadAccountScope,
        _memoryLifecycleEngine = memoryLifecycleEngine,
        _memoryProposalFactory = memoryProposalFactory,
        _memoryLifecycleRepository = memoryLifecycleRepository,
        _memoryPolicyEngine = memoryPolicyEngine,
        _memoryEvidenceClassifier = memoryEvidenceClassifier,
        _loadMemoryPolicy = loadMemoryPolicy;

  bool _lastMemoryProposalWasAttempted = false;
  bool _lastMemoryProposalWasPersistedOrPending = false;
  bool _lastMemoryProposalWasActivated = false;

  @override
  bool get lastMemoryProposalWasAttempted => _lastMemoryProposalWasAttempted;

  @override
  bool get lastMemoryProposalWasPersistedOrPending =>
      _lastMemoryProposalWasPersistedOrPending;

  @override
  bool get lastMemoryProposalWasActivated => _lastMemoryProposalWasActivated;

  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    final now = DateTime.now().toUtc();
    ConversationContextEnvelope envelope;
    try {
      final scope = await _loadAccountScope();
      final projection = await (_loadProjection ?? _loadCanonicalProjection)(
        scope,
      ).timeout(ConversationTransportContract.contextTimeout);
      if (projection.accountScopeId != scope) {
        throw const LifeContextProjectionException(
          'conversation_projection_account_mismatch',
        );
      }
      envelope = ConversationContextAssembler.assemble(projection);
    } on TimeoutException {
      envelope = ConversationContextEnvelope.unavailable(
        state: ConversationContextState.timeout,
        generatedAt: now,
        warningCode: 'context_timeout',
      );
    } on LifeContextEngineException catch (error) {
      envelope = ConversationContextEnvelope.unavailable(
        state: switch (error.code) {
          'unauthenticated' => ConversationContextState.unauthenticated,
          'account_mismatch' => ConversationContextState.accountMismatch,
          'cancelled' => ConversationContextState.cancelled,
          _ => ConversationContextState.unavailable,
        },
        generatedAt: now,
        warningCode: error.code,
      );
    } on LifeContextProjectionException catch (error) {
      envelope = ConversationContextEnvelope.unavailable(
        state: error.code.contains('account_mismatch')
            ? ConversationContextState.accountMismatch
            : ConversationContextState.invalidProjection,
        generatedAt: now,
        warningCode: error.code,
      );
    } on FormatException {
      envelope = ConversationContextEnvelope.unavailable(
        state: ConversationContextState.invalidProjection,
        generatedAt: now,
        warningCode: 'invalid_projection',
      );
    } on Object {
      envelope = ConversationContextEnvelope.unavailable(
        state: ConversationContextState.unknownFailure,
        generatedAt: now,
        warningCode: 'context_unavailable',
      );
    }
    return ChatBackendRequest(
      message: message,
      context: envelope,
    );
  }

  static Future<LifeContextProjection> _loadCanonicalProjection(
    String scope,
  ) async {
    final production = await LifeContextProductionFactory.production();
    production.handleAccountScopeChanged(scope);
    return production.getCurrentProjection(
      LifeContextConsumerPurpose.conversation,
    );
  }

  @override
  Future<LifeContextProjection> loadPriorityProjection() async {
    final scope = await _loadAccountScope();
    final projection = await (_loadProjection != null
            ? _loadProjection(scope)
            : () async {
                final production =
                    await LifeContextProductionFactory.production();
                production.handleAccountScopeChanged(scope);
                return production.getCurrentProjection(
                  LifeContextConsumerPurpose.proactivePriority,
                );
              }())
        .timeout(ConversationTransportContract.contextTimeout);
    if (projection.accountScopeId != scope) {
      throw const LifeContextProjectionException(
        'priority_projection_account_mismatch',
      );
    }
    return projection;
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {
    await proposeResponseMemory(memory);
  }

  @override
  MemoryLifecycleRepository get memoryLifecycleRepository {
    final injected = _memoryLifecycleRepository;
    if (injected != null) return injected;
    return LedgeredMemoryLifecycleRepository(
      delegate: FirestoreMemoryLifecycleRepository(),
      ledger: ActionLedgerService.production(),
      loadAutonomyPolicy: () async {
        final service = await ActionAutonomyPolicyService.local(
          currentAccountScopeId: () => AuthService.currentUserId,
        );
        return service.load();
      },
      loadMemoryPolicy: _policy,
    );
  }

  @override
  Future<MemoryConfirmationRequest?> proposeUserMemory(
    String message, {
    String? logicalRequestId,
    String? resolvedSubjectEntityId,
    MemorySemanticSubjectScope? semanticSubjectScope,
    MemorySemanticContextType? semanticContextType,
    String? semanticContextEntityId,
  }) async {
    _lastMemoryProposalWasAttempted =
        MemoryPipelineService.shouldProcessMemory(message);
    _lastMemoryProposalWasPersistedOrPending = false;
    _lastMemoryProposalWasActivated = false;
    if (!_lastMemoryProposalWasAttempted) return null;
    final evidenceQualification = _memoryEvidenceClassifier.classify(
      message,
      resolvedSubjectEntityId: resolvedSubjectEntityId,
    );
    final statement =
        evidenceQualification.statementForMemory?.trim().isNotEmpty == true
            ? evidenceQualification.statementForMemory!
            : message;
    final memory = MemoryPipelineService.buildMemory(statement);
    final payload = MemoryPipelineService.buildSavePayload(
      memory,
      fallbackText: statement,
    );
    return _proposeMemory({
      'text': payload.text,
      'category': payload.category,
      'importance': payload.importance,
    },
        source: 'explicit_user_message',
        explicitMemoryRequest:
            MemoryPipelineService.hasExplicitMemoryRequest(message),
        evidenceQualification: evidenceQualification,
        semanticSubjectScope: semanticSubjectScope,
        semanticSubjectEntityId: resolvedSubjectEntityId,
        semanticContextType: semanticContextType,
        semanticContextEntityId: semanticContextEntityId,
        logicalRequestId: logicalRequestId);
  }

  @override
  Future<MemoryConfirmationRequest?> proposeResponseMemory(
      dynamic memory) async {
    if (memory is! Map) return null;

    final text = memory['text']?.toString() ?? '';
    if (text.trim().isEmpty) return null;
    if (!MemoryPipelineService.shouldProcessMemory(text)) return null;

    final builtMemory = MemoryPipelineService.buildMemory(text);
    final payload = MemoryPipelineService.buildSavePayload(
      builtMemory,
      fallbackText: text,
    );

    return _proposeMemory({
      'text': payload.text,
      'category': payload.category,
      'importance': payload.importance,
    },
        source: 'assistant_memory_candidate',
        explicitMemoryRequest: false,
        evidenceQualification: _memoryEvidenceClassifier.assistantCandidate());
  }

  Future<MemoryConfirmationRequest?> _proposeMemory(
    Map<String, dynamic> payload, {
    required String source,
    required bool explicitMemoryRequest,
    required MemoryEvidenceQualification evidenceQualification,
    MemorySemanticSubjectScope? semanticSubjectScope,
    String? semanticSubjectEntityId,
    MemorySemanticContextType? semanticContextType,
    String? semanticContextEntityId,
    String? logicalRequestId,
  }) async {
    var persistenceStep = 'initialization';
    try {
      final repository = memoryLifecycleRepository;
      persistenceStep = 'policy_load';
      final policy = await _policy();
      final accountScopeId = policy.accountScopeId;
      persistenceStep = 'proposal_id_allocation';
      final proposalId = await repository.allocateProposalId();
      if (proposalId == null || proposalId.isEmpty) return null;
      final proposedAt = DateTime.now();
      var proposal = _memoryProposalFactory.fromHistoricalPayload(
        id: proposalId,
        payload: payload,
        source: source,
        proposedAt: proposedAt,
        confirmationRequired: true,
        evidenceQualification: evidenceQualification,
        semanticSubjectScope: semanticSubjectScope,
        semanticSubjectEntityId: semanticSubjectEntityId,
        semanticContextType: semanticContextType,
        semanticContextEntityId: semanticContextEntityId,
      );
      if (proposal == null) return null;
      final effectiveLogicalRequestId =
          logicalRequestId?.trim().isNotEmpty == true
              ? logicalRequestId!.trim()
              : proposalId;
      final identity = proposal.semanticIdentity;
      if (identity != null &&
          identity.eligibleForAutomaticContradiction &&
          proposal.semanticValue?.trim().isNotEmpty == true) {
        final accountFingerprint = sha256
            .convert(
              utf8.encode(
                'zelia-memory-proposal-account-v1|$accountScopeId',
              ),
            )
            .toString();
        final stableId = sha256
            .convert(
              utf8.encode(
                'zelia-memory-proposal-v1|$accountFingerprint|'
                '${sha256.convert(utf8.encode('zelia-memory-logical-request-v1|$effectiveLogicalRequestId'))}',
              ),
            )
            .toString();
        proposal = _memoryProposalFactory.fromHistoricalPayload(
          id: stableId,
          payload: payload,
          source: source,
          proposedAt: proposedAt,
          confirmationRequired: true,
          evidenceQualification: evidenceQualification,
          semanticSubjectScope: semanticSubjectScope,
          semanticSubjectEntityId: semanticSubjectEntityId,
          semanticContextType: semanticContextType,
          semanticContextEntityId: semanticContextEntityId,
        );
        if (proposal == null) return null;
      }
      final effectiveProposal = proposal;
      persistenceStep = 'candidate_lookup';
      final existing = await repository.findCandidates(effectiveProposal);
      final isHealth = _isExplicitHealthCategory(effectiveProposal.category);
      final policyDecision = _memoryPolicyEngine.evaluate(
        policy: policy,
        input: MemoryPolicyProposal(
          proposal: effectiveProposal,
          sensitivity:
              effectiveProposal.sensitivity == LifeContextSensitivity.sensitive
                  ? MemoryProposalSensitivity.sensitive
                  : MemoryProposalSensitivity.ordinary,
          isExplicitHealth: isHealth,
          hasExplicitUserEvidence:
              evidenceQualification.canConfirmImmediately &&
                  evidenceQualification.hasAttributableSubject,
          hasExplicitSaveDirective: explicitMemoryRequest,
          isDuplicate: existing.any(
            (item) =>
                item.semanticType == effectiveProposal.semanticType &&
                item.category.trim().toLowerCase() ==
                    effectiveProposal.category.trim().toLowerCase() &&
                item.normalizedText == effectiveProposal.normalizedText,
          ),
          structuredDomain: _structuredOwner(effectiveProposal.semanticType),
        ),
      );
      if (policyDecision.type == MemoryPolicyDecisionType.paused ||
          (policyDecision.type.name.startsWith('reject') &&
              policyDecision.type !=
                  MemoryPolicyDecisionType.rejectDuplicate)) {
        return null;
      }
      final decision = _memoryLifecycleEngine.evaluateProposal(
        proposal: effectiveProposal,
        existingMemories: existing,
        referenceDate: proposedAt,
        accountScopeId: accountScopeId,
      );
      if (decision.type ==
          MemoryLifecycleDecisionType.confirmExistingProposal) {
        _lastMemoryProposalWasPersistedOrPending = true;
        return decision.confirmationRequest;
      }
      if (decision.type == MemoryLifecycleDecisionType.noChange &&
          decision.memoryIds.isNotEmpty) {
        LifeMemoryFact? existingDuplicate;
        for (final candidate in existing) {
          if (decision.memoryIds.contains(candidate.id)) {
            existingDuplicate = candidate;
            break;
          }
        }
        if (existingDuplicate != null) {
          _lastMemoryProposalWasPersistedOrPending = true;
          _lastMemoryProposalWasActivated =
              existingDuplicate.lifecycleState == MemoryLifecycleState.active;
          return null;
        }
      }
      if ((decision.type != MemoryLifecycleDecisionType.createProposal &&
              decision.contradictionMatch == null) ||
          decision.mutations.isEmpty) {
        return null;
      }
      final proposalMutation = decision.mutations.single;
      final contradictionMatch = decision.contradictionMatch;
      if (contradictionMatch != null) {
        final replacementRepository = repository;
        if (replacementRepository is! MemoryReplacementPendingRepository) {
          return null;
        }
        persistenceStep = 'replacement_proposal_write';
        final persisted =
            await (replacementRepository as MemoryReplacementPendingRepository)
                .persistReplacementProposal(
          proposal: effectiveProposal,
          mutation: proposalMutation,
          match: contradictionMatch,
          accountScopeId: accountScopeId,
          logicalRequestId: effectiveLogicalRequestId,
          createdAt: proposedAt,
        );
        if (persisted == null ||
            persisted.action.state != MemoryReplacementActionState.pending) {
          return null;
        }
        _lastMemoryProposalWasPersistedOrPending = true;
        final request = decision.confirmationRequest;
        if (request == null) return null;
        return MemoryConfirmationRequest(
          action: request.action,
          proposalId: request.proposalId,
          memoryId: request.memoryId,
          prompt: request.prompt,
          changeType: request.changeType,
          sensitivity: request.sensitivity,
          consequence: request.consequence,
          contradictionCandidate: persisted.candidate,
          replacementPendingAction: persisted.action,
        );
      }
      if (policyDecision.type == MemoryPolicyDecisionType.saveAutomatically) {
        final activationMutations = _automaticActivationMutations(
          effectiveProposal,
          proposedAt,
          actor: explicitMemoryRequest
              ? MemoryLifecycleActor.user
              : MemoryLifecycleActor.system,
          source: explicitMemoryRequest
              ? 'explicit_user_memory_directive'
              : 'memory_policy_v1',
        );
        if (activationMutations != null &&
            repository is MemoryLifecycleDirectActivationRepository) {
          persistenceStep = 'direct_activation_write';
          await (repository as MemoryLifecycleDirectActivationRepository)
              .createActiveMemory(
            effectiveProposal,
            proposalMutation,
            activationMutations,
          );
          _lastMemoryProposalWasPersistedOrPending = true;
          _lastMemoryProposalWasActivated = true;
          return null;
        }
      }
      persistenceStep = 'proposal_write';
      await repository.createProposal(effectiveProposal, proposalMutation);
      _lastMemoryProposalWasPersistedOrPending = true;
      if (policyDecision.type == MemoryPolicyDecisionType.saveAutomatically) {
        persistenceStep = 'activation_write';
        final activated = await _activateAutomatically(
          repository,
          effectiveProposal,
          proposedAt,
          actor: explicitMemoryRequest
              ? MemoryLifecycleActor.user
              : MemoryLifecycleActor.system,
          source: explicitMemoryRequest
              ? 'explicit_user_memory_directive'
              : 'memory_policy_v1',
        );
        if (!activated) return decision.confirmationRequest;
        _lastMemoryProposalWasActivated = true;
        return null;
      }
      return decision.confirmationRequest;
    } catch (error) {
      AppDiagnostics.record(
        component: 'conversation_memory',
        step: persistenceStep,
        code: AppErrorCode.storageFailure,
        sourceExceptionType: error.runtimeType.toString(),
        technicalStatus:
            error is FormatException ? error.message.toString() : null,
      );
      return null;
    }
  }

  Future<MemoryPolicy> _policy() async {
    if (_loadMemoryPolicy != null) return _loadMemoryPolicy();
    final service = await MemoryPolicyService.local(
      currentAccountScopeId: () => AuthService.currentUserId,
    );
    return service.load();
  }

  Future<bool> _activateAutomatically(
    MemoryLifecycleRepository repository,
    MemoryProposal proposal,
    DateTime referenceDate, {
    required MemoryLifecycleActor actor,
    required String source,
  }) async {
    final mutations = _automaticActivationMutations(
      proposal,
      referenceDate,
      actor: actor,
      source: source,
    );
    if (mutations == null) return false;
    await repository.applyMutations(mutations);
    return true;
  }

  List<MemoryLifecycleMutation>? _automaticActivationMutations(
    MemoryProposal proposal,
    DateTime referenceDate, {
    required MemoryLifecycleActor actor,
    required String source,
  }) {
    var fact = _factFromProposal(proposal, MemoryLifecycleState.proposed);
    final confirmed = _memoryLifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.confirm,
        referenceDate: referenceDate,
        actor: actor,
        source: source,
        target: fact,
      ),
    );
    if (!confirmed.hasMutations) return null;
    fact = _factFromProposal(proposal, MemoryLifecycleState.confirmed);
    final active = _memoryLifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.activate,
        referenceDate: referenceDate,
        actor: actor,
        source: source,
        target: fact,
      ),
    );
    if (!active.hasMutations) return null;
    return [
      ...confirmed.mutations,
      ...active.mutations,
    ];
  }

  LifeMemoryFact _factFromProposal(
    MemoryProposal proposal,
    MemoryLifecycleState state,
  ) =>
      LifeMemoryFact(
        id: proposal.id,
        text: proposal.text,
        normalizedText: proposal.normalizedText,
        semanticType: proposal.semanticType,
        category: proposal.category,
        importance: proposal.importance,
        sourceType: LifeContextSourceType.memory,
        sourceId: proposal.source,
        createdAt: proposal.proposedAt,
        validFrom: proposal.validFrom,
        validUntil: proposal.validUntil,
        confirmationStatus: state == MemoryLifecycleState.confirmed
            ? MemoryConfirmationStatus.confirmed
            : MemoryConfirmationStatus.unconfirmed,
        sensitivity: proposal.sensitivity,
        evidenceType: LifeContextEvidenceType.explicit,
        lifecycleState: state,
        lifecycleStateIsExplicit: true,
        confidence: proposal.confidence,
      );

  bool _isExplicitHealthCategory(String category) {
    final value = category.trim().toLowerCase();
    return value == 'health' || value == 'medical' || value == 'sante';
  }

  String? _structuredOwner(LifeMemorySemanticType type) => switch (type) {
        LifeMemorySemanticType.routine => 'routine',
        LifeMemorySemanticType.relationship => 'human',
        _ => null,
      };
}
