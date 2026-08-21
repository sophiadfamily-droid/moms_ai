const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createCallableAccountDataHandler,
  exportAccountData,
  jsonSafe,
  validatePayload,
} = require("../../services/accountDataLifecycleService");

/** Minimal callable error used by the unit tests. */
class FakeHttpsError extends Error {
  /**
   * @param {string} code Callable error code.
   * @param {string} message Safe public message.
   */
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const appCheck = {value: () => true};
const production = {ZELIA_ENVIRONMENT: "production"};

test("accepts only the closed export and confirmed delete contracts", () => {
  assert.deepEqual(
      validatePayload({schemaVersion: 1, operation: "export"}),
      {operation: "export"},
  );
  assert.deepEqual(
      validatePayload({
        schemaVersion: 1,
        operation: "delete",
        confirmation: "SUPPRIMER",
      }),
      {operation: "delete"},
  );
  assert.throws(() => validatePayload({
    schemaVersion: 1,
    operation: "delete",
    confirmation: "oui",
  }));
  assert.throws(() => validatePayload({
    schemaVersion: 1,
    operation: "export",
    uid: "forbidden",
  }));
});

test("serializes Firestore-like values without losing their meaning", () => {
  const date = new Date("2026-08-21T10:00:00.000Z");
  assert.deepEqual(jsonSafe({
    timestamp: {toDate: () => date},
    point: {latitude: 48.8, longitude: 2.3},
    bytes: Buffer.from("Zelia"),
  }), {
    timestamp: date.toISOString(),
    point: {type: "geoPoint", latitude: 48.8, longitude: 2.3},
    bytes: {type: "bytes", base64: "WmVsaWE="},
  });
});

test("exports a wide nested tree in bounded parallel batches", async () => {
  let activeCollections = 0;
  let peakCollections = 0;
  const childrenByPath = new Map();

  const makeSnapshot = (reference, data) => ({
    exists: true,
    ref: reference,
    data: () => data,
  });
  const makeReference = (path, data) => ({
    path,
    get: async function() {
      return makeSnapshot(this, data);
    },
    listCollections: async function() {
      const children = childrenByPath.get(path) || [];
      if (children.length === 0) return [];
      return [{
        get: async () => {
          activeCollections += 1;
          peakCollections = Math.max(peakCollections, activeCollections);
          await new Promise((resolve) => setTimeout(resolve, 2));
          activeCollections -= 1;
          return {docs: children.map((child) =>
            makeSnapshot(child.reference, child.data))};
        },
      }];
    },
  });

  const root = makeReference("users/account", {profile: true});
  const firstLevel = Array.from({length: 48}, (_, index) => {
    const path = `users/account/items/${index.toString().padStart(2, "0")}`;
    return {
      reference: makeReference(path, {index}),
      data: {index},
    };
  });
  childrenByPath.set(root.path, firstLevel);
  for (const item of firstLevel) {
    const childPath = `${item.reference.path}/details/value`;
    childrenByPath.set(item.reference.path, [{
      reference: makeReference(childPath, {parent: item.data.index}),
      data: {parent: item.data.index},
    }]);
  }

  const quotaReference = {
    get: async () => ({exists: false}),
  };
  const firestore = {
    collection: (name) => name === "users" ? {
      doc: () => root,
    } : {
      doc: () => quotaReference,
    },
  };

  const result = await exportAccountData({
    firestore,
    uid: "account",
  });

  assert.equal(result.documents.length, 97);
  assert.equal(result.documents[0].path, ".");
  assert.ok(peakCollections > 1);
  assert.deepEqual(
      result.documents.map((item) => item.path),
      [...result.documents.map((item) => item.path)].sort(),
  );
});

test("binds export and deletion exclusively to verified auth", async () => {
  const calls = [];
  const handler = createCallableAccountDataHandler({
    firestore: {},
    exportData: async ({uid}) => {
      calls.push(["export", uid]);
      return {schemaVersion: 1, documents: []};
    },
    deleteData: async ({uid}) => calls.push(["delete", uid]),
    HttpsErrorClass: FakeHttpsError,
    appCheckEnforcement: appCheck,
    env: production,
    logger: {error: () => {}},
  });

  const exported = await handler({
    auth: {uid: "verified", token: {}},
    app: {appId: "verified-app"},
    data: {schemaVersion: 1, operation: "export"},
  });
  assert.equal(exported.operation, "export");
  await handler({
    auth: {uid: "verified", token: {}},
    app: {appId: "verified-app"},
    data: {
      schemaVersion: 1,
      operation: "delete",
      confirmation: "SUPPRIMER",
    },
  });
  assert.deepEqual(calls, [["export", "verified"], ["delete", "verified"]]);

  await assert.rejects(
      handler({data: {schemaVersion: 1, operation: "export"}}),
      (error) => error.code === "unauthenticated",
  );
  await assert.rejects(
      handler({
        auth: {uid: "verified", token: {}},
        data: {schemaVersion: 1, operation: "export"},
      }),
      (error) => error.code === "failed-precondition",
  );
});
