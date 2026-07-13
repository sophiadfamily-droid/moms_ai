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
  });

  assert.equal(
      Object.prototype.hasOwnProperty.call(request, "temperature"),
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
    output_text: JSON.stringify({
      reply: "C'est noté.",
      actions: [],
      memories: [],
    }),
  });

  assert.deepEqual(parsed, {
    reply: "C'est noté.",
    actions: [],
    memories: [],
  });
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
