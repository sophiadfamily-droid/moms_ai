/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  CHAT_QUOTA_COLLECTION,
  ChatQuotaExceededError,
  consumeChatQuota,
  resolveChatQuotaConfig,
} = require("../../services/chatQuotaService");

class FakeFirestore {
  constructor() {
    this.documents = new Map();
    this.queue = Promise.resolve();
  }

  collection(name) {
    return {doc: (id) => ({path: `${name}/${id}`})};
  }

  runTransaction(callback) {
    const operation = this.queue.then(async () => {
      const transaction = {
        get: async (reference) => ({
          exists: this.documents.has(reference.path),
          data: () => this.documents.get(reference.path),
        }),
        set: (reference, value) => {
          this.documents.set(reference.path, structuredClone(value));
        },
      };
      return callback(transaction);
    });
    this.queue = operation.catch(() => {});
    return operation;
  }
}

test("uses bounded configurable quota values", () => {
  assert.deepEqual(resolveChatQuotaConfig({
    ZELIA_AI_CHAT_QUOTA_LIMIT: "4",
    ZELIA_AI_CHAT_QUOTA_WINDOW_SECONDS: "20",
  }), {limit: 4, windowMs: 20000});
  assert.deepEqual(resolveChatQuotaConfig({
    ZELIA_AI_CHAT_QUOTA_LIMIT: "0",
    ZELIA_AI_CHAT_QUOTA_WINDOW_SECONDS: "invalid",
  }), {limit: 30, windowMs: 60000});
});

test("stores technical counters in one server document", async () => {
  const firestore = new FakeFirestore();
  const result = await consumeChatQuota({
    firestore,
    uid: "anonymous-user",
    now: () => 1000,
    env: {ZELIA_AI_CHAT_QUOTA_LIMIT: "2"},
  });

  assert.deepEqual(result, {remaining: 1});
  assert.deepEqual(
      firestore.documents.get(`${CHAT_QUOTA_COLLECTION}/anonymous-user`),
      {windowStartedAtMs: 1000, count: 1, updatedAtMs: 1000},
  );
});

test("concurrent requests cannot exceed the server quota", async () => {
  const firestore = new FakeFirestore();
  const attempts = Array.from({length: 8}, () => consumeChatQuota({
    firestore,
    uid: "same-user",
    now: () => 1000,
    env: {ZELIA_AI_CHAT_QUOTA_LIMIT: "3"},
  }));

  const settled = await Promise.allSettled(attempts);
  assert.equal(settled.filter((item) => item.status === "fulfilled").length, 3);
  const failures = settled.filter((item) => item.status === "rejected");
  assert.equal(failures.length, 5);
  assert.ok(failures.every((item) =>
    item.reason instanceof ChatQuotaExceededError));
});

test("starts a fresh window without accumulating documents", async () => {
  const firestore = new FakeFirestore();
  const env = {
    ZELIA_AI_CHAT_QUOTA_LIMIT: "1",
    ZELIA_AI_CHAT_QUOTA_WINDOW_SECONDS: "10",
  };
  await consumeChatQuota({firestore, uid: "uid", now: () => 1000, env});
  const result = await consumeChatQuota({
    firestore,
    uid: "uid",
    now: () => 11000,
    env,
  });

  assert.deepEqual(result, {remaining: 0});
  assert.equal(firestore.documents.size, 1);
});
