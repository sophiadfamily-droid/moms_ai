const assert = require("node:assert/strict");
const test = require("node:test");

const {
  validateConversationRequest,
} = require("../../services/conversationContextContract");

/**
 * Builds a canonical request fixture with controlled overrides.
 * @param {object} overrides Root request overrides.
 * @return {object} Canonical request.
 */
function payload(overrides = {}) {
  return {
    schemaVersion: 2,
    correlationId: "0123456789abcdef0123456789abcdef",
    message: "Bonjour",
    sessionGeneration: 0,
    conversationContext: {
      schemaVersion: 1,
      projectionVersion: 1,
      purpose: "conversation.transport.v1",
      generatedAt: "2026-07-23T10:00:00.000Z",
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
      budgetRequested: 245,
      budgetUsed: 0,
      omittedCount: 0,
      truncatedSections: [],
      warningCodes: ["event_unavailable"],
      redactionVersion: 1,
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
    ...overrides,
  };
}

test("accepts canonical partial context and preserves unavailable section",
    () => {
      const result = validateConversationRequest(payload());
      assert.equal(result.conversationContext.state, "partial");
      assert.equal(
          result.conversationContext.sections[0].availability,
          "unavailable",
      );
    });

test("refuses future, absent and unknown request schemas", () => {
  assert.throws(() => validateConversationRequest(payload({schemaVersion: 3})));
  const absent = payload();
  delete absent.schemaVersion;
  assert.throws(() => validateConversationRequest(absent));
  assert.throws(() => validateConversationRequest(payload({unknown: true})));
});

test("requires a bounded opaque client correlation identifier", () => {
  assert.equal(
      validateConversationRequest(payload()).correlationId,
      "0123456789abcdef0123456789abcdef",
  );
  for (const correlationId of [
    "",
    "short",
    "g".repeat(32),
    "a".repeat(33),
    "firebase-uid:private-message",
  ]) {
    assert.throws(() => validateConversationRequest(payload({correlationId})));
  }
  const absent = payload();
  delete absent.correlationId;
  assert.throws(() => validateConversationRequest(absent));
});

test("validates the closed autonomy mode and blocks executable kinds in pause",
    () => {
      assert.equal(validateConversationRequest(payload()).autonomyMode,
          "suggestions");
      assert.throws(() => validateConversationRequest(
          payload({autonomyMode: "unknown"})));
      assert.throws(() => validateConversationRequest(payload({
        autonomyMode: "paused",
        allowedStructuredResponseKinds: ["answer", "actionProposal"],
      })));
      const paused = validateConversationRequest(payload({
        autonomyMode: "paused",
        allowedStructuredResponseKinds: [
          "answer", "answerWithCaveat", "clarificationRequired",
          "cannotDetermine", "contextUnavailable", "unsupportedRequest",
          "safeFailure",
        ],
      }));
      assert.equal(paused.autonomyMode, "paused");
    });

test("refuses oversized current messages including UTF-8", () => {
  assert.throws(() => validateConversationRequest(
      payload({message: "a".repeat(4001)})));
  assert.throws(() => validateConversationRequest(
      payload({message: "🧡".repeat(3500)})));
});

test("refuses unbounded history and invalid roles", () => {
  assert.throws(() => validateConversationRequest(payload({
    conversationHistory: Array.from(
        {length: 9}, () => ({role: "user", text: "x"})),
  })));
  assert.throws(() => validateConversationRequest(payload({
    conversationHistory: [{role: "system", text: "secret"}],
  })));
});

test("deduplicates identical bounded history without logging content", () => {
  const result = validateConversationRequest(payload({
    conversationHistory: [
      {role: "user", text: "même"},
      {role: "user", text: "même"},
    ],
  }));
  assert.deepEqual(result.conversationHistory, [
    {role: "user", text: "même"},
  ]);
});

test("refuses unknown sections, item keys and facts", () => {
  const unknownSection = payload();
  unknownSection.conversationContext.sections[0].type = "health";
  assert.throws(() => validateConversationRequest(unknownSection));

  const unknownItem = payload();
  unknownItem.conversationContext.sections[0].items = [{
    type: "event",
    confirmation: "confirmed",
    freshness: "current",
    facts: {title: "Borné"},
    raw: {},
  }];
  assert.throws(() => validateConversationRequest(unknownItem));

  const unknownFact = payload();
  unknownFact.conversationContext.sections[0].items = [{
    type: "event",
    confirmation: "confirmed",
    freshness: "current",
    facts: {medicalNotes: "interdit"},
  }];
  assert.throws(() => validateConversationRequest(unknownFact));
});

test("accepts bounded Human and explicit Relation projection", () => {
  const value = payload();
  value.message = "Quel est le prénom de mon enfant ?";
  value.conversationContext.state = "complete";
  value.conversationContext.sections = [
    {
      type: "human",
      availability: "available",
      freshness: "current",
      items: [
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-main",
            personRole: "primary",
            displayName: "Personne Test",
            birthDate: "1990-02-01",
            familyStatus: "Je vis en couple",
            workStatus: "Je suis salariée",
            status: "active",
          },
        },
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-alex",
            personRole: "related",
            displayName: "Alex",
            birthDate: "1989-04-03",
            status: "active",
          },
        },
        {
          type: "person",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            nodeId: "human:person:person-sam",
            personRole: "related",
            displayName: "Sam",
            birthDate: "2018-06-05",
            status: "active",
          },
        },
      ],
      budgetLimit: 55,
      budgetUsed: 8,
      omittedCount: 0,
      truncated: false,
    },
    {
      type: "relation",
      availability: "available",
      freshness: "current",
      items: [
        {
          type: "relation",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            kind: "humanRelation",
            relationRole: "partner",
            sourceNodeId: "human:person:person-main",
            targetNodeId: "human:person:person-alex",
          },
        },
        {
          type: "relation",
          confirmation: "confirmed",
          freshness: "current",
          facts: {
            kind: "humanRelation",
            relationRole: "child",
            sourceNodeId: "human:person:person-main",
            targetNodeId: "human:person:person-sam",
          },
        },
      ],
      budgetLimit: 50,
      budgetUsed: 4,
      omittedCount: 0,
      truncated: false,
    },
  ];
  value.conversationContext.budgetUsed = 12;

  const result = validateConversationRequest(value);
  assert.equal(result.conversationContext.sections[0].items[2]
      .facts.displayName, "Sam");
  assert.equal(result.conversationContext.sections[0].items[0]
      .facts.familyStatus, "Je vis en couple");
  assert.equal(result.conversationContext.sections[0].items[0]
      .facts.personRole, "primary");
  assert.equal(result.conversationContext.sections[0].items[0]
      .facts.workStatus, "Je suis salariée");
  assert.equal(result.conversationContext.sections[1].items[0]
      .facts.relationRole, "partner");
  assert.equal(result.conversationContext.sections[1].items[1]
      .facts.relationRole, "child");
});

test("accepts bounded relationship status and couple dates", () => {
  const value = payload();
  value.conversationContext.sections[0].items = [{
    type: "relationshipDetails",
    confirmation: "confirmed",
    freshness: "current",
    facts: {
      kind: "spouse",
      relationshipStatus: "Mariée",
      marriageDate: "2020-08-12",
      engagementDate: "2019-05-04",
    },
  }];

  const result = validateConversationRequest(value);
  const facts = result.conversationContext.sections[0].items[0].facts;
  assert.equal(facts.relationshipStatus, "Mariée");
  assert.equal(facts.marriageDate, "2020-08-12");
  assert.equal(facts.engagementDate, "2019-05-04");
});

test("refuses invalid Human dates, node IDs and relation roles", () => {
  for (const facts of [
    {birthDate: "05/06/2018"},
    {birthDate: "2026-02-30"},
    {nodeId: "private user id"},
    {relationRole: "unknownRelation"},
    {personRole: "unknownPersonRole"},
    {marriageDate: "12/08/2020"},
    {engagementDate: "2026-02-30"},
  ]) {
    const value = payload();
    value.conversationContext.sections[0].items = [{
      type: "person",
      confirmation: "confirmed",
      freshness: "current",
      facts,
    }];
    assert.throws(() => validateConversationRequest(value));
  }
});

test("refuses profile and every non-empty legacy context alias", () => {
  for (const [key, value] of [
    ["profile", {firstName: "x"}],
    ["profileContext", {human: {}}],
    ["memories", [{text: "x"}]],
    ["memoryReasoning", [{type: "x"}]],
    ["events", [{title: "x"}]],
  ]) {
    assert.throws(() => validateConversationRequest(payload({[key]: value})));
  }
});

test("refuses account, authentication and secret fields", () => {
  for (const field of ["uid", "accountScopeId", "token", "secret"]) {
    const value = payload();
    value.conversationContext.sections[0].items = [{
      type: "event",
      confirmation: "confirmed",
      freshness: "current",
      facts: {[field]: "interdit"},
    }];
    assert.throws(() => validateConversationRequest(value));
  }
});

test("refuses inconsistent budgets and excessive item counts", () => {
  const invalidBudget = payload();
  invalidBudget.conversationContext.budgetUsed = 246;
  assert.throws(() => validateConversationRequest(invalidBudget));

  const tooMany = payload();
  tooMany.conversationContext.sections[0].items = Array.from(
      {length: 41},
      () => ({
        type: "event",
        confirmation: "confirmed",
        freshness: "current",
        facts: {status: "active"},
      }),
  );
  assert.throws(() => validateConversationRequest(tooMany));
});
