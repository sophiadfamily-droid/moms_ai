const assert = require("node:assert/strict");
const test = require("node:test");

const {
  OPENAI_TIMEOUT_MS,
  handleChatRequest,
  runWithOpenAiDeadline,
} = require("../../services/chatRequestHandler");
const {generateZeliaResponse} = require("../../services/openaiService");

const payload = {
  message: "Ajoute du lait aux courses",
  profile: {firstName: "Sophie"},
  profileContext: {work: {}},
  memories: [{text: "Routine"}],
  memoryReasoning: [{type: "routine"}],
  events: [{title: "École"}],
};

test("uses a 22 second total OpenAI deadline", () => {
  assert.equal(OPENAI_TIMEOUT_MS, 22000);
});

test("handles the legacy payload without mutating it", async () => {
  const original = structuredClone(payload);
  const calls = [];

  const result = await handleChatRequest(payload, {}, {
    apiKey: "test-key",
    now: () => new Date("2026-07-20T10:00:00.000Z"),
    env: {ZELIA_MODEL_FAST: "test-fast"},
    logger: {info() {}},
    generateResponse: async (request) => {
      calls.push(request);
      return {
        reply: "C'est noté.",
        actions: [{type: "shopping", title: "Lait"}],
        memories: [],
      };
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
  });
});

test("preserves legacy defaults for missing fields", async () => {
  const result = await handleChatRequest({}, {}, {
    apiKey: "test-key",
    now: () => new Date("2026-07-20T10:00:00.000Z"),
    logger: {info() {}},
    generateResponse: async ({userMessage}) => {
      assert.equal(userMessage, "");
      return {reply: "", actions: null, memories: null};
    },
  });

  assert.deepEqual(result, {
    reply: "C'est noté 💕",
    actions: [],
    memories: [],
  });
});

test(
    "keeps only a participant literally present in the user message",
    async () => {
      const explicit = await handleChatRequest({
        message: "Ajoute un rendez-vous avec Person A",
      }, {}, {
        now: () => new Date("2026-07-20T10:00:00.000Z"),
        logger: {info() {}},
        generateResponse: async () => ({
          reply: "D'accord",
          actions: [{
            type: "event",
            title: "Rendez-vous",
            participant: {
              label: "Person A",
              entityType: "person",
              evidence: "explicit_user_input",
            },
          }],
          memories: [],
        }),
      });
      assert.equal(explicit.actions[0].participant.label, "Person A");

      const invented = await handleChatRequest(
          {message: "Ajoute un rendez-vous"},
          {},
          {
            now: () => new Date("2026-07-20T10:00:00.000Z"),
            logger: {info() {}},
            generateResponse: async () => explicit,
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
              output_text: JSON.stringify({
                reply: "Réponse de secours",
                actions: [],
                memories: [],
              }),
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

      assert.equal(result.reply, "Réponse de secours");
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
