const assert = require("node:assert/strict");
const test = require("node:test");

const {
  validateConversationResponse,
} = require("../../services/conversationResponseContract");

/**
 * Builds a validated C.2 request fixture.
 * @param {object} contextOverrides Context overrides.
 * @return {object} Canonical request.
 */
function request(contextOverrides = {}) {
  return {
    schemaVersion: 2,
    message: "Ma demande",
    sessionGeneration: 4,
    conversationContext: {
      schemaVersion: 1,
      projectionVersion: 3,
      purpose: "conversation.transport.v1",
      generatedAt: "2026-07-23T10:00:00.000Z",
      state: "complete",
      sections: [{
        type: "event",
        availability: "available",
        freshness: "current",
        items: [{
          type: "event",
          confirmation: "confirmed",
          freshness: "current",
          facts: {status: "active"},
        }],
        budgetLimit: 50,
        budgetUsed: 1,
        omittedCount: 0,
        truncated: false,
      }],
      budgetRequested: 245,
      budgetUsed: 1,
      omittedCount: 0,
      truncatedSections: [],
      warningCodes: [],
      redactionVersion: 1,
      ...contextOverrides,
    },
    conversationHistory: [],
    profile: {},
    profileContext: {},
    memories: [],
    memoryReasoning: [],
    events: [],
    autonomyPolicyVersion: 1,
    autonomyMode: "suggestions",
    allowedStructuredResponseKinds: [
      "answer", "answerWithCaveat", "clarificationRequired",
      "confirmationRequired", "actionProposal", "cannotDetermine",
      "contextUnavailable", "unsupportedRequest", "safeFailure",
    ],
  };
}

/**
 * Builds a closed C.3 response fixture.
 * @param {object} epistemicOverrides Epistemic overrides.
 * @param {Array<object>} actions Structured actions.
 * @return {object} Canonical model response.
 */
function response(epistemicOverrides = {}, actions = []) {
  return {
    visibleText: "Réponse sûre.",
    actions,
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: actions.length === 0 ? "answer" : "actionProposal",
      epistemicState: "grounded",
      confidenceLevel: "high",
      usedSourceTypes: ["currentUserMessage"],
      groundingReferences: [{
        schemaVersion: 1,
        sourceType: "currentUserMessage",
        section: null,
        factKey: null,
        freshness: "current",
        confirmation: "confirmed",
        projectionVersion: 0,
      }],
      personalClaims: [],
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: [],
      contextStateObserved: "complete",
      warningCodes: [],
      responseId: "response-1",
      ...epistemicOverrides,
    },
  };
}

test("accepts general knowledge without a personal claim", () => {
  const value = response({
    usedSourceTypes: ["generalKnowledge"],
    groundingReferences: [{
      schemaVersion: 1,
      sourceType: "generalKnowledge",
      section: null,
      factKey: null,
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: 0,
    }],
  });
  assert.equal(validateConversationResponse(value, request()), value);
});

test("accepts a personal claim grounded in the sent envelope", () => {
  const value = response({
    usedSourceTypes: ["lifeContextEvent"],
    groundingReferences: [{
      schemaVersion: 1,
      sourceType: "lifeContextEvent",
      section: "event",
      factKey: "status",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: 3,
    }],
    personalClaims: [{
      claimId: "claim-1",
      category: "eventFact",
      sourceReferenceIndexes: [0],
      certainty: "grounded",
    }],
  });
  assert.equal(validateConversationResponse(value, request()), value);
});

test("rejects absent, unknown and general-only personal sources", () => {
  const absent = response({
    groundingReferences: [{
      schemaVersion: 1,
      sourceType: "lifeContextEvent",
      section: "event",
      factKey: "missing",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: 3,
    }],
  });
  assert.throws(() => validateConversationResponse(absent, request()),
      /response_grounding_reference_invalid/);

  const general = response({
    groundingReferences: [{
      schemaVersion: 1,
      sourceType: "generalKnowledge",
      section: null,
      factKey: null,
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: 0,
    }],
    personalClaims: [{
      claimId: "claim-1",
      category: "humanFact",
      sourceReferenceIndexes: [0],
      certainty: "grounded",
    }],
  });
  assert.throws(() => validateConversationResponse(general, request()),
      /response_personal_claim_ungrounded/);
});

test("keeps unavailable distinct from an empty available section", () => {
  const unavailableRequest = request({
    state: "partial",
    sections: [{
      type: "event",
      availability: "unavailable",
      freshness: "unknown",
      items: [],
      budgetLimit: 50,
      budgetUsed: 0,
      omittedCount: 0,
      truncated: false,
    }],
  });
  const unavailable = response({
    responseKind: "contextUnavailable",
    epistemicState: "contextUnavailable",
    confidenceLevel: "unavailable",
    contextStateObserved: "partial",
    usedSourceTypes: [],
    groundingReferences: [],
  });
  assert.equal(
      validateConversationResponse(unavailable, unavailableRequest),
      unavailable,
  );

  const inventedEmpty = response({
    contextStateObserved: "partial",
    groundingReferences: [{
      schemaVersion: 1,
      sourceType: "lifeContextEvent",
      section: "event",
      factKey: "status",
      freshness: "current",
      confirmation: "confirmed",
      projectionVersion: 3,
    }],
  });
  assert.throws(
      () => validateConversationResponse(inventedEmpty, unavailableRequest),
      /response_grounding_reference_invalid/,
  );
});

test("paused mode refuses model-produced structured actions", () => {
  const req = request();
  req.autonomyMode = "paused";
  req.allowedStructuredResponseKinds = [
    "answer", "answerWithCaveat", "clarificationRequired",
    "cannotDetermine", "contextUnavailable", "unsupportedRequest",
    "safeFailure",
  ];
  const result = response({}, [{type: "task", title: "Action"}]);
  assert.throws(() => validateConversationResponse(result, req));
});

test("rejects stale evidence presented as current", () => {
  const value = response({
    usedSourceTypes: ["lifeContextEvent"],
    groundingReferences: [{
      schemaVersion: 1,
      sourceType: "lifeContextEvent",
      section: "event",
      factKey: "status",
      freshness: "stale",
      confirmation: "confirmed",
      projectionVersion: 3,
    }],
  });
  assert.throws(() => validateConversationResponse(value, request()),
      /response_stale_as_current/);
});

test("rejects incomplete events and preserves minimal other actions", () => {
  assert.throws(
      () => validateConversationResponse(
          response({}, [{type: "event", title: "Rendez-vous"}]),
          request(),
      ),
      /response_action_incomplete/,
  );
  for (const type of ["task", "shopping"]) {
    const value = response({}, [{type, title: "Élément"}]);
    assert.equal(validateConversationResponse(value, request()), value);
  }
});

test("missing data and blocking contradictions prevent actions", () => {
  const action = [{type: "task", title: "Action"}];
  const missing = response({
    missingInformation: [{
      schemaVersion: 1,
      code: "missingTaskTarget",
      domain: "task",
      field: "target",
      isRequired: true,
      canClarify: true,
    }],
  }, action);
  assert.throws(() => validateConversationResponse(missing, request()),
      /response_action_incomplete/);

  const contradiction = response({
    contradictions: [{
      schemaVersion: 1,
      type: "twoConfirmedValues",
      domain: "event",
      field: "date",
      requiresClarification: true,
      blocksAction: true,
      code: "event_date_conflict",
    }],
  }, action);
  assert.throws(() => validateConversationResponse(contradiction, request()),
      /response_action_incomplete/);
});

test("validates clarification and binds it to the request generation", () => {
  const value = response({
    responseKind: "clarificationRequired",
    epistemicState: "insufficientInformation",
    confidenceLevel: "low",
    missingInformation: [{
      schemaVersion: 1,
      code: "missingDate",
      domain: "event",
      field: "date",
      isRequired: true,
      canClarify: true,
    }],
    clarification: {
      schemaVersion: 1,
      clarificationId: "clarification-1",
      reasonCode: "event_date_required",
      questionText: "Pour quel jour ?",
      expectedAnswerType: "date",
      allowedChoices: [],
      missingFieldCodes: ["missingDate"],
      createdAt: "2026-07-23T10:00:00.000Z",
      expiresAt: null,
      attemptNumber: 1,
      sessionGeneration: 0,
    },
  });
  validateConversationResponse(value, request());
  assert.equal(value.epistemic.clarification.sessionGeneration, 4);
});

test("rejects unknown nested fields and excessive claims", () => {
  const unknown = response();
  unknown.epistemic.groundingReferences[0].payload = {};
  assert.throws(() => validateConversationResponse(unknown, request()),
      /response_grounding_reference_invalid/);

  const tooMany = response({
    personalClaims: Array.from({length: 11}, (_, index) => ({
      claimId: `claim-${index}`,
      category: "taskFact",
      sourceReferenceIndexes: [0],
      certainty: "grounded",
    })),
  });
  assert.throws(() => validateConversationResponse(tooMany, request()),
      /response_grounding_bounds/);
});

test("refuses a model-fabricated confirmation acceptance", () => {
  const action = {
    type: "task",
    title: "Préparer le dossier",
    accepted: true,
  };
  const value = response({
    responseKind: "confirmationRequired",
  }, [action]);
  assert.throws(() => validateConversationResponse(value, request()),
      /response_action_incomplete/);
});
