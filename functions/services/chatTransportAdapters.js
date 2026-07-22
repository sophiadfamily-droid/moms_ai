const {HttpsError} = require("firebase-functions/v2/https");
const {ChatQuotaExceededError} = require("./chatQuotaService");
const {requiresAppCheck} = require("./securityEnvironment");

const CALLABLE_TIMEOUT_SECONDS = 25;
const CHAT_FUNCTION_REGION = "us-central1";
const OPENAI_API_KEY_NAME = "OPENAI_API_KEY";

/**
 * Construit les options du callable sécurisé.
 *
 * @param {Object} openaiApiKey secret Firebase OpenAI
 * @param {Object} env variables d'environnement
 * @return {Object}
 */
function createCallableFunctionOptions(openaiApiKey, env = process.env) {
  return {
    region: CHAT_FUNCTION_REGION,
    secrets: [openaiApiKey],
    timeoutSeconds: CALLABLE_TIMEOUT_SECONDS,
    enforceAppCheck: requiresAppCheck(env),
  };
}

/**
 * Construit l'adaptateur HTTP historique.
 *
 * @param {Object} dependencies dépendances de l'adaptateur
 * @return {Function}
 */
/**
 * Construit l'adaptateur Firebase callable sécurisé.
 *
 * @param {Object} dependencies dépendances de l'adaptateur
 * @return {Function}
 */
function createCallableChatHandler({
  handleChatRequest,
  getApiKey,
  logger = console,
  HttpsErrorClass = HttpsError,
  handlerDependencies = {},
  consumeQuota,
  env = process.env,
}) {
  return async (request) => {
    const payload = request && request.data;

    const uid = request && request.auth && request.auth.uid;
    if (typeof uid !== "string" || uid.trim().length === 0) {
      throw new HttpsErrorClass(
          "unauthenticated",
          "Une session ZELIA valide est nécessaire.",
      );
    }

    const appId = request && request.app && request.app.appId;
    if (requiresAppCheck(env) &&
        (typeof appId !== "string" || appId.trim().length === 0)) {
      throw new HttpsErrorClass(
          "failed-precondition",
          "La vérification de l'application est requise.",
      );
    }

    if (
      typeof payload !== "object" ||
      payload === null ||
      Array.isArray(payload)
    ) {
      throw new HttpsErrorClass(
          "invalid-argument",
          "La requête ZELIA est invalide.",
      );
    }

    const forbiddenIdentityFields = ["uid", "userId", "accountId"];
    if (forbiddenIdentityFields.some((field) => field in payload)) {
      throw new HttpsErrorClass(
          "invalid-argument",
          "La requête ZELIA contient un champ interdit.",
      );
    }

    try {
      if (typeof consumeQuota !== "function") {
        throw new Error("CHAT_QUOTA_NOT_CONFIGURED");
      }
      await consumeQuota({uid});
      return await handleChatRequest(payload, {
        uid,
      }, {
        ...handlerDependencies,
        apiKey: getApiKey(),
      });
    } catch (error) {
      if (error instanceof ChatQuotaExceededError ||
          error && error.code === "chat_quota_exceeded") {
        throw new HttpsErrorClass(
            "resource-exhausted",
            "Le nombre de requêtes autorisé a été atteint. Réessaie plus tard.",
        );
      }
      if (error instanceof HttpsErrorClass) {
        throw error;
      }
      logger.error("ZELIA_CHAT_FAILURE", {
        code: "chat_processing_failed",
      });
      throw new HttpsErrorClass(
          "internal",
          "Je rencontre un petit souci 💕",
      );
    }
  };
}

module.exports = {
  CALLABLE_TIMEOUT_SECONDS,
  CHAT_FUNCTION_REGION,
  OPENAI_API_KEY_NAME,
  createCallableFunctionOptions,
  createCallableChatHandler,
};
