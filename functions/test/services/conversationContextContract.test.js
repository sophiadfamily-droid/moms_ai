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
    message: "Bonjour",
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
