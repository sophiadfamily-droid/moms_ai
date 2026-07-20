const {HttpsError} = require("firebase-functions/v2/https");

const CALLABLE_TIMEOUT_SECONDS = 25;
const CHAT_FUNCTION_REGION = "us-central1";
const OPENAI_API_KEY_NAME = "OPENAI_API_KEY";

/**
 * Construit les options de la Function HTTP historique.
 *
 * @param {Object} openaiApiKey secret Firebase OpenAI
 * @return {Object}
 */
function createHttpFunctionOptions(openaiApiKey) {
  return {
    cors: true,
    region: CHAT_FUNCTION_REGION,
    secrets: [openaiApiKey],
  };
}

/**
 * Construit les options de la Function callable.
 *
 * @param {Object} openaiApiKey secret Firebase OpenAI
 * @return {Object}
 */
function createCallableFunctionOptions(openaiApiKey) {
  return {
    region: CHAT_FUNCTION_REGION,
    secrets: [openaiApiKey],
    timeoutSeconds: CALLABLE_TIMEOUT_SECONDS,
    enforceAppCheck: false,
  };
}

/**
 * Construit l'adaptateur HTTP historique.
 *
 * @param {Object} dependencies dépendances de l'adaptateur
 * @return {Function}
 */
function createHttpChatHandler({
  handleChatRequest,
  getApiKey,
  logger = console,
  handlerDependencies = {},
}) {
  return async (req, res) => {
    try {
      const result = await handleChatRequest(req.body, {}, {
        ...handlerDependencies,
        apiKey: getApiKey(),
      });

      res.json(result);
    } catch (error) {
      logger.error("ZELIA ERROR :", error);

      res.status(500).json({
        reply: "Je rencontre un petit souci 💕",
        actions: [],
        memories: [],
      });
    }
  };
}

/**
 * Construit l'adaptateur Firebase callable de phase 2.
 *
 * L'authentification et App Check sont volontairement observables mais non
 * imposés pendant la migration de transport.
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
}) {
  return async (request) => {
    const payload = request && request.data;

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

    try {
      return await handleChatRequest(payload, {
        auth: request.auth,
        app: request.app,
      }, {
        ...handlerDependencies,
        apiKey: getApiKey(),
      });
    } catch (error) {
      logger.error("ZELIA ERROR :", error);
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
  createHttpFunctionOptions,
  createCallableFunctionOptions,
  createHttpChatHandler,
  createCallableChatHandler,
};
