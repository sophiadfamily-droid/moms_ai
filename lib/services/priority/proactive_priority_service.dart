import 'package:shared_preferences/shared_preferences.dart';

import '../../models/life_context/life_context_domains.dart';
import '../../models/life_context/life_context_projection.dart';
import '../../models/priority/proactive_priority_models.dart';
import '../../models/priority/priority_models.dart';
import '../../models/priority/priority_suggestion_models.dart';
import '../../models/conversation_models.dart';
import '../../models/reasoning/reasoning_input.dart';
import '../../models/reasoning/reasoning_result.dart';
import '../app_diagnostics.dart';
import 'priority_candidate_adapter.dart';
import 'priority_engine.dart';
import 'priority_suggestion_builder.dart';
import 'priority_suggestion_conversation_context.dart';
import 'proactive_suggestion_history_repository.dart';
import 'proactive_suggestion_policy.dart';
import '../reasoning/reasoning_application_service.dart';

typedef ProactivePriorityProjectionLoader = Future<LifeContextProjection>
    Function();
typedef ProactiveReasoningLoader = Future<ReasoningResult> Function(
  int sessionGeneration,
);

final class ProactivePriorityService {
  static const _buildMarker = String.fromEnvironment(
    'ZELIA_BUILD_MARKER',
    defaultValue: 'unset',
  );

  ProactivePriorityService({
    required this.accountScopeId,
    required ProactivePriorityProjectionLoader loadProjection,
    required ProactiveSuggestionHistoryRepository history,
    DateTime Function()? clock,
    ProactiveSuggestionPolicy policy = const ProactiveSuggestionPolicy(),
    ProactiveReasoningLoader? loadReasoning,
  })  : _loadProjection = loadProjection,
        _history = history,
        _clock = clock ?? DateTime.now,
        _policy = policy,
        _loadReasoning = loadReasoning;

  final String accountScopeId;
  final ProactivePriorityProjectionLoader _loadProjection;
  final ProactiveSuggestionHistoryRepository _history;
  final DateTime Function() _clock;
  final ProactiveSuggestionPolicy _policy;
  final ProactiveReasoningLoader? _loadReasoning;
  bool _presentedThisSession = false;
  bool _blockedThisSession = false;
  String? _pendingPresentationId;
  ProactiveSuggestion? _visibleSuggestion;
  int _evaluationGeneration = 0;
  ProactiveEvaluationSnapshot? lastEvaluationSnapshot;
  ProactiveSuggestion? get currentVisibleSuggestion => _visibleSuggestion;
  String? get currentVisibleFingerprint =>
      _visibleSuggestion?.materialFingerprint;
  bool get presentationConfirmed => _visibleSuggestion != null;

  @Deprecated('Use currentVisibleSuggestion.')
  ProactiveSuggestion? get visibleSuggestion => currentVisibleSuggestion;

  static Future<ProactivePriorityService> create({
    required String accountScopeId,
    required ProactivePriorityProjectionLoader loadProjection,
    DateTime Function()? clock,
  }) async =>
      ProactivePriorityService(
        accountScopeId: accountScopeId,
        loadProjection: loadProjection,
        history: SharedPreferencesProactiveSuggestionHistoryRepository(
          await SharedPreferences.getInstance(),
        ),
        clock: clock,
        loadReasoning: (sessionGeneration) =>
            ReasoningApplicationService.production().evaluate(
          accountScopeId: accountScopeId,
          purpose: ReasoningPurpose.organizeAcrossDomains,
          conversationState: const ConversationState(),
          sessionGeneration: sessionGeneration,
        ),
      );

  Future<ProactiveSuggestionDecision> evaluate({
    required bool dashboardReady,
    required bool interactionActive,
    bool onboardingActive = false,
    String registryInstanceIdentifier = 'unbound',
    List<String> activeInteractionSources = const [],
    String lastInteractionTransition = 'none',
    int interactionGeneration = 0,
  }) async {
    final started = DateTime.now();
    try {
      final projection = await _loadProjection();
      if (projection.accountScopeId != accountScopeId) {
        return const ProactiveSuggestionDecision.noSuggestion(
          'account_mismatch',
        );
      }
      final now = _clock();
      ReasoningResult? reasoning;
      if (_loadReasoning != null) {
        try {
          reasoning = await _loadReasoning(interactionGeneration);
        } on Object catch (error) {
          AppDiagnostics.record(
            component: 'proactive_priority',
            step: 'optional_reasoning',
            code: AppErrorCode.dependencyUnavailable,
            severity: AppErrorSeverity.warning,
            sourceExceptionType: error.runtimeType.toString(),
            metadata: const {
              'result': 'local_priority_preserved',
            },
          );
        }
      }
      final candidates = const PriorityCandidateAdapter().fromProjection(
        projection,
        evaluatedAt: now.toUtc(),
      );
      final ranking = PriorityEngine().rank(
        candidates,
        evaluatedAt: now.toUtc(),
        expectedAccountScopeId: accountScopeId,
      );
      final result = const PrioritySuggestionBuilder().build(
        ranking: ranking,
        accountScopeId: accountScopeId,
        referenceDate: now.toUtc(),
        limit: PrioritySuggestionLimits.proactiveEvaluation,
      );
      final presentation =
          const PrioritySuggestionConversationContextBuilder().build(result);
      final history = await _history.load(accountScopeId);
      _repairVisiblePresentationState(
        history: history,
        ranking: ranking,
        now: now,
      );
      final decision = _policy.evaluate(
        suggestions: result,
        ranking: ranking,
        projection: projection,
        presentationMessages:
            presentation.items.map((value) => value.message).toList(),
        history: history,
        localNow: now,
        dashboardReady: dashboardReady,
        interactionActive: interactionActive,
        onboardingActive: onboardingActive,
        alreadyPresentedThisSession: _presentedThisSession,
        presentationReserved: _pendingPresentationId != null,
        historyPersistenceBlocked: _blockedThisSession,
        reasoningAssessment: reasoning?.assessment,
      );
      if (decision.suggestion case final suggestion?) {
        _pendingPresentationId = suggestion.suggestionId;
      }
      final sourceRevision = ranking.items.isEmpty
          ? 'none'
          : '${ranking.items.first.candidate.sourceRevision ?? 0}';
      final relationSections = projection.sections.where(
        (section) => section.type == LifeContextProjectionSectionType.relation,
      );
      final sectionAvailabilityCodes = projection.sections
          .map((section) => '${section.type.name}:${section.availability.name}')
          .toList(growable: false);
      final blockingSections = projection.sections
          .where(
            (section) =>
                section.warningCode != null ||
                section.truncated ||
                {
                  LifeContextAvailability.unavailable,
                  LifeContextAvailability.corrupted,
                  LifeContextAvailability.unsupported,
                  LifeContextAvailability.accountMismatch,
                }.contains(section.availability),
          )
          .map((section) => section.type.name)
          .toList(growable: false);
      final relevantSuggestion = decision.suggestion ?? _visibleSuggestion;
      final preservesVisibleSuggestion =
          decision.code == 'session_quota_consumed' &&
              _visibleSuggestion != null;
      final relevantHistory = relevantSuggestion == null
          ? null
          : history
              .where(
                (receipt) =>
                    receipt.canonicalSuggestionKey ==
                    relevantSuggestion.canonicalSuggestionKey,
              )
              .firstOrNull;
      lastEvaluationSnapshot = ProactiveEvaluationSnapshot(
        buildMarker: _buildMarker,
        evaluatedAt: now,
        candidateCount: candidates.length,
        decision: decision.type.name,
        reasonCodes: [decision.code],
        interactionActive: interactionActive,
        tabActive: dashboardReady,
        historyState: relevantHistory?.state.name ?? 'none',
        sessionQuotaConsumed: _presentedThisSession,
        sourceRevision: sourceRevision,
        evaluationGeneration: ++_evaluationGeneration,
        projectionState: projection.state.name,
        relationAvailability: relationSections.isEmpty
            ? 'absent'
            : relationSections.single.availability.name,
        presentationReserved: _pendingPresentationId != null,
        presentationConfirmed: _visibleSuggestion != null,
        registryInstanceIdentifier: registryInstanceIdentifier,
        activeInteractionSources: activeInteractionSources,
        activeInteractionCount: activeInteractionSources.length,
        lastInteractionTransition: lastInteractionTransition,
        interactionGeneration: interactionGeneration,
        inputSuggestionCount: decision.inputSuggestionCount,
        evaluatedCandidateCount: decision.evaluatedCandidateCount,
        skippedShownCount: decision.skippedShownCount,
        skippedDismissedCount: decision.skippedDismissedCount,
        skippedCompletedCount: decision.skippedCompletedCount,
        skippedIneligibleCount: decision.skippedIneligibleCount,
        selectedCandidateRank: decision.selectedCandidateRank,
        terminalReasonCode: decision.code,
        blockingSections: blockingSections,
        sectionAvailabilityCodes: sectionAvailabilityCodes,
        projectionStateReasonCodes: projection.warningCodes,
        evaluationDecision: decision.code,
        renderedState: preservesVisibleSuggestion
            ? 'existing_suggestion_preserved'
            : decision.suggestion != null
                ? 'new_suggestion_reserved'
                : 'empty',
        visibleSuggestionPresent: _visibleSuggestion != null,
      );
      _diagnose(
        step: 'evaluate',
        decision: decision,
        candidateCount: candidates.length,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        snapshot: lastEvaluationSnapshot!,
      );
      return decision;
    } on Object {
      lastEvaluationSnapshot = ProactiveEvaluationSnapshot(
        buildMarker: _buildMarker,
        evaluatedAt: _clock(),
        candidateCount: 0,
        decision: ProactiveSuggestionDecisionType.noSuggestion.name,
        reasonCodes: const ['local_failure'],
        interactionActive: interactionActive,
        tabActive: dashboardReady,
        historyState: 'unknown',
        sessionQuotaConsumed: _presentedThisSession,
        sourceRevision: 'unknown',
        evaluationGeneration: ++_evaluationGeneration,
        projectionState: 'unknown',
        relationAvailability: 'unknown',
        presentationReserved: false,
        presentationConfirmed: false,
        registryInstanceIdentifier: registryInstanceIdentifier,
        activeInteractionSources: activeInteractionSources,
        activeInteractionCount: activeInteractionSources.length,
        lastInteractionTransition: lastInteractionTransition,
        interactionGeneration: interactionGeneration,
        inputSuggestionCount: 0,
        evaluatedCandidateCount: 0,
        skippedShownCount: 0,
        skippedDismissedCount: 0,
        skippedCompletedCount: 0,
        skippedIneligibleCount: 0,
        selectedCandidateRank: null,
        terminalReasonCode: 'local_failure',
        blockingSections: const ['evaluation'],
        sectionAvailabilityCodes: const [],
        projectionStateReasonCodes: const ['local_failure'],
        evaluationDecision: 'local_failure',
        renderedState: 'empty',
        visibleSuggestionPresent: false,
      );
      _diagnose(
        step: 'evaluate',
        decision:
            const ProactiveSuggestionDecision.noSuggestion('local_failure'),
        candidateCount: 0,
        durationMs: DateTime.now().difference(started).inMilliseconds,
        snapshot: lastEvaluationSnapshot!,
      );
      return const ProactiveSuggestionDecision.noSuggestion('local_failure');
    }
  }

  Future<bool> confirmShown(ProactiveSuggestion suggestion) async {
    if (_presentedThisSession &&
        _visibleSuggestion?.suggestionId == suggestion.suggestionId &&
        _visibleSuggestion?.materialFingerprint ==
            suggestion.materialFingerprint) {
      return true;
    }
    if (_pendingPresentationId != suggestion.suggestionId ||
        _presentedThisSession ||
        _blockedThisSession) {
      return false;
    }
    final now = _clock();
    final history = await _history.load(accountScopeId);
    final receipt = ProactiveSuggestionReceipt(
      suggestionId: suggestion.suggestionId,
      canonicalSuggestionKey: suggestion.canonicalSuggestionKey,
      materialFingerprint: suggestion.materialFingerprint,
      firstShownAt: now,
      lastShownAt: now,
      state: ProactiveSuggestionHistoryState.shown,
      sourceRevision: suggestion.sourceRevision,
    );
    try {
      await _history.save(
        accountScopeId,
        [
          ...history.where(
            (value) => value.suggestionId != suggestion.suggestionId,
          ),
          receipt,
        ].take(128).toList(),
      );
      _presentedThisSession = true;
      _visibleSuggestion = suggestion;
      _pendingPresentationId = null;
      lastEvaluationSnapshot = lastEvaluationSnapshot?.copyWith(
        presentationReserved: false,
        presentationConfirmed: true,
        historyState: ProactiveSuggestionHistoryState.shown.name,
        sessionQuotaConsumed: true,
        renderedState: 'existing_suggestion_preserved',
        visibleSuggestionPresent: true,
      );
      return true;
    } on Object {
      _pendingPresentationId = null;
      _blockedThisSession = true;
      lastEvaluationSnapshot = lastEvaluationSnapshot?.copyWith(
        presentationReserved: false,
        presentationConfirmed: false,
        renderedState: 'empty',
        visibleSuggestionPresent: false,
      );
      AppDiagnostics.record(
        component: 'proactive_priority',
        step: 'persist_receipt',
        code: AppErrorCode.proactivePersistenceFailure,
      );
      return false;
    }
  }

  Future<void> dismiss(ProactiveSuggestion suggestion) =>
      _updateReceipt(suggestion, ProactiveSuggestionHistoryState.dismissed);

  Future<void> markActedOn(ProactiveSuggestion suggestion) =>
      _updateReceipt(suggestion, ProactiveSuggestionHistoryState.actedOn);

  Future<void> markCompleted(ProactiveSuggestion suggestion) =>
      _updateReceipt(suggestion, ProactiveSuggestionHistoryState.completed);

  Future<void> _updateReceipt(
    ProactiveSuggestion suggestion,
    ProactiveSuggestionHistoryState state,
  ) async {
    final now = _clock();
    final history = await _history.load(accountScopeId);
    final updated = history.map((receipt) {
      if (receipt.suggestionId != suggestion.suggestionId) return receipt;
      return ProactiveSuggestionReceipt(
        suggestionId: receipt.suggestionId,
        canonicalSuggestionKey: receipt.canonicalSuggestionKey,
        materialFingerprint: receipt.materialFingerprint,
        firstShownAt: receipt.firstShownAt,
        lastShownAt: receipt.lastShownAt,
        dismissedAt:
            state == ProactiveSuggestionHistoryState.dismissed ? now : null,
        actedOnAt:
            state == ProactiveSuggestionHistoryState.actedOn ? now : null,
        state: state,
        sourceRevision: receipt.sourceRevision,
      );
    }).toList();
    try {
      await _history.save(accountScopeId, updated);
      if (state == ProactiveSuggestionHistoryState.dismissed ||
          state == ProactiveSuggestionHistoryState.actedOn ||
          state == ProactiveSuggestionHistoryState.completed ||
          state == ProactiveSuggestionHistoryState.expired ||
          state == ProactiveSuggestionHistoryState.superseded) {
        _visibleSuggestion = null;
      }
    } on Object {
      AppDiagnostics.record(
        component: 'proactive_priority',
        step: 'persist_receipt',
        code: AppErrorCode.proactivePersistenceFailure,
      );
      rethrow;
    }
  }

  void _repairVisiblePresentationState({
    required List<ProactiveSuggestionReceipt> history,
    required PriorityRanking ranking,
    required DateTime now,
  }) {
    if (!_presentedThisSession) return;
    final visible = _visibleSuggestion;
    final hasReceipt = visible != null &&
        history.any(
          (receipt) =>
              receipt.suggestionId == visible.suggestionId &&
              receipt.materialFingerprint == visible.materialFingerprint &&
              receipt.state == ProactiveSuggestionHistoryState.shown,
        );
    final sourceRevision = visible?.sourceRevision.split(':').first;
    final remainsMateriallyValid = visible != null &&
        visible.validityState == ProactiveSuggestionValidityState.valid &&
        visible.expiresAt.isAfter(now) &&
        ranking.items.any(
          (item) =>
              visible.sourceEntityReferences.contains(item.candidate.id) &&
              '${item.candidate.sourceRevision ?? 0}' == sourceRevision &&
              item.candidate.status == PriorityCandidateStatus.active,
        );
    if (hasReceipt && remainsMateriallyValid) return;
    _presentedThisSession = false;
    _visibleSuggestion = null;
  }

  void _diagnose({
    required String step,
    required ProactiveSuggestionDecision decision,
    required int candidateCount,
    required int durationMs,
    required ProactiveEvaluationSnapshot snapshot,
  }) {
    AppDiagnostics.record(
      component: 'proactive_priority',
      step: step,
      code: decision.type == ProactiveSuggestionDecisionType.showSuggestion
          ? AppErrorCode.proactiveShow
          : AppErrorCode.proactiveNoShow,
      severity: AppErrorSeverity.info,
      metadata: {
        'result':
            decision.type == ProactiveSuggestionDecisionType.showSuggestion
                ? 'show'
                : 'no_show',
        'candidateCount': candidateCount,
        'durationMs': durationMs,
        'decision': snapshot.decision,
        'reasonCodes': snapshot.reasonCodes.join(','),
        'interactionActive': snapshot.interactionActive,
        'tabActive': snapshot.tabActive,
        'historyState': snapshot.historyState,
        'sessionQuotaConsumed': snapshot.sessionQuotaConsumed,
        'sourceRevision': snapshot.sourceRevision,
        'evaluationGeneration': snapshot.evaluationGeneration,
        if (decision.suggestion != null)
          'suggestionType': decision.suggestion!.suggestionType.name,
      },
    );
  }
}
