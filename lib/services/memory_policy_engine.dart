import '../models/life_context/life_context_provenance.dart';
import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle.dart';
import '../models/memory_policy.dart';

enum MemoryProposalSensitivity {
  ordinary,
  private,
  sensitive,
  highlySensitive,
}

enum MemoryPolicyDecisionType {
  saveAutomatically,
  requireConfirmation,
  rejectByPolicy,
  rejectSensitive,
  rejectHealthConsent,
  rejectDuplicate,
  rejectStructuredDomainOwnership,
  rejectContradiction,
  paused,
  invalidProposal,
}

final class MemoryPolicyProposal {
  const MemoryPolicyProposal({
    required this.proposal,
    required this.sensitivity,
    required this.isExplicitHealth,
    required this.hasExplicitUserEvidence,
    this.structuredDomain,
    this.structuredReferenceId,
    this.isDuplicate = false,
    this.contradictsConfirmedFact = false,
  });

  final MemoryProposal proposal;
  final MemoryProposalSensitivity sensitivity;
  final bool isExplicitHealth;
  final bool hasExplicitUserEvidence;
  final String? structuredDomain;
  final String? structuredReferenceId;
  final bool isDuplicate;
  final bool contradictsConfirmedFact;
}

final class MemoryPolicyDecision {
  const MemoryPolicyDecision(this.type, this.code);

  final MemoryPolicyDecisionType type;
  final String code;
}

final class MemoryPolicyEngine {
  const MemoryPolicyEngine();

  MemoryPolicyTransition transition({
    required MemoryPolicy current,
    required MemoryGeneralMode generalMode,
    required MemoryHealthMode healthMode,
    required bool explicitHealthConsent,
    required DateTime changedAt,
  }) {
    current.validate();
    if (healthMode == MemoryHealthMode.enabled && !explicitHealthConsent) {
      throw const MemoryPolicyException('health_consent_required');
    }
    final next = MemoryPolicy(
      accountScopeId: current.accountScopeId,
      generalMode: generalMode,
      healthMode: healthMode,
      healthConsentGranted:
          healthMode == MemoryHealthMode.enabled && explicitHealthConsent,
      changedAt: changedAt.toUtc(),
      changeSource: MemoryPolicyChangeSource.explicitUserSetting,
    )..validate();
    return MemoryPolicyTransition(
      previous: current,
      current: next,
      pendingProposalsRemainPending: true,
      existingMemoriesRemainAvailable: true,
      retroactiveCaptureAllowed: false,
    );
  }

  MemoryPolicyDecision evaluate({
    required MemoryPolicy policy,
    required MemoryPolicyProposal input,
  }) {
    policy.validate();
    final proposal = input.proposal;
    if (proposal.id.trim().isEmpty ||
        proposal.text.trim().isEmpty ||
        proposal.normalizedText.trim().isEmpty ||
        !proposal.hasValidDates) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.invalidProposal,
        'invalid_memory_proposal',
      );
    }
    if (policy.generalMode == MemoryGeneralMode.paused) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.paused,
        'memory_paused',
      );
    }
    if (input.isDuplicate) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.rejectDuplicate,
        'memory_duplicate',
      );
    }
    if (input.structuredDomain?.trim().isNotEmpty == true) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.rejectStructuredDomainOwnership,
        'structured_domain_owns_fact',
      );
    }
    if (input.contradictsConfirmedFact) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.rejectContradiction,
        'confirmed_fact_conflict',
      );
    }
    if (input.sensitivity == MemoryProposalSensitivity.highlySensitive) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.rejectSensitive,
        'highly_sensitive_memory_rejected',
      );
    }
    if (input.isExplicitHealth) {
      switch (policy.healthMode) {
        case MemoryHealthMode.disabled:
          return const MemoryPolicyDecision(
            MemoryPolicyDecisionType.rejectHealthConsent,
            'health_memory_disabled',
          );
        case MemoryHealthMode.askEveryTime:
          return const MemoryPolicyDecision(
            MemoryPolicyDecisionType.requireConfirmation,
            'health_confirmation_required',
          );
        case MemoryHealthMode.enabled:
          if (!policy.healthConsentGranted) {
            return const MemoryPolicyDecision(
              MemoryPolicyDecisionType.rejectHealthConsent,
              'health_consent_missing',
            );
          }
      }
    }
    if (policy.generalMode == MemoryGeneralMode.askEveryTime ||
        input.sensitivity == MemoryProposalSensitivity.sensitive ||
        !input.hasExplicitUserEvidence ||
        proposal.confidence != null && proposal.confidence! < 0.8) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.requireConfirmation,
        'memory_confirmation_required',
      );
    }
    if (policy.generalMode == MemoryGeneralMode.automatic) {
      return const MemoryPolicyDecision(
        MemoryPolicyDecisionType.saveAutomatically,
        'memory_automatic_allowed',
      );
    }
    return const MemoryPolicyDecision(
      MemoryPolicyDecisionType.rejectByPolicy,
      'memory_policy_rejected',
    );
  }

  MemoryProposalSensitivity sensitivityFor(LifeMemoryFact fact) =>
      fact.sensitivity == LifeContextSensitivity.sensitive
          ? MemoryProposalSensitivity.sensitive
          : MemoryProposalSensitivity.ordinary;
}
