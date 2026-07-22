const DEFAULT_CHAT_QUOTA_LIMIT = 30;
const DEFAULT_CHAT_QUOTA_WINDOW_SECONDS = 60;
const CHAT_QUOTA_COLLECTION = "__server_ai_chat_quota";

/** Erreur stable indiquant que la fenêtre de quota est épuisée. */
class ChatQuotaExceededError extends Error {
  /** Construit l'erreur sans donnée utilisateur. */
  constructor() {
    super("CHAT_QUOTA_EXCEEDED");
    this.code = "chat_quota_exceeded";
  }
}

/**
 * Lit un entier configurable dans des bornes sûres.
 *
 * @param {unknown} value valeur candidate
 * @param {number} fallback valeur de repli
 * @param {number} minimum borne basse
 * @param {number} maximum borne haute
 * @return {number} entier borné
 */
function parseBoundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value == null ? "" : value), 10);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    return fallback;
  }
  return parsed;
}

/**
 * Construit la configuration du quota technique. Un document fixe par UID
 * évite une croissance non bornée et ne contient aucun contenu utilisateur.
 *
 * @param {Object} env variables d'environnement
 * @return {{limit: number, windowMs: number}}
 */
function resolveChatQuotaConfig(env = process.env) {
  const limit = parseBoundedInteger(
      env.ZELIA_AI_CHAT_QUOTA_LIMIT,
      DEFAULT_CHAT_QUOTA_LIMIT,
      1,
      1000,
  );
  const windowSeconds = parseBoundedInteger(
      env.ZELIA_AI_CHAT_QUOTA_WINDOW_SECONDS,
      DEFAULT_CHAT_QUOTA_WINDOW_SECONDS,
      10,
      86400,
  );
  return {limit, windowMs: windowSeconds * 1000};
}

/**
 * Consomme une unité de quota dans une transaction Firestore.
 *
 * @param {Object} params paramètres
 * @param {Object} params.firestore instance Admin Firestore
 * @param {string} params.uid UID Firebase vérifié
 * @param {Function} params.now horloge injectable
 * @param {Object} params.env environnement injectable
 * @return {Promise<{remaining: number}>} quota restant
 */
async function consumeChatQuota({
  firestore,
  uid,
  now = () => Date.now(),
  env = process.env,
}) {
  if (!firestore || typeof firestore.runTransaction !== "function") {
    throw new Error("CHAT_QUOTA_STORE_UNAVAILABLE");
  }
  if (typeof uid !== "string" || uid.trim().length === 0) {
    throw new Error("CHAT_QUOTA_UID_INVALID");
  }

  const config = resolveChatQuotaConfig(env);
  const currentTimeMs = now();
  const reference = firestore.collection(CHAT_QUOTA_COLLECTION).doc(uid);

  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const stored = snapshot.exists ? snapshot.data() : {};
    const previousStart = Number.isInteger(stored.windowStartedAtMs) ?
      stored.windowStartedAtMs : currentTimeMs;
    const previousCount = Number.isInteger(stored.count) ? stored.count : 0;
    const windowExpired = currentTimeMs - previousStart >= config.windowMs ||
      currentTimeMs < previousStart;
    const windowStartedAtMs = windowExpired ? currentTimeMs : previousStart;
    const count = windowExpired ? 0 : previousCount;

    if (count >= config.limit) {
      throw new ChatQuotaExceededError();
    }

    const nextCount = count + 1;
    transaction.set(reference, {
      windowStartedAtMs,
      count: nextCount,
      updatedAtMs: currentTimeMs,
    });
    return {remaining: config.limit - nextCount};
  });
}

module.exports = {
  CHAT_QUOTA_COLLECTION,
  DEFAULT_CHAT_QUOTA_LIMIT,
  DEFAULT_CHAT_QUOTA_WINDOW_SECONDS,
  ChatQuotaExceededError,
  consumeChatQuota,
  resolveChatQuotaConfig,
};
