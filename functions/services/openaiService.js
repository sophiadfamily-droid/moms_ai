const {OpenAI} = require("openai");

const {
  zeliaResponseJsonSchema,
} = require("../brain/zeliaResponseJsonSchema");

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
 * @return {Object}
 */
function buildZeliaResponseRequest({
  systemContent,
  userMessage,
  model = DEFAULT_MODEL,
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

  if (!model.startsWith("gpt-5.6-")) {
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
    typeof parsed.reply !== "string" ||
    !Array.isArray(parsed.actions) ||
    !Array.isArray(parsed.memories)
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
 * @param {Object} request requête Responses API
 * @param {AbortSignal} signal signal d'annulation partagé
 * @return {Promise<Object>}
 */
async function executeZeliaRequest(client, request, signal) {
  const response = await client.responses.create(request, {signal});
  return parseZeliaResponse(response);
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
 * @param {Object} params.client client injecté pour les tests
 * @param {AbortSignal} params.signal signal d'annulation partagé
 * @return {Promise<Object>}
 */
async function generateZeliaResponse({
  apiKey,
  systemContent,
  userMessage,
  model = DEFAULT_MODEL,
  client = null,
  signal,
}) {
  const openai = client || new OpenAI({
    apiKey,
  });

  const request = buildZeliaResponseRequest({
    systemContent,
    userMessage,
    model,
  });

  try {
    return await executeZeliaRequest(openai, request, signal);
  } catch (error) {
    if (!shouldFallbackToDefaultModel(error, model)) {
      throw error;
    }

    console.warn("ZELIA MODEL FALLBACK", {
      attemptedModel: model,
      fallbackModel: DEFAULT_MODEL,
      status: error && error.status ? error.status : null,
      code: error && error.code ? error.code : null,
    });

    const fallbackRequest = buildZeliaResponseRequest({
      systemContent,
      userMessage,
      model: DEFAULT_MODEL,
    });

    return executeZeliaRequest(openai, fallbackRequest, signal);
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
