const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ERROR_CODES,
  createCorrelationId,
  sanitizeDiagnosticMetadata,
  writeDiagnostic,
} = require("../../services/diagnostics");

test("redacts personal, authentication, medical and unknown fields", () => {
  const safe = sanitizeDiagnosticMetadata({
    message: "conversation privée",
    prompt: "instructions privées",
    content: "réponse OpenAI",
    memory: "mémoire privée",
    profile: {name: "Person A"},
    health: "donnée médicale",
    authorization: "Bearer private-token",
    appCheckToken: "private-app-check",
    idToken: "private-id-token",
    refreshToken: "private-refresh-token",
    secret: "private-secret",
    apiKey: "private-key",
    unknown: {arbitrary: "object"},
    status: 503,
    retryable: true,
    reasoningEffort: "low",
    requestId: "req_technical",
    providerCode: "rate_limit_exceeded",
  });

  assert.deepEqual(safe, {
    status: 503,
    retryable: true,
    reasoningEffort: "low",
    requestId: "req_technical",
    providerCode: "rate_limit_exceeded",
  });
});

test("unknown objects are never serialized by default", () => {
  assert.deepEqual(sanitizeDiagnosticMetadata(new Error("private")), {});
  assert.deepEqual(sanitizeDiagnosticMetadata(["private"]), {});
});

test("NLU diagnostics accept closed non-personal codes only", () => {
  assert.deepEqual(sanitizeDiagnosticMetadata({
    normalizationCodes: ["accents_folded", "bad value", "safe_typo_corrected"],
    intentCode: "task",
    understandingLevel: "normalizedMatch",
    entityTypes: ["date", "person name"],
    ambiguityType: "negation_scope",
  }), {
    normalizationCodes: ["accents_folded", "safe_typo_corrected"],
    intentCode: "task",
    understandingLevel: "normalizedMatch",
    entityTypes: ["date"],
    ambiguityType: "negation_scope",
  });
});

test("writes only stable technical diagnostics in every environment", () => {
  for (const env of [
    {FUNCTIONS_EMULATOR: "true"},
    {ZELIA_ENVIRONMENT: "development"},
    {ZELIA_ENVIRONMENT: "production"},
  ]) {
    const lines = [];
    writeDiagnostic({
      logger: {warn: (...values) => lines.push(values)},
      level: "warn",
      event: "TEST_DIAGNOSTIC",
      component: "test_component",
      step: "test_step",
      code: ERROR_CODES.timeout,
      correlationId: "technical-correlation",
      metadata: {
        durationMs: 200,
        conversation: "ne doit pas sortir",
        token: "ne doit pas sortir",
      },
      env,
    });
    assert.equal(lines.length, 1);
    assert.equal(JSON.stringify(lines).includes("ne doit pas sortir"), false);
    assert.deepEqual(lines[0][1], {
      component: "test_component",
      step: "test_step",
      code: "timeout",
      environment: env.FUNCTIONS_EMULATOR ? "emulator" :
        env.ZELIA_ENVIRONMENT,
      correlationId: "technical-correlation",
      durationMs: 200,
    });
  }
});

test("correlation identifiers are random and contain no user identifier",
    () => {
      const first = createCorrelationId();
      const second = createCorrelationId();
      assert.notEqual(first, second);
      assert.match(first, /^[0-9a-f-]{36}$/);
      assert.equal(first.includes("firebase-uid"), false);
    });
