import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_provenance.dart';
import 'package:moms_ai/models/life_context/memory_context.dart';
import 'package:moms_ai/models/memory_lifecycle.dart';
import 'package:moms_ai/models/memory_policy.dart';
import 'package:moms_ai/services/memory_policy_engine.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 10);
  const engine = MemoryPolicyEngine();

  group('MemoryPolicy', () {
    test('défaut restrictif, version et scope sont explicites', () {
      final policy = MemoryPolicy.restrictiveDefault(
        accountScopeId: 'account-a',
        changedAt: now,
      );
      expect(policy.generalMode, MemoryGeneralMode.askEveryTime);
      expect(policy.healthMode, MemoryHealthMode.disabled);
      expect(policy.healthConsentGranted, false);
      expect(policy.readsExistingMemories, true);
      expect(
        MemoryPolicy.fromJson(
          policy.toJson(),
          expectedAccountScopeId: 'account-a',
        ).toJson(),
        policy.toJson(),
      );
      expect(
        () => MemoryPolicy.fromJson(
          {...policy.toJson(), 'schemaVersion': 2},
          expectedAccountScopeId: 'account-a',
        ),
        throwsA(isA<MemoryPolicyException>()),
      );
      expect(
        () => MemoryPolicy.fromJson(
          policy.toJson(),
          expectedAccountScopeId: 'account-b',
        ),
        throwsA(isA<MemoryPolicyException>()),
      );
    });

    test('toutes les transitions restent additives et non rétroactives', () {
      for (final general in MemoryGeneralMode.values) {
        for (final health in MemoryHealthMode.values) {
          final current = MemoryPolicy.restrictiveDefault(
            accountScopeId: 'account-a',
            changedAt: now,
          );
          final transition = engine.transition(
            current: current,
            generalMode: general,
            healthMode: health,
            explicitHealthConsent: health == MemoryHealthMode.enabled,
            changedAt: now.add(const Duration(minutes: 1)),
          );
          expect(transition.current.generalMode, general);
          expect(transition.current.healthMode, health);
          expect(transition.pendingProposalsRemainPending, true);
          expect(transition.existingMemoriesRemainAvailable, true);
          expect(transition.retroactiveCaptureAllowed, false);
        }
      }
      expect(
        () => engine.transition(
          current: MemoryPolicy.restrictiveDefault(
            accountScopeId: 'account-a',
            changedAt: now,
          ),
          generalMode: MemoryGeneralMode.automatic,
          healthMode: MemoryHealthMode.enabled,
          explicitHealthConsent: false,
          changedAt: now,
        ),
        throwsA(isA<MemoryPolicyException>()),
      );
    });
  });

  group('MemoryPolicyEngine', () {
    test('automatic accepte uniquement une proposition ordinaire explicite',
        () {
      expect(
        engine
            .evaluate(
              policy: _policy(
                now,
                general: MemoryGeneralMode.automatic,
              ),
              input: _input(),
            )
            .type,
        MemoryPolicyDecisionType.saveAutomatically,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(
                now,
                general: MemoryGeneralMode.automatic,
              ),
              input: _input(explicitEvidence: false),
            )
            .type,
        MemoryPolicyDecisionType.requireConfirmation,
      );
    });

    test('askEveryTime exige confirmation et paused ne propose rien', () {
      expect(
        engine
            .evaluate(
              policy: _policy(now),
              input: _input(),
            )
            .type,
        MemoryPolicyDecisionType.requireConfirmation,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(now, general: MemoryGeneralMode.paused),
              input: _input(),
            )
            .type,
        MemoryPolicyDecisionType.paused,
      );
    });

    test('une directive explicite vaut accord en mode askEveryTime', () {
      final decision = engine.evaluate(
        policy: _policy(now),
        input: _input(explicitSaveDirective: true),
      );

      expect(decision.type, MemoryPolicyDecisionType.saveAutomatically);
      expect(decision.code, 'explicit_memory_directive');
    });

    test('santé reste séparée du mode automatique général', () {
      final automatic = _policy(
        now,
        general: MemoryGeneralMode.automatic,
      );
      expect(
        engine
            .evaluate(
              policy: automatic,
              input: _input(health: true),
            )
            .type,
        MemoryPolicyDecisionType.rejectHealthConsent,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(
                now,
                general: MemoryGeneralMode.automatic,
                health: MemoryHealthMode.askEveryTime,
              ),
              input: _input(
                health: true,
                explicitSaveDirective: true,
              ),
            )
            .type,
        MemoryPolicyDecisionType.requireConfirmation,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(
                now,
                general: MemoryGeneralMode.automatic,
                health: MemoryHealthMode.enabled,
                healthConsent: true,
              ),
              input: _input(health: true),
            )
            .type,
        MemoryPolicyDecisionType.saveAutomatically,
      );
    });

    test('refuse haute sensibilité, doublon, domaine et contradiction', () {
      expect(
        engine
            .evaluate(
              policy: _policy(now),
              input: _input(
                sensitivity: MemoryProposalSensitivity.highlySensitive,
              ),
            )
            .type,
        MemoryPolicyDecisionType.rejectSensitive,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(now),
              input: _input(duplicate: true),
            )
            .type,
        MemoryPolicyDecisionType.rejectDuplicate,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(now),
              input: _input(structuredDomain: 'event'),
            )
            .type,
        MemoryPolicyDecisionType.rejectStructuredDomainOwnership,
      );
      expect(
        engine
            .evaluate(
              policy: _policy(now),
              input: _input(contradiction: true),
            )
            .type,
        MemoryPolicyDecisionType.rejectContradiction,
      );
    });
  });
}

MemoryPolicy _policy(
  DateTime now, {
  MemoryGeneralMode general = MemoryGeneralMode.askEveryTime,
  MemoryHealthMode health = MemoryHealthMode.disabled,
  bool healthConsent = false,
}) =>
    MemoryPolicy(
      accountScopeId: 'account-a',
      generalMode: general,
      healthMode: health,
      healthConsentGranted: healthConsent,
      changedAt: now,
      changeSource: MemoryPolicyChangeSource.explicitUserSetting,
    );

MemoryPolicyProposal _input({
  bool health = false,
  bool explicitEvidence = true,
  bool duplicate = false,
  bool explicitSaveDirective = false,
  bool contradiction = false,
  String? structuredDomain,
  MemoryProposalSensitivity sensitivity = MemoryProposalSensitivity.ordinary,
}) =>
    MemoryPolicyProposal(
      proposal: MemoryProposal(
        id: 'proposal-a',
        text: 'Préférence synthétique',
        normalizedText: 'préférence synthétique',
        semanticType: LifeMemorySemanticType.preference,
        category: health ? 'health' : 'preference',
        importance: 2,
        sensitivity: health
            ? LifeContextSensitivity.sensitive
            : LifeContextSensitivity.standard,
        source: 'explicit_user_message',
        proposedAt: DateTime.utc(2026, 7, 23),
        confirmationRequired: false,
      ),
      sensitivity: sensitivity,
      isExplicitHealth: health,
      hasExplicitUserEvidence: explicitEvidence,
      hasExplicitSaveDirective: explicitSaveDirective,
      isDuplicate: duplicate,
      contradictsConfirmedFact: contradiction,
      structuredDomain: structuredDomain,
    );
