const {HttpsError} = require("firebase-functions/v2/https");

const {ChatQuotaExceededError} = require("./chatQuotaService");
const {
  resolveSecurityPolicy,
  zeliaEnforceAppCheck,
} = require("./securityEnvironment");

const MAX_IMAGE_BYTES = 6 * 1024 * 1024;
const MAX_PDF_BYTES = 20 * 1024 * 1024;
const ALLOWED_IMAGE_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);

/**
 * Keeps provider diagnostics useful without logging document or prompt data.
 *
 * @param {Object} error Provider error.
 * @return {Object} Bounded, non-sensitive diagnostic fields.
 */
function safeProviderDiagnostic(error) {
  const safeString = (value) => typeof value === "string" ?
    value.replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 160) : undefined;
  const diagnostic = {};
  if (Number.isInteger(error && error.status)) {
    diagnostic.providerStatus = error.status;
  }
  const providerCode = safeString(error && error.code);
  const providerType = safeString(error && error.type);
  const providerParam = safeString(error && error.param);
  const requestId = safeString(error && (error.request_id || error.requestId));
  if (providerCode) diagnostic.providerCode = providerCode;
  if (providerType) diagnostic.providerType = providerType;
  if (providerParam) diagnostic.providerParam = providerParam;
  if (requestId) diagnostic.providerRequestId = requestId;
  return diagnostic;
}

/**
 * Validates a callable request before any provider transmission.
 *
 * @param {Object} payload Untrusted callable payload.
 * @return {Object} Validated analysis payload.
 */
function validateScheduleDocumentPayload(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload) ||
      payload.schemaVersion !== 1 ||
      !["image", "pdf"].includes(payload.documentKind) ||
      typeof payload.mimeType !== "string" ||
      typeof payload.fileBase64 !== "string" ||
      typeof payload.subjectEntityId !== "string" ||
      typeof payload.subjectLabel !== "string") {
    throw new Error("SCHEDULE_DOCUMENT_REQUEST_INVALID");
  }
  if (["uid", "userId", "accountId"].some((field) => field in payload)) {
    throw new Error("SCHEDULE_DOCUMENT_IDENTITY_FORBIDDEN");
  }
  if (payload.subjectEntityId.trim().length === 0 ||
      payload.subjectEntityId.length > 160 ||
      payload.subjectLabel.trim().length === 0 ||
      payload.subjectLabel.length > 160) {
    throw new Error("SCHEDULE_DOCUMENT_SUBJECT_INVALID");
  }

  const expectedMime = payload.documentKind === "pdf" ?
    payload.mimeType === "application/pdf" :
    ALLOWED_IMAGE_MIME_TYPES.has(payload.mimeType);
  if (!expectedMime || payload.fileBase64.length === 0 ||
      payload.fileBase64.length > Math.ceil(MAX_PDF_BYTES * 4 / 3) + 8 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(payload.fileBase64)) {
    throw new Error("SCHEDULE_DOCUMENT_ENCODING_INVALID");
  }

  const bytes = Buffer.from(payload.fileBase64, "base64");
  const maximumBytes = payload.documentKind === "pdf" ?
    MAX_PDF_BYTES : MAX_IMAGE_BYTES;
  if (bytes.length === 0 || bytes.length > maximumBytes) {
    throw new Error("SCHEDULE_DOCUMENT_SIZE_INVALID");
  }
  if (!hasExpectedSignature(bytes, payload.mimeType)) {
    throw new Error("SCHEDULE_DOCUMENT_SIGNATURE_INVALID");
  }

  return {
    documentKind: payload.documentKind,
    mimeType: payload.mimeType,
    fileBase64: payload.fileBase64,
    subject: {
      entityId: payload.subjectEntityId.trim(),
      label: payload.subjectLabel.trim(),
    },
  };
}

/**
 * Checks that decoded bytes match their declared MIME type.
 *
 * @param {Buffer} bytes Decoded document bytes.
 * @param {string} mimeType Declared MIME type.
 * @return {boolean} Whether the signature matches.
 */
function hasExpectedSignature(bytes, mimeType) {
  if (mimeType === "application/pdf") {
    return bytes.subarray(0, 5).toString("ascii") === "%PDF-";
  }
  if (mimeType === "image/jpeg") {
    return bytes.length >= 3 && bytes[0] === 0xff &&
      bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  if (mimeType === "image/png") {
    return bytes.length >= 8 &&
      bytes.subarray(0, 8).equals(
          Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      );
  }
  return mimeType === "image/webp" && bytes.length >= 12 &&
    bytes.subarray(0, 4).toString("ascii") === "RIFF" &&
    bytes.subarray(8, 12).toString("ascii") === "WEBP";
}

/**
 * Creates the authenticated, App Check protected callable handler.
 *
 * @param {Object} dependencies Handler dependencies.
 * @return {Function} Callable request handler.
 */
function createCallableScheduleDocumentHandler({
  analyzeDocument,
  getApiKey,
  consumeQuota,
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
    const appId = request && request.app && request.app.appId;
    if (appCheckRequired &&
        (typeof appId !== "string" || appId.trim().length === 0)) {
      throw new HttpsErrorClass(
          "failed-precondition",
          "La vérification de l'application est requise.",
      );
    }

    let payload;
    try {
      payload = validateScheduleDocumentPayload(request && request.data);
    } catch (_) {
      throw new HttpsErrorClass(
          "invalid-argument",
          "Le document est invalide.",
      );
    }

    try {
      if (typeof consumeQuota !== "function") {
        throw new Error("SCHEDULE_DOCUMENT_QUOTA_NOT_CONFIGURED");
      }
      await consumeQuota({uid});
      return await analyzeDocument({...payload, apiKey: getApiKey()});
    } catch (error) {
      if (error instanceof ChatQuotaExceededError ||
          error && error.code === "chat_quota_exceeded") {
        throw new HttpsErrorClass(
            "resource-exhausted",
            "Le nombre d'analyses autorisé a été atteint.",
        );
      }
      if (error instanceof HttpsErrorClass) throw error;
      logger.error("ZELIA_SCHEDULE_DOCUMENT_ANALYSIS_FAILURE", {
        component: "schedule_document_analysis",
        code: "service-unavailable",
        ...safeProviderDiagnostic(error),
      });
      throw new HttpsErrorClass(
          "internal",
          "Le document n'a pas pu être analysé.",
      );
    }
  };
}

module.exports = {
  ALLOWED_IMAGE_MIME_TYPES,
  MAX_IMAGE_BYTES,
  MAX_PDF_BYTES,
  createCallableScheduleDocumentHandler,
  hasExpectedSignature,
  safeProviderDiagnostic,
  validateScheduleDocumentPayload,
};
