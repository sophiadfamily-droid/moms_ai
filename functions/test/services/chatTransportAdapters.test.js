/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createCallableChatHandler,
  createCallableFunctionOptions,
  createHttpChatHandler,
  OPENAI_API_KEY_NAME,
} = require("../../services/chatTransportAdapters");
const {handleChatRequest} = require("../../services/chatRequestHandler");

test("provides the production callable Function configuration", () => {
  const secret = {name: OPENAI_API_KEY_NAME};

  assert.equal(OPENAI_API_KEY_NAME, "OPENAI_API_KEY");
  assert.deepEqual(createCallableFunctionOptions(secret), {
    region: "us-central1",
    secrets: [secret],
    timeoutSeconds: 25,
    enforceAppCheck: false,
  });
});

const response = {
  reply: "Réponse",
  actions: [{type: "task", title: "Appeler"}],
  memories: [{text: "Préfère le matin"}],
};

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function createResponseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

test("HTTP and callable adapters return the same shared result", async () => {
  const calls = [];
  const shared = async (payload, context, dependencies) => {
    calls.push({payload, context, dependencies});
    return response;
  };
  const getApiKey = () => "test-key";
  const httpHandler = createHttpChatHandler({
    handleChatRequest: shared,
    getApiKey,
  });
  const callableHandler = createCallableChatHandler({
    handleChatRequest: shared,
    getApiKey,
    HttpsErrorClass: FakeHttpsError,
  });
  const payload = {message: "Bonjour"};
  const res = createResponseRecorder();

  await httpHandler({body: payload}, res);
  const callableResult = await callableHandler({
    data: payload,
    auth: undefined,
    app: undefined,
  });

  assert.deepEqual(res.body, response);
  assert.deepEqual(callableResult, response);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].payload, payload);
  assert.equal(calls[1].payload, payload);
  assert.equal(calls[0].dependencies.apiKey, "test-key");
  assert.equal(calls[1].dependencies.apiKey, "test-key");
});

test("real orchestration preserves HTTP/callable parity", async () => {
  const completePayload = {
    message: "Ajoute du lait aux courses",
    profile: {firstName: "Sophie"},
    profileContext: {work: {status: "active"}},
    memories: [{text: "Préfère le matin"}],
    memoryReasoning: [{type: "preference"}],
    events: [{title: "École"}],
  };
  const originalPayload = structuredClone(completePayload);
  const generated = {
    reply: "C'est noté.",
    actions: [{type: "shopping", title: "Lait"}],
    memories: [{text: "Achète du lait"}],
  };
  const invocationCounts = {http: 0, callable: 0};
  const handlerDependencies = {
    now: () => new Date("2026-07-20T10:00:00.000Z"),
    logger: {info() {}},
    generateResponse: async () => generated,
  };
  const createCountedHandler = (transport) => async (...args) => {
    invocationCounts[transport] += 1;
    return handleChatRequest(...args);
  };
  const httpHandler = createHttpChatHandler({
    handleChatRequest: createCountedHandler("http"),
    getApiKey: () => "test-key",
    handlerDependencies,
  });
  const callableHandler = createCallableChatHandler({
    handleChatRequest: createCountedHandler("callable"),
    getApiKey: () => "test-key",
    handlerDependencies,
    HttpsErrorClass: FakeHttpsError,
  });
  const httpResponse = createResponseRecorder();

  await httpHandler({body: completePayload}, httpResponse);
  const callableResponse = await callableHandler({data: completePayload});

  assert.deepEqual(httpResponse.body, generated);
  assert.deepEqual(callableResponse, generated);
  assert.deepEqual(httpResponse.body.actions, generated.actions);
  assert.deepEqual(httpResponse.body.memories, generated.memories);
  assert.equal(invocationCounts.http, 1);
  assert.equal(invocationCounts.callable, 1);
  assert.deepEqual(completePayload, originalPayload);
});

test("callable accepts missing authentication during migration", async () => {
  let context;
  const handler = createCallableChatHandler({
    handleChatRequest: async (payload, receivedContext) => {
      context = receivedContext;
      return response;
    },
    getApiKey: () => "test-key",
    HttpsErrorClass: FakeHttpsError,
  });

  await handler({data: {message: "Bonjour"}});

  assert.deepEqual(context, {auth: undefined, app: undefined});
});

test("callable rejects a malformed payload before orchestration", async () => {
  let callCount = 0;
  const handler = createCallableChatHandler({
    handleChatRequest: async () => {
      callCount += 1;
      return response;
    },
    getApiKey: () => "test-key",
    HttpsErrorClass: FakeHttpsError,
  });

  await assert.rejects(
      () => handler({data: "invalid"}),
      (error) => error.code === "invalid-argument",
  );
  assert.equal(callCount, 0);
});

test("HTTP preserves its safe 500 response", async () => {
  const res = createResponseRecorder();
  const handler = createHttpChatHandler({
    handleChatRequest: async () => {
      throw new Error("private detail");
    },
    getApiKey: () => "test-key",
    logger: {error() {}},
  });

  await handler({body: {}}, res);

  assert.equal(res.statusCode, 500);
  assert.deepEqual(res.body, {
    reply: "Je rencontre un petit souci 💕",
    actions: [],
    memories: [],
  });
});

test("callable maps failures to a safe internal error", async () => {
  const handler = createCallableChatHandler({
    handleChatRequest: async () => {
      throw new Error("private detail");
    },
    getApiKey: () => "test-key",
    logger: {error() {}},
    HttpsErrorClass: FakeHttpsError,
  });

  await assert.rejects(
      () => handler({data: {}}),
      (error) =>
        error.code === "internal" &&
        !error.message.includes("private detail"),
  );
});
