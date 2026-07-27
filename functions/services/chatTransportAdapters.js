const {HttpsError} = require("firebase-functions/v2/https");
const {ChatQuotaExceededError} = require("./chatQuotaService");
const {
  resolveSecurityPolicy,
  zeliaEnforceAppCheck,
} = require("./securityEnvironment");
const {ERROR_CODES, writeDiagnostic} = require("./diagnostics");
const {
  ConversationContextValidationError,
  validateConversationRequest,
} = require("./conversationContextContract");

const CALLABLE_TIMEOUT_SECONDS = 60;
const CHAT_FUNCTION_REGION = "us-central1";
const OPENAI_API_KEY_NAME = "OPENAI_API_KEY";

/**
 * Construit les options du callable sécurisé.
 *
 * @param {Object} openaiApiKey secret Firebase OpenAI
 * @param {Object} appCheckEnforcement paramètre Firebase App Check
 * @return {Object}
 */
function createCallableFunctionOptions(
    openaiApiKey,
    appCheckEnforcement = zeliaEnforceAppCheck,
) {
  return {
    region: CHAT_FUNCTION_REGION,
    secrets: [openaiApiKey],
    timeoutSeconds: CALLABLE_TIMEOUT_SECONDS,
    enforceAppCheck: appCheckEnforcement,
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
  appCheckEnforcement = zeliaEnforceAppCheck,
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

    let appCheckRequired;
    try {
      ({appCheckRequired} = resolveSecurityPolicy(
          appCheckEnforcement,
          env,
      ));
    } catch (error) {
      writeDiagnostic({
        logger,
        level: "error",
        event: "ZELIA_SECURITY_CONFIGURATION_INVALID",
        component: "chat_transport",
        step: "security_environment",
        code: ERROR_CODES.appCheckRequired,
        env,
      });
      throw new HttpsErrorClass(
          "failed-precondition",
          "La configuration de sécurité ZELIA est invalide.",
      );
    }

    const appId = request && request.app && request.app.appId;
    const hasVerifiedAppCheck =
      typeof appId === "string" && appId.trim().length > 0;
    if (appCheckRequired &&
        !hasVerifiedAppCheck) {
      throw new HttpsErrorClass(
          "failed-precondition",
          "La vérification de l'application est requise.",
      );
    }
    if (!appCheckRequired && !hasVerifiedAppCheck) {
      writeDiagnostic({
        logger,
        level: "warn",
        event: "ZELIA_APP_CHECK_OBSERVED",
        component: "chat_transport",
        step: "app_check",
        code: ERROR_CODES.appCheckNotEnforced,
        env,
        metadata: {
          authStatus: "verified",
          appCheckStatus: "missing",
        },
      });
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

    let validatedPayload;
    try {
      validatedPayload = validateConversationRequest(payload);
    } catch (error) {
      if (error instanceof ConversationContextValidationError) {
        throw new HttpsErrorClass(
            "invalid-argument",
            "La requête ZELIA est invalide.",
        );
      }
      throw error;
    }

    try {
      if (typeof consumeQuota !== "function") {
        throw new Error("CHAT_QUOTA_NOT_CONFIGURED");
      }
      await consumeQuota({uid});
      return await handleChatRequest(validatedPayload, {
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
      writeDiagnostic({
        logger,
        level: "error",
        event: "ZELIA_CHAT_FAILURE",
        component: "chat_transport",
        step: "request",
        code: ERROR_CODES.serviceUnavailable,
        env,
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
