import 'dart:async';

import '../models/chat_backend_request.dart';
import '../models/conversation_context_envelope.dart';
import '../models/event_model.dart';
import '../models/life_context/life_context_projection.dart';
import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_policy.dart';
import '../models/memory_evidence.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'memory_pipeline_service.dart';
import 'life_context/life_context_engine.dart';
import 'life_context/life_context_projection_engine.dart';
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
    String? resolvedSubjectEntityId,
  });

  Future<MemoryConfirmationRequest?> proposeResponseMemory(dynamic memory);
}

class DefaultConversationContextProvider
    implements ConversationContextProvider, MemoryConversationContextProvider {
  final ConversationProjectionLoader? _loadProjection;
  final ConversationAccountScopeLoader _loadAccountScope;
  final MemoryLifecycleEngine _memoryLifecycleEngine;
  final MemoryProposalFactory _memoryProposalFactory;
  final MemoryLifecycleRepository? _memoryLifecycleRepository;
  final MemoryPolicyEngine _memoryPolicyEngine;
  final MemoryEvidenceClassifier _memoryEvidenceClassifier;
  final ConversationMemoryPolicyLoader? _loadMemoryPolicy;

  const DefaultConversationContextProvider({
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
    final engine = await LifeContextProductionFactory.create();
    final snapshot = await engine.buildCanonicalSnapshot(
      accountScopeId: scope,
    );
    return LifeContextProjectionEngine().build(
      snapshot: snapshot,
      contract: LifeContextConsumerContract.forPurpose(
        LifeContextConsumerPurpose.conversation,
      ),
    );
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
    String? resolvedSubjectEntityId,
  }) async {
    if (!MemoryPipelineService.shouldProcessMemory(message)) return null;
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
        evidenceQualification: evidenceQualification);
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
        evidenceQualification: _memoryEvidenceClassifier.assistantCandidate());
  }

  Future<MemoryConfirmationRequest?> _proposeMemory(
    Map<String, dynamic> payload, {
    required String source,
    required MemoryEvidenceQualification evidenceQualification,
  }) async {
    try {
      final repository = memoryLifecycleRepository;
      final proposalId = await repository.allocateProposalId();
      if (proposalId == null || proposalId.isEmpty) return null;
      final proposedAt = DateTime.now();
      final proposal = _memoryProposalFactory.fromHistoricalPayload(
        id: proposalId,
        payload: payload,
        source: source,
        proposedAt: proposedAt,
        confirmationRequired: true,
        evidenceQualification: evidenceQualification,
      );
      if (proposal == null) return null;
      final existing = await repository.findCandidates(proposal);
      final policy = await _policy();
      final isHealth = _isExplicitHealthCategory(proposal.category);
      final policyDecision = _memoryPolicyEngine.evaluate(
        policy: policy,
        input: MemoryPolicyProposal(
          proposal: proposal,
          sensitivity: proposal.sensitivity == LifeContextSensitivity.sensitive
              ? MemoryProposalSensitivity.sensitive
              : MemoryProposalSensitivity.ordinary,
          isExplicitHealth: isHealth,
          hasExplicitUserEvidence:
              evidenceQualification.canConfirmImmediately &&
                  evidenceQualification.hasAttributableSubject,
          isDuplicate: existing.any(
            (item) =>
                item.semanticType == proposal.semanticType &&
                item.category.trim().toLowerCase() ==
                    proposal.category.trim().toLowerCase() &&
                item.normalizedText == proposal.normalizedText,
          ),
          structuredDomain: _structuredOwner(proposal.semanticType),
        ),
      );
      if (policyDecision.type == MemoryPolicyDecisionType.paused ||
          policyDecision.type.name.startsWith('reject')) {
        return null;
      }
      final decision = _memoryLifecycleEngine.evaluateProposal(
        proposal: proposal,
        existingMemories: existing,
        referenceDate: proposedAt,
      );
      if (decision.type ==
          MemoryLifecycleDecisionType.confirmExistingProposal) {
        return decision.confirmationRequest;
      }
      if (decision.type != MemoryLifecycleDecisionType.createProposal ||
          decision.mutations.isEmpty) {
        return null;
      }
      await repository.createProposal(proposal, decision.mutations.single);
      if (policyDecision.type == MemoryPolicyDecisionType.saveAutomatically) {
        await _activateAutomatically(repository, proposal, proposedAt);
        return null;
      }
      return decision.confirmationRequest;
    } catch (_) {
      AppDiagnostics.record(
        component: 'conversation_memory',
        step: 'proposal_persistence',
        code: AppErrorCode.storageFailure,
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

  Future<void> _activateAutomatically(
    MemoryLifecycleRepository repository,
    MemoryProposal proposal,
    DateTime referenceDate,
  ) async {
    var fact = _factFromProposal(proposal, MemoryLifecycleState.proposed);
    final confirmed = _memoryLifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.confirm,
        referenceDate: referenceDate,
        actor: MemoryLifecycleActor.system,
        source: 'memory_policy_v1',
        target: fact,
      ),
    );
    if (!confirmed.hasMutations) return;
    fact = _factFromProposal(proposal, MemoryLifecycleState.confirmed);
    final active = _memoryLifecycleEngine.evaluate(
      MemoryLifecycleCommand(
        action: MemoryLifecycleAction.activate,
        referenceDate: referenceDate,
        actor: MemoryLifecycleActor.system,
        source: 'memory_policy_v1',
        target: fact,
      ),
    );
    if (!active.hasMutations) return;
    await repository.applyMutations([
      ...confirmed.mutations,
      ...active.mutations,
    ]);
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
