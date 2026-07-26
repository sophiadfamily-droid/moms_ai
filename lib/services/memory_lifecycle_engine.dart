import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_lifecycle_state.dart';
import '../models/memory_contradiction.dart';
import 'memory_contradiction_detector.dart';

final class MemoryLifecycleEngine {
  const MemoryLifecycleEngine({
    MemoryContradictionDetector contradictionDetector =
        const MemoryContradictionDetector(),
  }) : _contradictionDetector = contradictionDetector;

  final MemoryContradictionDetector _contradictionDetector;

  static const Map<MemoryLifecycleState, Set<MemoryLifecycleState>>
      allowedTransitions = {
    MemoryLifecycleState.proposed: {
      MemoryLifecycleState.confirmed,
      MemoryLifecycleState.rejected,
      MemoryLifecycleState.deleted,
    },
    MemoryLifecycleState.confirmed: {
      MemoryLifecycleState.active,
      MemoryLifecycleState.deleted,
    },
    MemoryLifecycleState.active: {
      MemoryLifecycleState.superseded,
      MemoryLifecycleState.obsolete,
      MemoryLifecycleState.deleted,
      MemoryLifecycleState.expired,
    },
    MemoryLifecycleState.obsolete: {MemoryLifecycleState.deleted},
    MemoryLifecycleState.expired: {MemoryLifecycleState.deleted},
    MemoryLifecycleState.rejected: {},
    MemoryLifecycleState.superseded: {MemoryLifecycleState.deleted},
    MemoryLifecycleState.deleted: {},
  };

  MemoryLifecycleDecision evaluateProposal({
    required MemoryProposal proposal,
    required Iterable<LifeMemoryFact> existingMemories,
    required DateTime referenceDate,
    String? accountScopeId,
    String? conflictingProfileField,
  }) {
    if (!_validProposal(proposal)) {
      return _decision(
        MemoryLifecycleDecisionType.ambiguous,
        proposal: proposal,
        reasons: const ['invalid_or_incomplete_proposal'],
        risks: const [MemoryLifecycleSignal.invalidInput],
      );
    }
    if (conflictingProfileField?.trim().isNotEmpty == true) {
      return _decision(
        MemoryLifecycleDecisionType.needsUserConfirmation,
        proposal: proposal,
        reasons: ['conflicts_with_profile:$conflictingProfileField'],
        risks: const [MemoryLifecycleSignal.profileConflict],
        confirmationRequest: _confirmationForProposal(
          proposal,
          prompt: 'Cette information diffère du profil. Veux-tu la confirmer ?',
          consequence:
              'Le profil restera prioritaire tant qu’il n’est pas modifié.',
        ),
      );
    }

    for (final existing in existingMemories) {
      if (_canCompete(existing) && _isExactDuplicate(existing, proposal)) {
        final isPending =
            existing.lifecycleState == MemoryLifecycleState.proposed;
        return _decision(
          isPending
              ? MemoryLifecycleDecisionType.confirmExistingProposal
              : MemoryLifecycleDecisionType.noChange,
          proposal: proposal,
          memoryIds: [existing.id],
          reasons: const ['exact_typed_duplicate'],
          risks: const [MemoryLifecycleSignal.duplicate],
          confirmationRequest: isPending
              ? MemoryConfirmationRequest(
                  action: MemoryLifecycleAction.confirm,
                  proposalId: existing.id,
                  prompt: '',
                  newValue: existing.text,
                  changeType: 'existingProposal',
                  sensitivity: existing.sensitivity,
                  consequence: 'requires_explicit_confirmation',
                )
              : null,
        );
      }
    }

    final contradictions = accountScopeId == null
        ? const <MemoryContradictionMatch>[]
        : existingMemories
            .map(
              (existing) => _contradictionDetector.detect(
                accountScopeId: accountScopeId,
                proposal: proposal,
                existing: existing,
                detectedAt: referenceDate,
              ),
            )
            .whereType<MemoryContradictionMatch>()
            .toList(growable: false);
    if (contradictions.length > 1) {
      return _decision(
        MemoryLifecycleDecisionType.ambiguous,
        proposal: proposal,
        reasons: const ['multiple_memory_contradictions'],
        risks: const [MemoryLifecycleSignal.possibleConflict],
      );
    }
    if (contradictions.length == 1) {
      final contradiction = contradictions.single;
      final existing = existingMemories.firstWhere(
        (item) => item.id == contradiction.existingMemoryId,
      );
      return _decision(
        MemoryLifecycleDecisionType.needsUserConfirmation,
        proposal: proposal,
        memoryIds: [existing.id, proposal.id],
        reasons: const ['same_type_and_category_with_different_value'],
        risks: const [
          MemoryLifecycleSignal.possibleConflict,
          MemoryLifecycleSignal.possibleReplacement,
        ],
        confirmationRequest: MemoryConfirmationRequest(
          action: MemoryLifecycleAction.replace,
          proposalId: proposal.id,
          memoryId: existing.id,
          prompt:
              'Une information déjà mémorisée semble différente de celle que '
              'tu viens d’indiquer. Veux-tu enregistrer la nouvelle '
              'information à la place de l’ancienne ?',
          previousValue: null,
          newValue: null,
          changeType: 'memoryReplacementConfirmation',
          sensitivity: proposal.sensitivity,
          consequence:
              'Le remplacement restera en attente de son exécution sécurisée.',
        ),
        contradictionMatch: contradiction,
        mutations: [
          _mutation(
            memoryId: proposal.id,
            action: MemoryLifecycleAction.propose,
            previousState: null,
            newState: MemoryLifecycleState.proposed,
            at: referenceDate,
            source: proposal.source,
            actor: MemoryLifecycleActor.assistant,
            reason: 'memory_replacement_candidate_created',
            expiresAt: proposal.expiresAt ?? proposal.validUntil,
          ),
        ],
      );
    }

    final temporaryWithoutRange =
        proposal.semanticType == LifeMemorySemanticType.temporary &&
            proposal.validUntil == null &&
            proposal.expiresAt == null;
    if (temporaryWithoutRange) {
      return _decision(
        MemoryLifecycleDecisionType.needsUserConfirmation,
        proposal: proposal,
        reasons: const ['temporary_memory_without_explicit_end'],
        risks: const [MemoryLifecycleSignal.ambiguousTimeRange],
        confirmationRequest: _confirmationForProposal(
          proposal,
          prompt: 'Jusqu’à quand dois-je retenir cette information ?',
          consequence: 'Aucune date d’expiration ne sera inventée.',
        ),
      );
    }

    return _decision(
      MemoryLifecycleDecisionType.createProposal,
      proposal: proposal,
      memoryIds: [proposal.id],
      reasons: const ['new_memory_requires_explicit_lifecycle'],
      risks: proposal.sensitivity == LifeContextSensitivity.sensitive
          ? const [MemoryLifecycleSignal.sensitiveData]
          : const [],
      confirmationRequest: proposal.confirmationRequired ||
              proposal.sensitivity == LifeContextSensitivity.sensitive
          ? _confirmationForProposal(
              proposal,
              prompt: 'Veux-tu que je retienne cette information ?',
              consequence:
                  'La mémoire deviendra confirmée uniquement après ton accord.',
            )
          : null,
      mutations: [
        _mutation(
          memoryId: proposal.id,
          action: MemoryLifecycleAction.propose,
          previousState: null,
          newState: MemoryLifecycleState.proposed,
          at: referenceDate,
          source: proposal.source,
          actor: MemoryLifecycleActor.assistant,
          reason: 'memory_candidate_created',
          expiresAt: proposal.expiresAt ?? proposal.validUntil,
        ),
      ],
    );
  }

  MemoryLifecycleDecision evaluate(MemoryLifecycleCommand command) {
    final target = command.target;
    if (target == null || target.id.trim().isEmpty) {
      return _invalid('missing_stable_memory_id');
    }
    final current = command.targetState ?? target.lifecycleState;
    final desired = _desiredState(command.action);
    if (desired == current) {
      return _decision(
        MemoryLifecycleDecisionType.noChange,
        memoryIds: [target.id],
        reasons: const ['already_in_requested_state'],
      );
    }
    if (command.action == MemoryLifecycleAction.restore) {
      return _invalid('restore_deferred_in_v1', memoryIds: [target.id]);
    }
    if (command.action == MemoryLifecycleAction.replace) {
      return _replace(command, current);
    }
    if (command.action == MemoryLifecycleAction.confirm &&
        target.sensitivity == LifeContextSensitivity.sensitive &&
        command.actor != MemoryLifecycleActor.user) {
      return _decision(
        MemoryLifecycleDecisionType.needsUserConfirmation,
        memoryIds: [target.id],
        reasons: const ['sensitive_confirmation_requires_user'],
        risks: const [MemoryLifecycleSignal.sensitiveData],
      );
    }
    if (command.action == MemoryLifecycleAction.delete &&
        command.actor != MemoryLifecycleActor.user) {
      return _decision(
        MemoryLifecycleDecisionType.needsUserConfirmation,
        memoryIds: [target.id],
        reasons: const ['logical_deletion_requires_user'],
      );
    }
    if (desired == null ||
        !(allowedTransitions[current]?.contains(desired) ?? false)) {
      return _invalid(
        'transition_not_allowed:${current.name}:${desired?.name ?? command.action.name}',
        memoryIds: [target.id],
      );
    }
    if (command.action == MemoryLifecycleAction.expire &&
        (target.validUntil == null ||
            !target.validUntil!.isBefore(command.referenceDate))) {
      return _decision(
        MemoryLifecycleDecisionType.noChange,
        memoryIds: [target.id],
        reasons: const ['expiration_date_not_reached'],
      );
    }
    final record = _record(
      command: command,
      memoryId: target.id,
      previousState: current,
      newState: desired,
    );
    if (_containsRecord(command.history, record)) {
      return _decision(
        MemoryLifecycleDecisionType.noChange,
        memoryIds: [target.id],
        reasons: const ['idempotent_command_already_recorded'],
      );
    }
    return _decision(
      _decisionType(command.action),
      memoryIds: [target.id],
      reasons: ['authorized_${command.action.name}'],
      mutations: [
        MemoryLifecycleMutation(
          memoryId: target.id,
          newState: desired,
          record: record,
          confirmedAt: command.action == MemoryLifecycleAction.confirm
              ? command.referenceDate
              : null,
          rejectedAt: command.action == MemoryLifecycleAction.reject
              ? command.referenceDate
              : null,
          deletedAt: command.action == MemoryLifecycleAction.delete
              ? command.referenceDate
              : null,
          expiresAt: command.action == MemoryLifecycleAction.expire
              ? target.validUntil
              : null,
        ),
      ],
    );
  }

  MemoryLifecycleDecision _replace(
    MemoryLifecycleCommand command,
    MemoryLifecycleState current,
  ) {
    final target = command.target!;
    final replacement = command.replacement;
    if (replacement == null || replacement.id.trim().isEmpty) {
      return _invalid('missing_replacement_memory_id', memoryIds: [target.id]);
    }
    if (replacement.id == target.id) {
      return _invalid('memory_cannot_replace_itself', memoryIds: [target.id]);
    }
    if (replacement.lifecycleState != MemoryLifecycleState.confirmed &&
        replacement.lifecycleState != MemoryLifecycleState.active) {
      return _invalid(
        'replacement_memory_must_be_confirmed',
        memoryIds: [target.id, replacement.id],
      );
    }
    if (current == MemoryLifecycleState.superseded &&
        target.legacyData['replacedByMemoryId'] == replacement.id) {
      return _decision(
        MemoryLifecycleDecisionType.noChange,
        memoryIds: [target.id, replacement.id],
        reasons: const ['replacement_already_applied'],
      );
    }
    if (command.actor != MemoryLifecycleActor.user) {
      return _decision(
        MemoryLifecycleDecisionType.needsUserConfirmation,
        memoryIds: [target.id, replacement.id],
        reasons: const ['replacement_requires_explicit_user_confirmation'],
        risks: const [MemoryLifecycleSignal.possibleReplacement],
        confirmationRequest: MemoryConfirmationRequest(
          action: MemoryLifecycleAction.replace,
          memoryId: target.id,
          proposalId: replacement.id,
          prompt:
              'J’avais enregistré « ${target.text} ». Veux-tu remplacer cette information par « ${replacement.text} » ?',
          previousValue: target.text,
          newValue: replacement.text,
          changeType: 'replacement',
          sensitivity: replacement.sensitivity,
          consequence: 'L’ancienne mémoire sera conservée comme remplacée.',
        ),
      );
    }
    if (!(allowedTransitions[current]
            ?.contains(MemoryLifecycleState.superseded) ??
        false)) {
      return _invalid('source_memory_cannot_be_replaced',
          memoryIds: [target.id]);
    }
    final oldRecord = _record(
      command: command,
      memoryId: target.id,
      previousState: current,
      newState: MemoryLifecycleState.superseded,
      replacementMemoryId: replacement.id,
    );
    return _decision(
      MemoryLifecycleDecisionType.replaceExistingMemory,
      memoryIds: [target.id, replacement.id],
      reasons: const ['explicit_user_confirmed_replacement'],
      mutations: [
        MemoryLifecycleMutation(
          memoryId: target.id,
          newState: MemoryLifecycleState.superseded,
          record: oldRecord,
          replacedByMemoryId: replacement.id,
        ),
        MemoryLifecycleMutation(
          memoryId: replacement.id,
          newState: MemoryLifecycleState.active,
          record: MemoryLifecycleRecord(
            action: MemoryLifecycleAction.activate,
            previousState: replacement.lifecycleState,
            newState: MemoryLifecycleState.active,
            occurredAt: command.referenceDate,
            source: command.source,
            actor: command.actor,
            memoryId: replacement.id,
            replacementMemoryId: target.id,
            reason: command.reason ?? 'replacement_confirmed',
          ),
          supersedesMemoryId: target.id,
        ),
      ],
    );
  }

  bool _validProposal(MemoryProposal proposal) {
    return proposal.id.trim().isNotEmpty &&
        proposal.text.trim().isNotEmpty &&
        proposal.normalizedText.trim().isNotEmpty &&
        proposal.importance >= 0 &&
        proposal.importance <= 3 &&
        proposal.hasValidDates &&
        (proposal.confidence == null ||
            (proposal.confidence! >= 0 && proposal.confidence! <= 1));
  }

  bool _isExactDuplicate(LifeMemoryFact fact, MemoryProposal proposal) {
    return fact.normalizedText == proposal.normalizedText &&
        fact.semanticType == proposal.semanticType &&
        _category(fact.category) == _category(proposal.category);
  }

  bool _canCompete(LifeMemoryFact fact) {
    if (!fact.lifecycleStateIsExplicit) return true;
    return const {
      MemoryLifecycleState.proposed,
      MemoryLifecycleState.confirmed,
      MemoryLifecycleState.active,
    }.contains(fact.lifecycleState);
  }

  String _category(String value) => value.trim().toLowerCase();

  bool _containsRecord(
    List<MemoryLifecycleRecord> history,
    MemoryLifecycleRecord candidate,
  ) =>
      history
          .any((record) => record.idempotencyKey == candidate.idempotencyKey);

  MemoryLifecycleState? _desiredState(MemoryLifecycleAction action) =>
      switch (action) {
        MemoryLifecycleAction.propose => MemoryLifecycleState.proposed,
        MemoryLifecycleAction.confirm => MemoryLifecycleState.confirmed,
        MemoryLifecycleAction.reject => MemoryLifecycleState.rejected,
        MemoryLifecycleAction.activate => MemoryLifecycleState.active,
        MemoryLifecycleAction.markObsolete => MemoryLifecycleState.obsolete,
        MemoryLifecycleAction.delete => MemoryLifecycleState.deleted,
        MemoryLifecycleAction.expire => MemoryLifecycleState.expired,
        MemoryLifecycleAction.replace || MemoryLifecycleAction.restore => null,
      };

  MemoryLifecycleDecisionType _decisionType(MemoryLifecycleAction action) =>
      switch (action) {
        MemoryLifecycleAction.confirm =>
          MemoryLifecycleDecisionType.confirmExistingProposal,
        MemoryLifecycleAction.reject =>
          MemoryLifecycleDecisionType.rejectProposal,
        MemoryLifecycleAction.activate =>
          MemoryLifecycleDecisionType.createNewMemory,
        MemoryLifecycleAction.markObsolete =>
          MemoryLifecycleDecisionType.markExistingObsolete,
        MemoryLifecycleAction.delete =>
          MemoryLifecycleDecisionType.deleteExistingMemory,
        _ => MemoryLifecycleDecisionType.noChange,
      };

  MemoryLifecycleRecord _record({
    required MemoryLifecycleCommand command,
    required String memoryId,
    required MemoryLifecycleState previousState,
    required MemoryLifecycleState newState,
    String? replacementMemoryId,
  }) =>
      MemoryLifecycleRecord(
        action: command.action,
        previousState: previousState,
        newState: newState,
        occurredAt: command.referenceDate,
        source: command.source,
        actor: command.actor,
        memoryId: memoryId,
        replacementMemoryId: replacementMemoryId,
        reason: command.reason,
      );

  MemoryLifecycleMutation _mutation({
    required String memoryId,
    required MemoryLifecycleAction action,
    required MemoryLifecycleState? previousState,
    required MemoryLifecycleState newState,
    required DateTime at,
    required String source,
    required MemoryLifecycleActor actor,
    required String reason,
    DateTime? expiresAt,
  }) =>
      MemoryLifecycleMutation(
        memoryId: memoryId,
        newState: newState,
        expiresAt: expiresAt,
        record: MemoryLifecycleRecord(
          action: action,
          previousState: previousState,
          newState: newState,
          occurredAt: at,
          source: source,
          actor: actor,
          memoryId: memoryId,
          reason: reason,
        ),
      );

  MemoryConfirmationRequest _confirmationForProposal(
    MemoryProposal proposal, {
    required String prompt,
    required String consequence,
  }) =>
      MemoryConfirmationRequest(
        action: MemoryLifecycleAction.confirm,
        proposalId: proposal.id,
        prompt: prompt,
        newValue: proposal.text,
        changeType: 'proposal',
        sensitivity: proposal.sensitivity,
        consequence: consequence,
      );

  MemoryLifecycleDecision _invalid(
    String reason, {
    List<String> memoryIds = const [],
  }) =>
      _decision(
        MemoryLifecycleDecisionType.invalidTransition,
        memoryIds: memoryIds,
        reasons: [reason],
        risks: const [MemoryLifecycleSignal.invalidInput],
      );

  MemoryLifecycleDecision _decision(
    MemoryLifecycleDecisionType type, {
    List<String> memoryIds = const [],
    List<String> reasons = const [],
    List<MemoryLifecycleSignal> risks = const [],
    List<MemoryLifecycleMutation> mutations = const [],
    MemoryConfirmationRequest? confirmationRequest,
    MemoryProposal? proposal,
    MemoryContradictionCandidate? contradictionCandidate,
    MemoryContradictionMatch? contradictionMatch,
  }) =>
      MemoryLifecycleDecision(
        type: type,
        memoryIds: memoryIds,
        reasons: reasons,
        risks: risks,
        mutations: mutations,
        confirmationRequest: confirmationRequest,
        proposal: proposal,
        contradictionCandidate: contradictionCandidate,
        contradictionMatch: contradictionMatch,
      );
}
