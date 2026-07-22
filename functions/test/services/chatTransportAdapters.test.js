/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  createCallableChatHandler,
  createCallableFunctionOptions,
  OPENAI_API_KEY_NAME,
} = require("../../services/chatTransportAdapters");

const response = {reply: "Réponse", actions: [], memories: []};

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
    env: {ZELIA_ENVIRONMENT: "production"},
    ...overrides,
  });
}

function secureRequest(data = {message: "Bonjour"}) {
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
  const secret = {name: OPENAI_API_KEY_NAME};
  assert.deepEqual(createCallableFunctionOptions(secret, {
    ZELIA_ENVIRONMENT: "production",
  }), {
    region: "us-central1",
    secrets: [secret],
    timeoutSeconds: 25,
    enforceAppCheck: true,
  });
  assert.equal(createCallableFunctionOptions(secret, {
    FUNCTIONS_EMULATOR: "true",
  }).enforceAppCheck, false);
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

test("rejects absent App Check in production but allows emulator", async () => {
  await assert.rejects(
      () => createHandler()({...secureRequest(), app: undefined}),
      (error) => error.code === "failed-precondition",
  );

  const emulatorHandler = createHandler({
    env: {FUNCTIONS_EMULATOR: "true"},
  });
  assert.deepEqual(
      await emulatorHandler({...secureRequest(), app: undefined}),
      response,
  );
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
          message: "Bonjour",
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
  assert.deepEqual(logs, [[
    "ZELIA_CHAT_FAILURE",
    {code: "chat_processing_failed"},
  ]]);
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
