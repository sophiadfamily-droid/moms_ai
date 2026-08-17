/* eslint-disable require-jsdoc */
const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createCallableScheduleDocumentHandler,
  safeProviderDiagnostic,
  validateScheduleDocumentPayload,
} = require("../../services/structuredScheduleDocumentTransport");

const appCheckEnabled = {value: () => true};

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function pdfBase64() {
  return Buffer.from("%PDF-1.7\nplanning").toString("base64");
}

function payload() {
  return {
    schemaVersion: 1,
    documentKind: "pdf",
    mimeType: "application/pdf",
    fileBase64: pdfBase64(),
    subjectEntityId: "child-1",
    subjectLabel: "Kassim",
  };
}

function request(data = payload()) {
  return {
    data,
    auth: {uid: "firebase-uid"},
    app: {appId: "verified-app"},
  };
}

function handler(overrides = {}) {
  return createCallableScheduleDocumentHandler({
    analyzeDocument: async () => ({schemaVersion: 1, proposals: []}),
    getApiKey: () => "test-key",
    consumeQuota: async () => ({remaining: 2}),
    HttpsErrorClass: FakeHttpsError,
    appCheckEnforcement: appCheckEnabled,
    env: {ZELIA_ENVIRONMENT: "production"},
    logger: {error() {}},
    ...overrides,
  });
}

test("validates a real PDF signature and profile context", () => {
  const validated = validateScheduleDocumentPayload(payload());
  assert.equal(validated.documentKind, "pdf");
  assert.equal(validated.subject.entityId, "child-1");
  assert.equal(validated.subject.label, "Kassim");
});

test("rejects spoofed identity, MIME and binary signatures", () => {
  assert.throws(
      () => validateScheduleDocumentPayload({...payload(), uid: "spoofed"}),
      /IDENTITY_FORBIDDEN/,
  );
  assert.throws(
      () => validateScheduleDocumentPayload({
        ...payload(),
        fileBase64: Buffer.from("not a pdf").toString("base64"),
      }),
      /SIGNATURE_INVALID/,
  );
  assert.throws(
      () => validateScheduleDocumentPayload({
        ...payload(), mimeType: "image/heic",
      }),
      /ENCODING_INVALID/,
  );
});

test("requires authentication and verified App Check", async () => {
  await assert.rejects(
      () => handler()({...request(), auth: undefined}),
      (error) => error.code === "unauthenticated",
  );
  await assert.rejects(
      () => handler()({...request(), app: undefined}),
      (error) => error.code === "failed-precondition",
  );
});

test("passes only validated data and server key to analysis", async () => {
  const calls = [];
  const result = {schemaVersion: 1, importId: "import-1", proposals: []};
  const response = await handler({
    analyzeDocument: async (value) => {
      calls.push(value);
      return result;
    },
  })(request());

  assert.deepEqual(response, result);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].apiKey, "test-key");
  assert.equal(calls[0].subject.entityId, "child-1");
  assert.equal("uid" in calls[0], false);
});

test("logs safe provider metadata without leaking its message", async () => {
  const logs = [];
  const providerError = Object.assign(new Error("secret document contents"), {
    status: 400,
    code: "invalid_json_schema",
    type: "invalid_request_error",
    param: "text.format.schema.properties[secret] !",
    request_id: "req_123",
  });

  await assert.rejects(
      () => handler({
        analyzeDocument: async () => {
          throw providerError;
        },
        logger: {error: (...values) => logs.push(values)},
      })(request()),
      (error) => error.code === "internal",
  );

  assert.equal(logs.length, 1);
  assert.equal(logs[0][1].providerStatus, 400);
  assert.equal(logs[0][1].providerCode, "invalid_json_schema");
  assert.equal(logs[0][1].providerParam.includes(" "), false);
  assert.equal(
      JSON.stringify(logs).includes("secret document contents"),
      false,
  );
});

test("sanitizes optional provider diagnostics", () => {
  assert.deepEqual(safeProviderDiagnostic({
    status: 429,
    code: "rate_limit_exceeded",
    requestId: "req-456",
  }), {
    providerStatus: 429,
    providerCode: "rate_limit_exceeded",
    providerRequestId: "req-456",
  });
});
