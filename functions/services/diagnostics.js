const {randomUUID} = require("node:crypto");
const {resolveSecurityEnvironment} = require("./securityEnvironment");

const ERROR_CODES = Object.freeze({
  unauthenticated: "unauthenticated",
  appCheckRequired: "app-check-required",
  permissionDenied: "permission-denied",
  invalidArgument: "invalid-argument",
  resourceExhausted: "resource-exhausted",
  networkUnavailable: "network-unavailable",
  timeout: "timeout",
  serviceUnavailable: "service-unavailable",
  conflict: "conflict",
  staleRevision: "stale-revision",
  notFound: "not-found",
  cancelled: "cancelled",
  storageFailure: "storage-failure",
  syncFailure: "sync-failure",
  unknown: "unknown",
});

const ALLOWED_METADATA = new Set([
  "durationMs",
  "status",
  "count",
  "retryable",
  "intent",
  "tier",
  "model",
  "reasoningEffort",
  "requestId",
  "providerCode",
]);

const FORBIDDEN_NAMES = [
  "message", "prompt", "content", "conversation", "memory", "profile",
  "email", "phone", "address", "birthdate", "health", "medical",
  "token", "authorization", "appchecktoken", "idtoken", "refreshtoken",
  "secret", "apikey", "password", "uid",
];

/**
 * Garde uniquement des métadonnées techniques explicitement autorisées.
 * Les objets et valeurs inconnus sont refusés par défaut.
 *
 * @param {Object} metadata métadonnées candidates
 * @return {Object} métadonnées sûres
 */
function sanitizeDiagnosticMetadata(metadata = {}) {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
    return {};
  }
  return Object.fromEntries(Object.entries(metadata).flatMap(([key, value]) => {
    const normalized = key.toLowerCase();
    if (!ALLOWED_METADATA.has(key) ||
        FORBIDDEN_NAMES.some((name) => normalized.includes(name))) {
      return [];
    }
    if (typeof value !== "string" && typeof value !== "number" &&
        typeof value !== "boolean") {
      return [];
    }
    return [[key, value]];
  }));
}

/**
 * Produit un identifiant aléatoire sans lien avec une utilisatrice.
 *
 * @return {string} identifiant de corrélation
 */
function createCorrelationId() {
  return randomUUID();
}

/**
 * Écrit un diagnostic fermé sans sérialiser une erreur ou un payload brut.
 *
 * @param {Object} params paramètres du diagnostic
 */
function writeDiagnostic({
  logger = console,
  level = "error",
  event = "ZELIA_DIAGNOSTIC",
  component,
  step,
  code = ERROR_CODES.unknown,
  correlationId = createCorrelationId(),
  metadata = {},
  env = process.env,
}) {
  if (!logger || typeof logger[level] !== "function") return;
  logger[level](event, {
    component,
    step,
    code,
    environment: resolveSecurityEnvironment(env),
    correlationId,
    ...sanitizeDiagnosticMetadata(metadata),
  });
}

module.exports = {
  ERROR_CODES,
  createCorrelationId,
  sanitizeDiagnosticMetadata,
  writeDiagnostic,
};
