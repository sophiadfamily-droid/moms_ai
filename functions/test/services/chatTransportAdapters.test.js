/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  CALLABLE_TIMEOUT_SECONDS,
  createCallableChatHandler,
  createCallableFunctionOptions,
  OPENAI_API_KEY_NAME,
} = require("../../services/chatTransportAdapters");

const response = {reply: "Réponse", actions: [], memories: []};
const appCheckEnabled = {value: () => true};
const appCheckDisabled = {value: () => false};

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function createHandler(overrides = {}) {
  return createCallableChatHandler({
    handleChatRequest: async () => response,
    getApiKey: () => "test-key",
    consumeQuota: async () => ({remaining: 2}),
    HttpsErrorClass: FakeHttpsError,
    logger: {error() {}},
    appCheckEnforcement: appCheckEnabled,
    env: {ZELIA_ENVIRONMENT: "production"},
    ...overrides,
  });
}

function validPayload(message = "Bonjour") {
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
    autonomyPolicyVersion: 1,
    autonomyMode: "suggestions",
    allowedStructuredResponseKinds: [
      "answer", "answerWithCaveat", "clarificationRequired",
      "confirmationRequired", "actionProposal", "cannotDetermine",
      "contextUnavailable", "unsupportedRequest", "safeFailure",
    ],
  };
}

function secureRequest(data = validPayload()) {
  return {
    data,
    auth: {
      uid: "firebase-uid",
      token: {firebase: {sign_in_provider: "password"}},
    },
    app: {appId: "verified-app"},
  };
}

test("provides fail-closed production callable options", () => {
  assert.equal(CALLABLE_TIMEOUT_SECONDS, 60);
  const secret = {name: OPENAI_API_KEY_NAME};
  const enabledOptions = createCallableFunctionOptions(
      secret,
      appCheckEnabled,
  );
  assert.deepEqual(enabledOptions, {
    region: "us-central1",
    secrets: [secret],
    timeoutSeconds: 60,
    enforceAppCheck: appCheckEnabled,
  });
  assert.equal(enabledOptions.enforceAppCheck.value(), true);
  assert.equal(createCallableFunctionOptions(
      secret,
      appCheckDisabled,
  ).enforceAppCheck.value(), false);
});

test("accepts permanent and anonymous Firebase users", async () => {
  const contexts = [];
  const handler = createHandler({
    handleChatRequest: async (_, context) => {
      contexts.push(context);
      return response;
    },
  });

  await handler(secureRequest());
  await handler({
    ...secureRequest(),
    auth: {uid: "anonymous-uid", token: {
      firebase: {sign_in_provider: "anonymous"},
    }},
  });

  assert.deepEqual(contexts, [
    {uid: "firebase-uid"},
    {uid: "anonymous-uid"},
  ]);
});

test("rejects missing authentication before orchestration", async () => {
  let quotaCalls = 0;
  let handlerCalls = 0;
  const handler = createHandler({
    consumeQuota: async () => quotaCalls++,
    handleChatRequest: async () => {
      handlerCalls++;
      return response;
    },
  });

  await assert.rejects(
      () => handler({...secureRequest(), auth: undefined}),
      (error) => error.code === "unauthenticated",
  );
  assert.equal(quotaCalls, 0);
  assert.equal(handlerCalls, 0);
});

test("rejects absent App Check when enforcement is enabled", async () => {
  await assert.rejects(
      () => createHandler()({...secureRequest(), app: undefined}),
      (error) => error.code === "failed-precondition",
  );
});

test("disabled App Check still requires auth and consumes quota", async () => {
  const quotaUids = [];
  let handlerCalls = 0;
  const handler = createHandler({
    appCheckEnforcement: appCheckDisabled,
    consumeQuota: async ({uid}) => quotaUids.push(uid),
    handleChatRequest: async () => {
      handlerCalls++;
      return response;
    },
  });

  assert.deepEqual(
      await handler({...secureRequest(), app: undefined}),
      response,
  );
  assert.deepEqual(quotaUids, ["firebase-uid"]);
  assert.equal(handlerCalls, 1);

  await assert.rejects(
      () => handler({
        ...secureRequest(),
        auth: undefined,
        app: undefined,
      }),
      (error) => error.code === "unauthenticated",
  );
  assert.deepEqual(quotaUids, ["firebase-uid"]);
  assert.equal(handlerCalls, 1);
});

test("rejects an invalid App Check context in production", async () => {
  await assert.rejects(
      () => createHandler()({...secureRequest(), app: {}}),
      (error) => error.code === "failed-precondition",
  );
});

test("rejects client-controlled identity fields", async () => {
  for (const field of ["uid", "userId", "accountId"]) {
    await assert.rejects(
        () => createHandler()(secureRequest({
          ...validPayload(),
          [field]: "x",
        })),
        (error) => error.code === "invalid-argument",
    );
  }
});

test("binds quota and orchestration exclusively to verified UID", async () => {
  const quotaUids = [];
  const contexts = [];
  const handler = createHandler({
    consumeQuota: async ({uid}) => quotaUids.push(uid),
    handleChatRequest: async (_, context) => {
      contexts.push(context);
      return response;
    },
  });

  await handler(secureRequest());
  assert.deepEqual(quotaUids, ["firebase-uid"]);
  assert.deepEqual(contexts, [{uid: "firebase-uid"}]);
});

test("maps quota exhaustion to a stable safe error", async () => {
  const handler = createHandler({
    consumeQuota: async () => {
      const error = new Error("private quota detail");
      error.code = "chat_quota_exceeded";
      throw error;
    },
  });

  await assert.rejects(
      () => handler(secureRequest()),
      (error) => error.code === "resource-exhausted" &&
        !error.message.includes("private"),
  );
});

test("logs only a stable code for OpenAI failures", async () => {
  const logs = [];
  const handler = createHandler({
    handleChatRequest: async () => {
      throw new Error("private conversation and provider detail");
    },
    logger: {error: (...values) => logs.push(values)},
  });

  await assert.rejects(
      () => handler(secureRequest()),
      (error) => error.code === "internal" &&
        !error.message.includes("private"),
  );
  assert.equal(logs.length, 1);
  assert.equal(logs[0][0], "ZELIA_CHAT_FAILURE");
  assert.deepEqual({
    ...logs[0][1],
    correlationId: "redacted-for-test",
  }, {
    component: "chat_transport",
    step: "request",
    code: "service-unavailable",
    environment: "production",
    correlationId: "redacted-for-test",
  });
  assert.equal(JSON.stringify(logs).includes("private"), false);
});

test("rejects malformed payload before quota", async () => {
  let quotaCalls = 0;
  const handler = createHandler({
    consumeQuota: async () => quotaCalls++,
  });
  await assert.rejects(
      () => handler(secureRequest("invalid")),
      (error) => error.code === "invalid-argument",
  );
  assert.equal(quotaCalls, 0);
});

test("legacy HTTP transport is no longer exported", () => {
  const source = fs.readFileSync(
      path.resolve(__dirname, "../../index.js"),
      "utf8",
  );
  assert.doesNotMatch(source, /chatWithZeliaHttp|onRequest/);
  assert.match(source, /chatWithZeliaCallable/);
});
