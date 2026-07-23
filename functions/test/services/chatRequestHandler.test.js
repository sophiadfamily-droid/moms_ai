const assert = require("node:assert/strict");
const test = require("node:test");

const {
  OPENAI_TIMEOUT_MS,
  handleChatRequest,
  runWithOpenAiDeadline,
} = require("../../services/chatRequestHandler");
const {generateZeliaResponse} = require("../../services/openaiService");

/**
 * Builds a canonical bounded conversation request fixture.
 * @param {string} message Visible user message.
 * @return {object} Canonical request.
 */
function request(message = "Ajoute du lait aux courses") {
  return {
    schemaVersion: 2,
    message,
    sessionGeneration: 0,
    conversationContext: {
      schemaVersion: 1,
      projectionVersion: 1,
      purpose: "conversation.transport.v1",
      generatedAt: "2026-07-20T10:00:00.000Z",
      state: "complete",
      sections: [],
      budgetRequested: 245,
      budgetUsed: 0,
      omittedCount: 0,
      truncatedSections: [],
      warningCodes: [],
      redactionVersion: 1,
    },
    conversationHistory: [],
    profile: {},
    profileContext: {},
    memories: [],
    memoryReasoning: [],
    events: [],
  };
}

const payload = request();

/**
 * Builds a valid model response fixture.
 * @param {string} visibleText Visible assistant text.
 * @param {Array<object>} actions Structured actions.
 * @return {object} Closed epistemic response.
 */
function response(visibleText, actions = []) {
  return {
    visibleText,
    actions,
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: actions.length > 0 ? "actionProposal" : "answer",
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
      responseId: "response-test",
    },
  };
}

test("uses a 22 second total OpenAI deadline", () => {
  assert.equal(OPENAI_TIMEOUT_MS, 22000);
});

test("handles the canonical bounded payload without mutating it", async () => {
  const original = structuredClone(payload);
  const calls = [];

  const result = await handleChatRequest(payload, {uid: "test-uid"}, {
    apiKey: "test-key",
    now: () => new Date("2026-07-20T10:00:00.000Z"),
    env: {ZELIA_MODEL_FAST: "test-fast"},
    logger: {info() {}},
    generateResponse: async (request) => {
      calls.push(request);
      return response("C'est noté.", [{type: "shopping", title: "Lait"}]);
    },
  });

  assert.deepEqual(payload, original);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].apiKey, "test-key");
  assert.equal(calls[0].userMessage, payload.message);
  assert.equal(calls[0].model, "test-fast");
  assert.ok(calls[0].signal instanceof AbortSignal);
  assert.deepEqual(result, {
    reply: "C'est noté.",
    actions: [{type: "shopping", title: "Lait"}],
    memories: [],
    epistemic: response("x", [{type: "shopping", title: "Lait"}]).epistemic,
  });
});

test("rejects missing canonical fields", async () => {
  await assert.rejects(
      () => handleChatRequest({}, {uid: "test-uid"}),
      /conversation_request_invalid/,
  );
});

test(
    "keeps only a participant literally present in the user message",
    async () => {
      const explicit = await handleChatRequest(
          request("Ajoute un rendez-vous avec Person A"),
          {uid: "test-uid"}, {
            now: () => new Date("2026-07-20T10:00:00.000Z"),
            logger: {info() {}},
            generateResponse: async () => response("D'accord", [{
              type: "event",
              title: "Rendez-vous",
              date: "2026-07-25",
              time: "10:00",
              durationMinutes: 30,
              participant: {
                label: "Person A",
                entityType: "person",
                evidence: "explicit_user_input",
              },
            }]),
          });
      assert.equal(explicit.actions[0].participant.label, "Person A");

      const invented = await handleChatRequest(
          request("Ajoute un rendez-vous"),
          {uid: "test-uid"},
          {
            now: () => new Date("2026-07-20T10:00:00.000Z"),
            logger: {info() {}},
            generateResponse: async () => response("D'accord", [{
              type: "event",
              title: "Rendez-vous",
              date: "2026-07-25",
              time: "10:00",
              durationMinutes: 30,
              participant: {
                label: "Person A",
                entityType: "person",
                evidence: "explicit_user_input",
              },
            }]),
          },
      );
      assert.equal("participant" in invented.actions[0], false);
    },
);

test(
    "aborts and rejects the whole OpenAI operation at its deadline",
    async () => {
      let receivedSignal;

      await assert.rejects(
          () => runWithOpenAiDeadline((signal) => {
            receivedSignal = signal;
            return new Promise(() => {});
          }, 5),
          /OPENAI_TIMEOUT/,
      );

      assert.equal(receivedSignal.aborted, true);
    },
);

test(
    "uses one deadline and cleans it after real fallback success",
    async () => {
      const scheduled = [];
      const cleared = [];
      const timers = {
        setTimeout(callback, timeoutMs) {
          const token = {callback, timeoutMs};
          scheduled.push(token);
          return token;
        },
        clearTimeout(token) {
          cleared.push(token);
        },
      };
      const attempts = [];
      const client = {
        responses: {
          async create(request, options) {
            attempts.push({request, signal: options.signal});
            if (attempts.length === 1) {
              const error = new Error("Service unavailable");
              error.status = 503;
              throw error;
            }
            return {
              output_text: JSON.stringify(response("Réponse de secours")),
            };
          },
        },
      };

      const result = await runWithOpenAiDeadline(
          (signal) => generateZeliaResponse({
            apiKey: "test-key",
            systemContent: "SYSTEM",
            userMessage: "USER",
            model: "gpt-5.6-terra",
            client,
            signal,
          }),
          OPENAI_TIMEOUT_MS,
          timers,
      );

      assert.equal(result.visibleText, "Réponse de secours");
      assert.equal(scheduled.length, 1);
      assert.equal(scheduled[0].timeoutMs, OPENAI_TIMEOUT_MS);
      assert.equal(cleared.length, 1);
      assert.equal(cleared[0], scheduled[0]);
      assert.ok(attempts[0].signal instanceof AbortSignal);
      assert.equal(attempts[1].signal, attempts[0].signal);
    },
);

test("cleans the single deadline after real OpenAI failure", async () => {
  const scheduled = [];
  const cleared = [];
  const timers = {
    setTimeout(callback, timeoutMs) {
      const token = {callback, timeoutMs};
      scheduled.push(token);
      return token;
    },
    clearTimeout(token) {
      cleared.push(token);
    },
  };
  const client = {
    responses: {
      async create() {
        const error = new Error("Invalid request");
        error.status = 400;
        throw error;
      },
    },
  };

  await assert.rejects(
      () => runWithOpenAiDeadline(
          (signal) => generateZeliaResponse({
            apiKey: "test-key",
            systemContent: "SYSTEM",
            userMessage: "USER",
            model: "gpt-5.6-terra",
            client,
            signal,
          }),
          OPENAI_TIMEOUT_MS,
          timers,
      ),
      /Invalid request/,
  );

  assert.equal(scheduled.length, 1);
  assert.equal(cleared.length, 1);
  assert.equal(cleared[0], scheduled[0]);
});
