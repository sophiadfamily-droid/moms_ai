/* eslint-disable max-len */

const systemPrompt = require("../brain/systemPrompt");
const shoppingDictionary = require("../brain/shoppingDictionary");
const taskDictionary = require("../brain/taskDictionary");
const eventDictionary = require("../brain/eventDictionary");
const memoryRules = require("../brain/memoryRules");
const priorities = require("../brain/priorities");
const {detectIntent} = require("../brain/engines/intentDetector");
const {
  detectPlanningComplexity,
} = require("../brain/engines/planningComplexityDetector");
const {generateZeliaResponse} = require("./openaiService");
const {routeModel} = require("./modelRouterService");
const {sanitizeEventParticipants} = require("./eventParticipantContract");
const {sanitizeEventMutations} = require("./eventMutationContract");
const {writeDiagnostic} = require("./diagnostics");

const OPENAI_TIMEOUT_MS = 22000;

/**
 * Construit le contexte cerveau de Zelia.
 * @return {string}
 */
function buildBrainContext() {
  return `
==================================================
SHOPPING DICTIONARY
==================================================

${JSON.stringify(shoppingDictionary)}

==================================================
TASK DICTIONARY
==================================================

${JSON.stringify(taskDictionary)}

==================================================
EVENT DICTIONARY
==================================================

${JSON.stringify(eventDictionary)}

==================================================
MEMORY RULES
==================================================

${JSON.stringify(memoryRules)}

==================================================
PRIORITIES
==================================================

${JSON.stringify(priorities)}
`;
}

/**
 * Exécute toute la génération dans une échéance unique, repli compris.
 *
 * @param {Function} operation génération à exécuter
 * @param {number} timeoutMs échéance totale
 * @param {Object} timers gestionnaires de minuterie injectables
 * @return {Promise<Object>}
 */
async function runWithOpenAiDeadline(
    operation,
    timeoutMs,
    timers = {setTimeout, clearTimeout},
) {
  const controller = new AbortController();
  let timeoutId;

  const timeoutPromise = new Promise((resolve, reject) => {
    timeoutId = timers.setTimeout(() => {
      controller.abort();
      reject(new Error("OPENAI_TIMEOUT"));
    }, timeoutMs);
  });

  try {
    return await Promise.race([
      operation(controller.signal),
      timeoutPromise,
    ]);
  } finally {
    timers.clearTimeout(timeoutId);
  }
}

/**
 * Exécute l'orchestration ZELIA indépendamment du transport.
 *
 * @param {Object} payload charge utile HTTP ou callable
 * @param {Object} context identité vérifiée par le transport
 * @param {Object} dependencies dépendances injectables
 * @return {Promise<Object>}
 */
async function handleChatRequest(
    payload,
    context = {},
    dependencies = {},
) {
  if (typeof context.uid !== "string" || context.uid.trim().length === 0) {
    throw new Error("CHAT_AUTH_CONTEXT_REQUIRED");
  }

  const source = payload || {};
  const message = source.message || "";
  const profile = source.profile || {};
  const profileContext = source.profileContext || {};
  const memories = source.memories || [];
  const memoryReasoning = source.memoryReasoning || [];
  const events = source.events || [];

  const now = dependencies.now || (() => new Date());
  const logger = dependencies.logger || console;
  const generateResponse =
      dependencies.generateResponse || generateZeliaResponse;
  const route = dependencies.route || routeModel;
  const timeoutMs = dependencies.openAiTimeoutMs || OPENAI_TIMEOUT_MS;
  const today = now().toISOString().slice(0, 10);
  const detectedIntent = detectIntent(message);
  const planningComplexity = detectPlanningComplexity(message);

  const systemContent = `
${systemPrompt({
    today,
    profile,
    profileContext,
    memories,
    memoryReasoning,
    events,
    detectedIntent,
  })}

${buildBrainContext()}
`;

  const modelDecision = route({
    primaryIntent: detectedIntent.primaryIntent,
    requiresComplexPlanning: planningComplexity.requiresComplexPlanning,
    env: dependencies.env || process.env,
  });

  writeDiagnostic({
    logger,
    level: "info",
    event: "ZELIA_MODEL_ROUTING",
    component: "chat_orchestration",
    step: "model_routing",
    code: "model-routed",
    env: dependencies.env || process.env,
    metadata: {
      intent: detectedIntent.primaryIntent,
      tier: modelDecision.tier,
      model: modelDecision.model,
    },
  });

  const parsed = await runWithOpenAiDeadline(
      (signal) => generateResponse({
        apiKey: dependencies.apiKey,
        systemContent,
        userMessage: message,
        model: modelDecision.model,
        logger,
        env: dependencies.env || process.env,
        signal,
      }),
      timeoutMs,
  );

  return {
    reply: parsed.reply || "C'est noté 💕",
    actions: sanitizeEventMutations(
        sanitizeEventParticipants(parsed.actions, message, logger),
        message,
        logger),
    memories: parsed.memories || [],
  };
}

module.exports = {
  OPENAI_TIMEOUT_MS,
  buildBrainContext,
  runWithOpenAiDeadline,
  handleChatRequest,
};
