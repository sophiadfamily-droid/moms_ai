import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/conversation_context_envelope.dart';
import 'package:moms_ai/models/conversation_epistemic_models.dart';
import 'package:moms_ai/services/conversation_grounding_policy.dart';

void main() {
  group('V1-C.3 epistemic models', () {
    test('all certainty states are closed and current version round-trips', () {
      expect(ConversationEpistemicState.values.map((value) => value.name), {
        'grounded',
        'groundedPartial',
        'uncertain',
        'conflicting',
        'stale',
        'contextUnavailable',
        'insufficientInformation',
        'unsupported',
        'invalid',
      });
      final original = contract();
      final decoded = ConversationEpistemicContract.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );
      expect(decoded.toJson(), original.toJson());
    });

    test('future versions, unknown fields and response types are refused', () {
      final json = Map<String, dynamic>.from(contract().toJson());
      expect(
        () => ConversationEpistemicContract.fromJson({
          ...json,
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => ConversationEpistemicContract.fromJson({
          ...json,
          'unexpected': true,
        }),
        throwsFormatException,
      );
      expect(
        () => ConversationEpistemicContract.fromJson({
          ...json,
          'responseKind': 'future',
        }),
        throwsFormatException,
      );
    });

    test('backend response rejects missing epistemic and unknown fields', () {
      expect(
        () => ChatBackendResponse.fromJson({
          'reply': 'Réponse',
          'actions': const [],
          'memories': const [],
        }),
        throwsFormatException,
      );
      expect(
        () => ChatBackendResponse.fromJson({
          'reply': 'Réponse',
          'actions': const [],
          'memories': const [],
          'epistemic': contract().toJson(),
          'payload': const {},
        }),
        throwsFormatException,
      );
    });
  });

  group('V1-C.3 grounding and absence', () {
    const policy = ConversationGroundingPolicy();

    test('accepts a personal fact only when its source exists', () {
      final result = policy.validate(
        contract: contract(
          sources: const [
            ConversationGroundingSourceType.lifeContextEvent,
          ],
          references: const [
            ConversationGroundingReference(
              sourceType: ConversationGroundingSourceType.lifeContextEvent,
              section: 'event',
              factKey: 'status',
              freshness: 'current',
              confirmation: 'confirmed',
              projectionVersion: 3,
            ),
          ],
          claims: [
            ConversationPersonalClaim(
              claimId: 'claim-1',
              category: ConversationPersonalClaimCategory.eventFact,
              sourceReferenceIndexes: const [0],
              certainty: ConversationEpistemicState.grounded,
            ),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [],
      );
      expect(result.isValid, isTrue);
    });

    test('accepts a shopping fact carried by the shared brain context', () {
      final envelope = ConversationContextEnvelope(
        projectionVersion: 3,
        purpose: ConversationTransportContract.purposeId,
        generatedAt: DateTime.utc(2026, 7, 23),
        state: ConversationContextState.complete,
        sections: [
          ConversationContextSection(
            type: 'shopping',
            availability: 'available',
            freshness: 'current',
            items: [
              ConversationContextItem(
                type: 'shoppingItem',
                confirmation: 'confirmed',
                freshness: 'current',
                facts: {'title': 'Fraises', 'urgency': 'urgent'},
              ),
            ],
            budgetLimit: 25,
            budgetUsed: 2,
            omittedCount: 0,
            truncated: false,
          ),
        ],
        budgetRequested: 330,
        budgetUsed: 2,
        omittedCount: 0,
        truncatedSections: const [],
        warningCodes: const [],
      );
      final result = policy.validate(
        contract: contract(
          sources: const [
            ConversationGroundingSourceType.lifeContextShopping,
          ],
          references: const [
            ConversationGroundingReference(
              sourceType: ConversationGroundingSourceType.lifeContextShopping,
              section: 'shopping',
              factKey: 'urgency',
              freshness: 'current',
              confirmation: 'confirmed',
              projectionVersion: 3,
            ),
          ],
          claims: [
            ConversationPersonalClaim(
              claimId: 'shopping-claim-1',
              category: ConversationPersonalClaimCategory.shoppingFact,
              sourceReferenceIndexes: const [0],
              certainty: ConversationEpistemicState.grounded,
            ),
          ],
        ),
        envelope: envelope,
        actions: const [],
      );

      expect(result.isValid, isTrue);
    });

    test('accepts shopping facts verified by the authenticated server', () {
      final result = policy.validate(
        contract: contract(
          sources: const [
            ConversationGroundingSourceType.serverVerifiedShopping,
          ],
          references: const [
            ConversationGroundingReference(
              sourceType:
                  ConversationGroundingSourceType.serverVerifiedShopping,
              freshness: 'current',
              confirmation: 'confirmed',
              projectionVersion: 3,
            ),
          ],
          claims: [
            ConversationPersonalClaim(
              claimId: 'shopping-server-1',
              category: ConversationPersonalClaimCategory.shoppingFact,
              sourceReferenceIndexes: const [0],
              certainty: ConversationEpistemicState.grounded,
            ),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [],
      );
      expect(result.isValid, isTrue);
    });

    test('refuses a missing source and general knowledge personal claim', () {
      final missing = policy.validate(
        contract: contract(
          references: const [
            ConversationGroundingReference(
              sourceType: ConversationGroundingSourceType.lifeContextEvent,
              section: 'event',
              factKey: 'deadline',
              freshness: 'current',
              confirmation: 'confirmed',
              projectionVersion: 3,
            ),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [],
      );
      expect(missing.code, 'grounding_reference_missing');

      final general = policy.validate(
        contract: contract(
          references: const [
            ConversationGroundingReference(
              sourceType: ConversationGroundingSourceType.generalKnowledge,
              freshness: 'current',
              confirmation: 'confirmed',
              projectionVersion: 0,
            ),
          ],
          claims: [
            ConversationPersonalClaim(
              claimId: 'claim-1',
              category: ConversationPersonalClaimCategory.humanFact,
              sourceReferenceIndexes: const [0],
              certainty: ConversationEpistemicState.grounded,
            ),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [],
      );
      expect(general.code, 'personal_claim_uses_general_knowledge');
    });

    test('unavailable remains different from an available empty section', () {
      final unavailable = ConversationContextEnvelope.unavailable(
        state: ConversationContextState.unavailable,
        generatedAt: DateTime.utc(2026, 7, 23),
        warningCode: 'context_unavailable',
      );
      expect(unavailable.state, ConversationContextState.unavailable);
      expect(availableEnvelope(items: const []).state,
          ConversationContextState.complete);
      final decision = policy.decide(
        state: ConversationEpistemicState.contextUnavailable,
        missingInformation: const [],
        contradictions: const [],
        hasAction: false,
        ledger: const ConversationClarificationLedger(),
        sessionGeneration: 0,
      );
      expect(decision, ConversationClarificationDecision.retryContext);
    });

    test('stale evidence cannot be presented as current', () {
      final result = policy.validate(
        contract: contract(
          references: const [
            ConversationGroundingReference(
              sourceType: ConversationGroundingSourceType.lifeContextEvent,
              section: 'event',
              factKey: 'status',
              freshness: 'stale',
              confirmation: 'confirmed',
              projectionVersion: 3,
            ),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [],
      );
      expect(result.code, 'stale_presented_as_current');
    });
  });

  group('V1-C.3 clarification policy and action guards', () {
    const policy = ConversationGroundingPolicy();

    test('optional absence answers, required absence clarifies', () {
      final optional = policy.decide(
        state: ConversationEpistemicState.groundedPartial,
        missingInformation: [
          missing(
            ConversationMissingInformationCode.missingDeadline,
            required: false,
          ),
        ],
        contradictions: const [],
        hasAction: false,
        ledger: const ConversationClarificationLedger(),
        sessionGeneration: 0,
      );
      expect(optional, ConversationClarificationDecision.answerWithCaveat);

      final required = policy.decide(
        state: ConversationEpistemicState.insufficientInformation,
        missingInformation: [
          missing(ConversationMissingInformationCode.missingDate),
        ],
        contradictions: const [],
        hasAction: true,
        ledger: const ConversationClarificationLedger(),
        sessionGeneration: 0,
      );
      expect(required, ConversationClarificationDecision.clarify);
    });

    test('ledger prevents repeated and unbounded clarification', () {
      const initial = ConversationClarificationLedger();
      expect(
        initial.canAsk(
          const [ConversationMissingInformationCode.missingDate],
          generation: 0,
        ),
        isTrue,
      );
      final asked = initial.record(
        const [ConversationMissingInformationCode.missingDate],
      );
      expect(
        asked.canAsk(
          const [ConversationMissingInformationCode.missingDate],
          generation: 0,
        ),
        isFalse,
      );
      final maximum = asked.record(const [
        ConversationMissingInformationCode.missingTime
      ]).record(const [ConversationMissingInformationCode.missingDuration]);
      expect(
        maximum.canAsk(
          const [ConversationMissingInformationCode.missingPerson],
          generation: 0,
        ),
        isFalse,
      );
      expect(
        initial.canAsk(
          const [ConversationMissingInformationCode.missingDate],
          generation: 1,
        ),
        isFalse,
      );
    });

    test('an incomplete Event is blocked without defaults', () {
      final result = policy.validate(
        contract: contract(
          kind: ConversationResponseKind.actionProposal,
        ),
        envelope: availableEnvelope(),
        actions: const [
          {'type': 'event', 'title': 'Rendez-vous'},
        ],
      );
      expect(result.code, 'incomplete_action');
    });

    test('minimal Task and Shopping do not invent optional values', () {
      for (final type in const ['task', 'shopping']) {
        final result = policy.validate(
          contract: contract(
            kind: ConversationResponseKind.actionProposal,
          ),
          envelope: availableEnvelope(),
          actions: [
            {'type': type, 'title': 'Élément'},
          ],
        );
        expect(result.isValid, isTrue);
      }
    });

    test('required information and contradiction block an action', () {
      final missingResult = policy.validate(
        contract: contract(
          kind: ConversationResponseKind.actionProposal,
          missingInformation: [
            missing(ConversationMissingInformationCode.missingTaskTarget),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [
          {'type': 'task', 'title': 'Action'},
        ],
      );
      expect(missingResult.code, 'action_blocked_by_epistemic_state');

      final conflictResult = policy.validate(
        contract: contract(
          kind: ConversationResponseKind.actionProposal,
          state: ConversationEpistemicState.conflicting,
          contradictions: const [
            ConversationContradiction(
              type: ConversationContradictionType.twoConfirmedValues,
              domain: 'event',
              field: 'date',
              requiresClarification: true,
              blocksAction: true,
              code: 'event_date_conflict',
            ),
          ],
        ),
        envelope: availableEnvelope(),
        actions: const [
          {'type': 'task', 'title': 'Action'},
        ],
      );
      expect(conflictResult.code, 'action_blocked_by_epistemic_state');
    });
  });
}

ConversationContextEnvelope availableEnvelope({
  List<ConversationContextItem>? items,
}) =>
    ConversationContextEnvelope(
      projectionVersion: 3,
      purpose: ConversationTransportContract.purposeId,
      generatedAt: DateTime.utc(2026, 7, 23),
      state: ConversationContextState.complete,
      sections: [
        ConversationContextSection(
          type: 'event',
          availability: 'available',
          freshness: 'current',
          items: items ??
              [
                ConversationContextItem(
                  type: 'event',
                  confirmation: 'confirmed',
                  freshness: 'current',
                  facts: const {'status': 'active'},
                ),
              ],
          budgetLimit: 50,
          budgetUsed: items?.length ?? 1,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      budgetRequested: 245,
      budgetUsed: items?.length ?? 1,
      omittedCount: 0,
      truncatedSections: const [],
      warningCodes: const [],
    );

ConversationMissingInformation missing(
  ConversationMissingInformationCode code, {
  bool required = true,
}) =>
    ConversationMissingInformation(
      code: code,
      domain: 'event',
      field: code.name,
      isRequired: required,
      canClarify: true,
    );

ConversationEpistemicContract contract({
  ConversationResponseKind kind = ConversationResponseKind.answer,
  ConversationEpistemicState state = ConversationEpistemicState.grounded,
  List<ConversationGroundingSourceType> sources = const [
    ConversationGroundingSourceType.currentUserMessage,
  ],
  List<ConversationGroundingReference> references = const [
    ConversationGroundingReference(
      sourceType: ConversationGroundingSourceType.currentUserMessage,
      freshness: 'current',
      confirmation: 'confirmed',
      projectionVersion: 0,
    ),
  ],
  List<ConversationPersonalClaim> claims = const [],
  List<ConversationMissingInformation> missingInformation = const [],
  List<ConversationContradiction> contradictions = const [],
  ConversationClarification? clarification,
}) =>
    ConversationEpistemicContract(
      responseKind: kind,
      epistemicState: state,
      confidenceLevel: ConversationConfidenceLevel.high,
      usedSourceTypes: sources,
      groundingReferences: references,
      personalClaims: claims,
      missingInformation: missingInformation,
      contradictions: contradictions,
      clarification: clarification,
      uncertaintyCodes: const [],
      contextStateObserved: ConversationContextState.complete,
      warningCodes: const [],
      responseId: 'response-1',
    );
