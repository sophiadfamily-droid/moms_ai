const {HttpsError} = require("firebase-functions/v2/https");

const {
  resolveSecurityPolicy,
  zeliaEnforceAppCheck,
} = require("./securityEnvironment");

const ACCOUNT_EXPORT_SCHEMA_VERSION = 1;
const DELETE_CONFIRMATION = "SUPPRIMER";
const MAX_EXPORT_DOCUMENTS = 5000;
const MAX_EXPORT_BYTES = 7 * 1024 * 1024;
const EXPORT_TRAVERSAL_BATCH_SIZE = 24;
const CHAT_QUOTA_COLLECTION = "__server_ai_chat_quota";

/**
 * Converts Firestore values into a stable JSON-compatible representation.
 * @param {*} value Firestore value.
 * @return {*} JSON-compatible value.
 */
function jsonSafe(value) {
  if (value == null || typeof value === "string" ||
      typeof value === "boolean" || typeof value === "number") {
    return value;
  }
  if (Array.isArray(value)) return value.map(jsonSafe);
  if (Buffer.isBuffer(value)) {
    return {type: "bytes", base64: value.toString("base64")};
  }
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (typeof value.latitude === "number" &&
      typeof value.longitude === "number") {
    return {
      type: "geoPoint",
      latitude: value.latitude,
      longitude: value.longitude,
    };
  }
  if (typeof value.path === "string" && value.firestore) {
    return {type: "documentReference", path: value.path};
  }
  if (typeof value === "object") {
    return Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, jsonSafe(item)]),
    );
  }
  return String(value);
}

/**
 * Recursively collects one account document tree.
 * @param {*} reference Firestore document reference.
 * @param {string} rootPath Root path removed from exported paths.
 * @param {!Array<!Object>} records Accumulated records.
 * @return {!Promise<void>}
 */
async function collectDocumentTree(reference, rootPath, records) {
  const rootSnapshot = await reference.get();
  const pending = [{reference, snapshot: rootSnapshot}];

  while (pending.length > 0) {
    const batch = pending.splice(0, EXPORT_TRAVERSAL_BATCH_SIZE);
    const results = await Promise.all(batch.map(async (item) => {
      const collections = await item.reference.listCollections();
      const childSnapshots = await Promise.all(
          collections.map((collection) => collection.get()),
      );
      return {
        ...item,
        children: childSnapshots.flatMap((snapshot) => snapshot.docs),
      };
    }));

    for (const result of results) {
      if (result.snapshot.exists) {
        if (records.length >= MAX_EXPORT_DOCUMENTS) {
          throw new Error("ACCOUNT_EXPORT_DOCUMENT_LIMIT");
        }
        records.push({
          path: result.reference.path
              .slice(rootPath.length)
              .replace(/^\//, "") || ".",
          data: jsonSafe(result.snapshot.data()),
        });
      }
      for (const child of result.children) {
        pending.push({reference: child.ref, snapshot: child});
      }
    }
  }

  records.sort((first, second) => first.path.localeCompare(second.path));
}

/**
 * Builds a bounded export or fails without returning a partial file.
 * @param {!Object} options Export dependencies and verified identity.
 * @return {!Promise<!Object>}
 */
async function exportAccountData({firestore, uid, authToken = {}}) {
  const userReference = firestore.collection("users").doc(uid);
  const documents = [];
  await collectDocumentTree(userReference, userReference.path, documents);

  const quotaSnapshot = await firestore
      .collection(CHAT_QUOTA_COLLECTION)
      .doc(uid)
      .get();
  const result = {
    schemaVersion: ACCOUNT_EXPORT_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    account: {
      id: uid,
      email: typeof authToken.email === "string" ? authToken.email : null,
      anonymous: authToken.firebase &&
        authToken.firebase.sign_in_provider === "anonymous",
    },
    documents,
    technicalUsage: quotaSnapshot.exists ? jsonSafe(quotaSnapshot.data()) : {},
  };
  if (Buffer.byteLength(JSON.stringify(result), "utf8") > MAX_EXPORT_BYTES) {
    throw new Error("ACCOUNT_EXPORT_SIZE_LIMIT");
  }
  return result;
}

/**
 * Deletes all app data while preserving Firebase Auth.
 * @param {!Object} options Deletion dependencies and verified identity.
 * @return {!Promise<!Object>}
 */
async function deleteAccountData({firestore, uid}) {
  const userReference = firestore.collection("users").doc(uid);
  await firestore.recursiveDelete(userReference);
  await firestore.collection(CHAT_QUOTA_COLLECTION).doc(uid).delete();
  return {deleted: true};
}

/**
 * Validates the closed account-data request contract.
 * @param {*} data Callable request data.
 * @return {{operation: string}}
 */
function validatePayload(data) {
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      data.schemaVersion !== 1 ||
      !["export", "delete"].includes(data.operation) ||
      ["uid", "userId", "accountId"].some((field) => field in data)) {
    throw new Error("ACCOUNT_DATA_REQUEST_INVALID");
  }
  const allowed = data.operation === "delete" ?
    new Set(["schemaVersion", "operation", "confirmation"]) :
    new Set(["schemaVersion", "operation"]);
  if (Object.keys(data).some((field) => !allowed.has(field))) {
    throw new Error("ACCOUNT_DATA_REQUEST_INVALID");
  }
  if (data.operation === "delete" &&
      data.confirmation !== DELETE_CONFIRMATION) {
    throw new Error("ACCOUNT_DATA_CONFIRMATION_INVALID");
  }
  return {operation: data.operation};
}

/**
 * Creates the authenticated and App Check protected lifecycle callable.
 * @param {!Object} dependencies Callable dependencies.
 * @return {function(!Object): !Promise<!Object>}
 */
function createCallableAccountDataHandler({
  firestore,
  exportData = exportAccountData,
  deleteData = deleteAccountData,
  HttpsErrorClass = HttpsError,
  appCheckEnforcement = zeliaEnforceAppCheck,
  env = process.env,
  logger = console,
}) {
  return async (request) => {
    const uid = request && request.auth && request.auth.uid;
    if (typeof uid !== "string" || uid.trim().length === 0) {
      throw new HttpsErrorClass(
          "unauthenticated",
          "Une session est nécessaire.",
      );
    }
    let appCheckRequired;
    try {
      ({appCheckRequired} = resolveSecurityPolicy(appCheckEnforcement, env));
    } catch (_) {
      throw new HttpsErrorClass(
          "failed-precondition",
          "La configuration de sécurité est invalide.",
      );
    }
    if (appCheckRequired &&
        !(request.app && typeof request.app.appId === "string" &&
          request.app.appId.trim().length > 0)) {
      throw new HttpsErrorClass(
          "failed-precondition",
          "La vérification de l'application est requise.",
      );
    }

    let payload;
    try {
      payload = validatePayload(request.data);
    } catch (_) {
      throw new HttpsErrorClass("invalid-argument", "La demande est invalide.");
    }

    try {
      if (payload.operation === "export") {
        const startedAt = Date.now();
        const accountExport = await exportData({
          firestore,
          uid,
          authToken: request.auth.token || {},
        });
        if (typeof logger.info === "function") {
          logger.info("ZELIA_ACCOUNT_DATA_EXPORT_SUCCESS", {
            component: "account_data_lifecycle",
            documentCount: Array.isArray(accountExport.documents) ?
              accountExport.documents.length : 0,
            durationMs: Date.now() - startedAt,
          });
        }
        return {
          operation: "export",
          export: accountExport,
        };
      }
      await deleteData({firestore, uid});
      if (typeof logger.info === "function") {
        logger.info("ZELIA_ACCOUNT_DATA_DELETE_SUCCESS", {
          component: "account_data_lifecycle",
        });
      }
      return {operation: "delete", deleted: true};
    } catch (error) {
      logger.error("ZELIA_ACCOUNT_DATA_LIFECYCLE_FAILURE", {
        component: "account_data_lifecycle",
        operation: payload.operation,
        code: error && typeof error.message === "string" &&
          error.message.startsWith("ACCOUNT_EXPORT_") ?
          error.message : "ACCOUNT_DATA_OPERATION_FAILED",
      });
      const resourceLimit = error &&
        ["ACCOUNT_EXPORT_DOCUMENT_LIMIT", "ACCOUNT_EXPORT_SIZE_LIMIT"]
            .includes(error.message);
      throw new HttpsErrorClass(
          resourceLimit ? "resource-exhausted" : "internal",
          resourceLimit ?
            "L'export est trop volumineux pour être préparé ici." :
            "L'opération n'a pas pu être terminée.",
      );
    }
  };
}

module.exports = {
  ACCOUNT_EXPORT_SCHEMA_VERSION,
  DELETE_CONFIRMATION,
  EXPORT_TRAVERSAL_BATCH_SIZE,
  MAX_EXPORT_BYTES,
  MAX_EXPORT_DOCUMENTS,
  createCallableAccountDataHandler,
  deleteAccountData,
  exportAccountData,
  jsonSafe,
  validatePayload,
};
