const {OpenAI} = require("openai");

const {
  zeliaResponseJsonSchema,
} = require("../brain/zeliaResponseJsonSchema");
const {writeDiagnostic} = require("./diagnostics");

const DEFAULT_MODEL = "gpt-4.1-mini";
const RESPONSE_SCHEMA_NAME = "zelia_response";

const RETRYABLE_STATUS_CODES = new Set([
  403,
  404,
  408,
  409,
  429,
  500,
  502,
  503,
  504,
]);

const RETRYABLE_RESPONSE_ERRORS = new Set([
  "OPENAI_EMPTY_OUTPUT",
  "OPENAI_INVALID_JSON",
  "OPENAI_INVALID_RESPONSE_OBJECT",
  "OPENAI_INVALID_RESPONSE_CONTRACT",
]);

/**
 * Construit la requête Responses API de Zelia.
 *
 * @param {Object} params paramètres de génération
 * @param {string} params.systemContent instructions système
 * @param {string} params.userMessage message utilisateur
 * @param {string} params.model modèle OpenAI
 * @param {string} params.reasoningEffort effort de raisonnement sélectionné
 * @return {Object}
 */
function buildZeliaResponseRequest({
  systemContent,
  userMessage,
  model = DEFAULT_MODEL,
  reasoningEffort,
}) {
  const request = {
    model,
    instructions: systemContent,
    input: userMessage,
    store: false,
    max_output_tokens: 2600,
    text: {
      format: {
        type: "json_schema",
        name: RESPONSE_SCHEMA_NAME,
        strict: true,
        schema: zeliaResponseJsonSchema,
      },
    },
  };

  if (model.startsWith("gpt-5.6-")) {
    request.reasoning = {
      effort: reasoningEffort,
    };
  } else {
    request.temperature = 0.03;
  }

  return request;
}

/**
 * Extrait et valide la réponse textuelle de la Responses API.
 *
 * @param {Object} response réponse OpenAI
 * @return {Object}
 */
function parseZeliaResponse(response) {
  const content =
    response &&
    typeof response.output_text === "string" ?
      response.output_text.trim() :
      "";

  if (!content) {
    throw new Error("OPENAI_EMPTY_OUTPUT");
  }

  let parsed;

  try {
    parsed = JSON.parse(content);
  } catch (error) {
    throw new Error("OPENAI_INVALID_JSON", {
      cause: error,
    });
  }

  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed)
  ) {
    throw new Error("OPENAI_INVALID_RESPONSE_OBJECT");
  }

  if (
    typeof parsed.visibleText !== "string" ||
    !Array.isArray(parsed.actions) ||
    !Array.isArray(parsed.memories) ||
    typeof parsed.epistemic !== "object" ||
    parsed.epistemic === null ||
    Array.isArray(parsed.epistemic)
  ) {
    throw new Error("OPENAI_INVALID_RESPONSE_CONTRACT");
  }

  return parsed;
}

/**
 * Détermine si une erreur justifie un repli vers le modèle de secours.
 *
 * Les erreurs de validation de requête ne sont pas masquées.
 *
 * @param {Object} error erreur reçue
 * @param {string} attemptedModel modèle initialement appelé
 * @return {boolean}
 */
function shouldFallbackToDefaultModel(error, attemptedModel) {
  if (!attemptedModel || attemptedModel === DEFAULT_MODEL) {
    return false;
  }

  const status = Number(error && error.status);
  const code = error && typeof error.code === "string" ?
    error.code :
    "";
  const message = error && typeof error.message === "string" ?
    error.message :
    "";

  if (RETRYABLE_STATUS_CODES.has(status)) {
    return true;
  }

  if (
    code === "model_not_found" ||
    code === "rate_limit_exceeded" ||
    code === "server_error"
  ) {
    return true;
  }

  return RETRYABLE_RESPONSE_ERRORS.has(message);
}

/**
 * Exécute une requête et retourne la réponse Zelia parsée.
 *
 * @param {Object} client client OpenAI
 * @param {Object} params paramètres d'exécution
 * @return {Promise<Object>}
 */
async function executeZeliaRequest({
  client,
  request,
  signal,
  tier,
  reasoningEffort,
  logger,
  env,
  correlationId,
}) {
  const startedAt = Date.now();
  const metadata = {
    model: request.model,
    tier,
    reasoningEffort,
  };

  writeDiagnostic({
    logger,
    level: "info",
    event: "ZELIA_OPENAI_REQUEST",
    component: "openai",
    step: "responses_create",
    code: "provider-request",
    correlationId,
    env,
    metadata,
  });

  try {
    const response = await client.responses.create(request, {signal});
    const requestId = response && (
      response._request_id || response.request_id
    );
    writeDiagnostic({
      logger,
      level: "info",
      event: "ZELIA_OPENAI_SUCCESS",
      component: "openai",
      step: "responses_create",
      code: "provider-success",
      correlationId,
      env,
      metadata: {
        ...metadata,
        durationMs: Date.now() - startedAt,
        requestId,
      },
    });
    return parseZeliaResponse(response);
  } catch (error) {
    writeDiagnostic({
      logger,
      level: "error",
      event: "ZELIA_OPENAI_ERROR",
      component: "openai",
      step: "responses_create",
      code: "provider-error",
      correlationId,
      env,
      metadata: {
        ...metadata,
        durationMs: Date.now() - startedAt,
        status: Number(error && error.status) || 0,
        providerCode: error && typeof error.code === "string" ?
          error.code :
          "",
        requestId: error && (
          error.request_id || error.requestId
        ),
      },
    });
    throw error;
  }
}

/**
 * Génère une réponse Zelia via la Responses API OpenAI.
 *
 * En cas d'indisponibilité du modèle sélectionné, un seul repli est
 * effectué vers gpt-4.1-mini.
 *
 * @param {Object} params paramètres de génération
 * @param {string} params.apiKey clé API OpenAI
 * @param {string} params.systemContent instructions système
 * @param {string} params.userMessage message utilisateur
 * @param {string} params.model modèle OpenAI
 * @param {string} params.tier niveau de routage
 * @param {string} params.reasoningEffort effort de raisonnement sélectionné
 * @param {Object} params.client client injecté pour les tests
 * @param {AbortSignal} params.signal signal d'annulation partagé
 * @return {Promise<Object>}
 */
async function generateZeliaResponse({
  apiKey,
  systemContent,
  userMessage,
  model = DEFAULT_MODEL,
  tier,
  reasoningEffort,
  client = null,
  logger = console,
  env = process.env,
  correlationId,
  signal,
}) {
  const openai = client || new OpenAI({
    apiKey,
  });

  const request = buildZeliaResponseRequest({
    systemContent,
    userMessage,
    model,
    reasoningEffort,
  });

  try {
    return await executeZeliaRequest({
      client: openai,
      request,
      signal,
      tier,
      reasoningEffort,
      logger,
      env,
      correlationId,
    });
  } catch (error) {
    if (!shouldFallbackToDefaultModel(error, model)) {
      throw error;
    }

    writeDiagnostic({
      logger,
      level: "warn",
      event: "ZELIA_MODEL_FALLBACK",
      component: "openai",
      step: "model_fallback",
      code: "provider-fallback",
      correlationId,
      env,
      metadata: {
        model: DEFAULT_MODEL,
        status: Number(error && error.status) || 0,
        retryable: true,
      },
    });

    const fallbackRequest = buildZeliaResponseRequest({
      systemContent,
      userMessage,
      model: DEFAULT_MODEL,
    });

    return executeZeliaRequest({
      client: openai,
      request: fallbackRequest,
      signal,
      tier,
      reasoningEffort,
      logger,
      env,
      correlationId,
    });
  }
}

module.exports = {
  DEFAULT_MODEL,
  RESPONSE_SCHEMA_NAME,
  RETRYABLE_STATUS_CODES,
  buildZeliaResponseRequest,
  parseZeliaResponse,
  shouldFallbackToDefaultModel,
  executeZeliaRequest,
  generateZeliaResponse,
};
