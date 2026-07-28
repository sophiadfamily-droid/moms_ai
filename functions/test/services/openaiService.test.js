const assert = require("node:assert/strict");
const test = require("node:test");

const {
  DEFAULT_MODEL,
  RESPONSE_SCHEMA_NAME,
  buildZeliaResponseRequest,
  parseZeliaResponse,
} = require("../../services/openaiService");

const {
  zeliaResponseJsonSchema,
} = require("../../brain/zeliaResponseJsonSchema");

/**
 * Builds a valid model response fixture.
 * @param {string} visibleText Visible assistant text.
 * @return {object} Closed epistemic response.
 */
function generatedResponse(visibleText = "C'est noté.") {
  return {
    visibleText,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: "answer",
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
        projectionVersion: null,
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

test("builds a stateless Responses API request", () => {
  const request = buildZeliaResponseRequest({
    systemContent: "SYSTEM",
    userMessage: "USER",
  });

  assert.equal(request.model, DEFAULT_MODEL);
  assert.equal(request.instructions, "SYSTEM");
  assert.equal(request.input, "USER");
  assert.equal(request.store, false);
  assert.equal(request.temperature, 0.03);
  assert.equal(request.max_output_tokens, 2600);
});

test("omits temperature for GPT-5.6 models", () => {
  const request = buildZeliaResponseRequest({
    systemContent: "SYSTEM",
    userMessage: "USER",
    model: "gpt-5.6-luna",
    reasoningEffort: "none",
  });

  assert.equal(
      Object.prototype.hasOwnProperty.call(request, "temperature"),
      false,
  );
  assert.deepEqual(request.reasoning, {effort: "none"});
});

test("omits reasoning for the fallback model", () => {
  const request = buildZeliaResponseRequest({
    systemContent: "SYSTEM",
    userMessage: "USER",
    model: DEFAULT_MODEL,
    reasoningEffort: "medium",
  });

  assert.equal(
      Object.prototype.hasOwnProperty.call(request, "reasoning"),
      false,
  );
});

test("uses the strict Zelia response schema", () => {
  const request = buildZeliaResponseRequest({
    systemContent: "SYSTEM",
    userMessage: "USER",
    model: "custom-model",
  });

  assert.equal(request.model, "custom-model");
  assert.deepEqual(request.text.format, {
    type: "json_schema",
    name: RESPONSE_SCHEMA_NAME,
    strict: true,
    schema: zeliaResponseJsonSchema,
  });
});

test("parses a valid Responses API output", () => {
  const parsed = parseZeliaResponse({
    output_text: JSON.stringify(generatedResponse()),
  });

  assert.deepEqual(parsed, generatedResponse());
});

test("rejects an empty Responses API output", () => {
  assert.throws(
      () => parseZeliaResponse({output_text: ""}),
      /OPENAI_EMPTY_OUTPUT/,
  );
});

test("rejects invalid JSON output", () => {
  assert.throws(
      () => parseZeliaResponse({output_text: "not-json"}),
      /OPENAI_INVALID_JSON/,
  );
});

test("rejects a response outside the Zelia contract", () => {
  assert.throws(
      () => parseZeliaResponse({
        output_text: JSON.stringify({
          reply: "Bonjour",
        }),
      }),
      /OPENAI_INVALID_RESPONSE_CONTRACT/,
  );
});

test("allows fallback for temporary model errors", () => {
  const {
    shouldFallbackToDefaultModel,
  } = require("../../services/openaiService");

  assert.equal(
      shouldFallbackToDefaultModel(
          {status: 503, message: "Service unavailable"},
          "gpt-5.6-terra",
      ),
      true,
  );

  assert.equal(
      shouldFallbackToDefaultModel(
          {status: 400, message: "Invalid request"},
          "gpt-5.6-terra",
      ),
      false,
  );
});

test("never falls back recursively from the default model", () => {
  const {
    shouldFallbackToDefaultModel,
  } = require("../../services/openaiService");

  assert.equal(
      shouldFallbackToDefaultModel(
          {status: 503, message: "Service unavailable"},
          DEFAULT_MODEL,
      ),
      false,
  );
});

test(
    "retries once with the default model after a temporary failure",
    async () => {
      const {
        generateZeliaResponse,
      } = require("../../services/openaiService");

      const calls = [];
      const logs = [];
      const signal = new AbortController().signal;

      const client = {
        responses: {
          async create(request, options) {
            calls.push({request, options});

            if (calls.length === 1) {
              const error = new Error("Service unavailable");
              error.status = 503;
              throw error;
            }

            return {
              output_text: JSON.stringify(
                  generatedResponse("Réponse de secours"),
              ),
            };
          },
        },
      };

      const result = await generateZeliaResponse({
        apiKey: "test-key",
        systemContent: "SYSTEM",
        userMessage: "USER",
        model: "gpt-5.6-terra",
        tier: "balanced",
        reasoningEffort: "low",
        client,
        logger: {
          info: (...values) => logs.push(values),
          warn: (...values) => logs.push(values),
          error: (...values) => logs.push(values),
        },
        signal,
      });

      assert.equal(calls.length, 2);
      assert.equal(calls[0].request.model, "gpt-5.6-terra");
      assert.deepEqual(calls[0].request.reasoning, {effort: "low"});
      assert.equal(calls[1].request.model, DEFAULT_MODEL);
      assert.equal(calls[1].request.temperature, 0.03);
      assert.equal("reasoning" in calls[1].request, false);
      assert.equal(calls[0].options.signal, signal);
      assert.equal(calls[1].options.signal, signal);

      assert.deepEqual(result, generatedResponse("Réponse de secours"));
      assert.equal(JSON.stringify(logs).includes("SYSTEM"), false);
      assert.equal(JSON.stringify(logs).includes("USER"), false);
    },
);

test("logs bounded provider diagnostics without sensitive data", async () => {
  const logs = [];
  const logger = {
    info: (...values) => logs.push(values),
    error: (...values) => logs.push(values),
  };
  const client = {
    responses: {
      async create() {
        return {
          _request_id: "req_technical",
          output_text: JSON.stringify(generatedResponse()),
        };
      },
    },
  };

  const {generateZeliaResponse} = require("../../services/openaiService");
  await generateZeliaResponse({
    apiKey: "private-key",
    systemContent: "PRIVATE SYSTEM",
    userMessage: "PRIVATE USER",
    model: "gpt-5.6-sol",
    tier: "reasoning",
    reasoningEffort: "medium",
    client,
    logger,
    correlationId: "0123456789abcdef0123456789abcdef",
  });

  assert.deepEqual(logs.map((line) => line[0]), [
    "ZELIA_OPENAI_REQUEST",
    "ZELIA_OPENAI_SUCCESS",
  ]);
  assert.equal(logs[1][1].requestId, "req_technical");
  assert.equal(logs[1][1].reasoningEffort, "medium");
  assert.equal(
      logs[0][1].correlationId,
      "0123456789abcdef0123456789abcdef",
  );
  assert.equal(
      logs[1][1].correlationId,
      "0123456789abcdef0123456789abcdef",
  );
  assert.equal(typeof logs[1][1].durationMs, "number");
  const serialized = JSON.stringify(logs);
  assert.equal(serialized.includes("private-key"), false);
  assert.equal(serialized.includes("PRIVATE SYSTEM"), false);
  assert.equal(serialized.includes("PRIVATE USER"), false);
});

test("does not hide a non-retryable request error", async () => {
  const {
    generateZeliaResponse,
  } = require("../../services/openaiService");

  const calls = [];
  const logs = [];

  const client = {
    responses: {
      async create(request) {
        calls.push(request);

        const error = new Error("Unsupported parameter");
        error.status = 400;
        throw error;
      },
    },
  };

  await assert.rejects(
      () => generateZeliaResponse({
        apiKey: "test-key",
        systemContent: "SYSTEM",
        userMessage: "USER",
        model: "gpt-5.6-sol",
        tier: "reasoning",
        reasoningEffort: "medium",
        client,
        logger: {
          info: (...values) => logs.push(values),
          error: (...values) => logs.push(values),
        },
      }),
      /Unsupported parameter/,
  );

  assert.equal(calls.length, 1);
  assert.equal(logs.at(-1)[0], "ZELIA_OPENAI_ERROR");
  assert.equal(logs.at(-1)[1].status, 400);
  assert.equal(JSON.stringify(logs).includes("Unsupported parameter"), false);
});
