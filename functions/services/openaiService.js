const {OpenAI} = require("openai");

const {
  zeliaResponseJsonSchema,
} = require("../brain/zeliaResponseJsonSchema");

const DEFAULT_MODEL = "gpt-4.1-mini";
const RESPONSE_SCHEMA_NAME = "zelia_response";

/**
 * Construit la requête Responses API de Zelia.
 *
 * Cette fonction est séparée pour rendre le contrat testable
 * sans effectuer de véritable appel réseau.
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
 * Génère une réponse Zelia via la Responses API OpenAI.
 *
 * @param {Object} params paramètres de génération
 * @param {string} params.apiKey clé API OpenAI
 * @param {string} params.systemContent instructions système
 * @param {string} params.userMessage message utilisateur
 * @param {string} params.model modèle OpenAI
 * @return {Promise<Object>}
 */
async function generateZeliaResponse({
  apiKey,
  systemContent,
  userMessage,
  model = DEFAULT_MODEL,
}) {
  const openai = new OpenAI({
    apiKey,
  });

  const request = buildZeliaResponseRequest({
    systemContent,
    userMessage,
    model,
  });

  const response = await openai.responses.create(request);

  return parseZeliaResponse(response);
}

module.exports = {
  DEFAULT_MODEL,
  RESPONSE_SCHEMA_NAME,
  buildZeliaResponseRequest,
  parseZeliaResponse,
  generateZeliaResponse,
};
