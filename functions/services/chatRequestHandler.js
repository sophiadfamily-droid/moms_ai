/* eslint-disable max-len */

const systemPrompt = require("../brain/systemPrompt");
const shoppingDictionary = require("../brain/shoppingDictionary");
const taskDictionary = require("../brain/taskDictionary");
const eventDictionary = require("../brain/eventDictionary");
const memoryRules = require("../brain/memoryRules");
const priorities = require("../brain/priorities");
const {
  detectIntent,
  extractTaskCreation,
} = require("../brain/engines/intentDetector");
const {
  detectPlanningComplexity,
} = require("../brain/engines/planningComplexityDetector");
const {generateZeliaResponse} = require("./openaiService");
const {routeModel} = require("./modelRouterService");
const {sanitizeEventParticipants} = require("./eventParticipantContract");
const {sanitizeEventMutations} = require("./eventMutationContract");
const {writeDiagnostic} = require("./diagnostics");
const {buildEventClarification} = require("./eventClarificationDraft");
const {
  canonicalProfileFactAnswer,
} = require("./canonicalProfileFactAnswer");
const {
  canonicalShoppingContextUnavailableAnswer,
  canonicalShoppingFactAnswer,
  requestedShoppingView,
} = require("./canonicalShoppingFactAnswer");
const {validateConversationRequest} =
  require("./conversationContextContract");
const {validateConversationResponse} =
  require("./conversationResponseContract");

const OPENAI_TIMEOUT_MS = 45000;

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

  const source = validateConversationRequest(payload);
  const correlationId = source.correlationId;
  const message = source.message || "";
  const profile = source.profile || {};
  const profileContext = source.profileContext || {};
  const memories = source.memories || [];
  const memoryReasoning = source.memoryReasoning || [];
  const events = source.events || [];
  const conversationContext = source.conversationContext;
  const conversationHistory = source.conversationHistory;
  const isGuidedDiscussion =
    source.conversationMode === "guidedDiscussion";

  const now = dependencies.now || (() => new Date());
  const logger = dependencies.logger || console;
  const generateResponse =
      dependencies.generateResponse || generateZeliaResponse;
  const route = dependencies.route || routeModel;
  const timeoutMs = dependencies.openAiTimeoutMs || OPENAI_TIMEOUT_MS;
  const today = now().toISOString().slice(0, 10);
  const nluStartedAt = Date.now();
  const detectedIntent = detectIntent(message);
  writeDiagnostic({
    logger,
    level: "info",
    event: "ZELIA_NATURAL_LANGUAGE",
    component: "natural_language",
    step: detectedIntent.understandingLevel === "ambiguous" ?
      "resolve_ambiguity" : "detect_intent",
    code: detectedIntent.understandingLevel === "ambiguous" ?
      "clarification-required" : "intent-detected",
    correlationId,
    env: dependencies.env || process.env,
    metadata: {
      durationMs: Date.now() - nluStartedAt,
      normalizationCodes:
        detectedIntent.normalization.normalizationCodes,
      intentCode: detectedIntent.primaryIntent,
      understandingLevel: detectedIntent.understandingLevel,
      entityTypes: [],
      ambiguityType: detectedIntent.ambiguityType || "",
    },
  });
  const planningComplexity = detectPlanningComplexity(message);
  const taskCreation = extractTaskCreation(message, now());

  const profileFactAnswer = isGuidedDiscussion ?
    null : canonicalProfileFactAnswer(source);
  if (profileFactAnswer !== null) {
    const validated = validateConversationResponse(profileFactAnswer, source);
    return {
      reply: validated.visibleText,
      actions: validated.actions,
      memories: validated.memories,
      epistemic: validated.epistemic,
    };
  }

  const shoppingFactAnswer = isGuidedDiscussion ? null :
    canonicalShoppingFactAnswer(source, {
      sourceType: "lifeContextShopping",
    });
  const shoppingView = isGuidedDiscussion ? null :
    requestedShoppingView(message);
  if (shoppingFactAnswer !== null) {
    const validated = validateConversationResponse(
        shoppingFactAnswer,
        source,
    );
    return {
      reply: validated.visibleText,
      actions: validated.actions,
      memories: validated.memories,
      epistemic: validated.epistemic,
    };
  }
  if (shoppingView !== null) {
    const unavailable = validateConversationResponse(
        canonicalShoppingContextUnavailableAnswer(source),
        source,
    );
    return {
      reply: unavailable.visibleText,
      actions: unavailable.actions,
      memories: unavailable.memories,
      epistemic: unavailable.epistemic,
    };
  }

  if (!isGuidedDiscussion &&
      detectedIntent.understandingLevel === "ambiguous") {
    const ambiguityType = detectedIntent.ambiguityType || "multiple_meanings";
    const questionText = ambiguityType === "negation_scope" ?
      "Je veux être sûre de respecter la négation. Que souhaites-tu faire ?" :
      ambiguityType === "plus_meaning" ?
        "Veux-tu en ajouter, ou veux-tu dire qu’il n’en reste plus ?" :
        "Ta phrase peut désigner plusieurs actions. Laquelle veux-tu préparer ?";
    const createdAt = now();
    const expiresAt = new Date(createdAt.getTime() + 10 * 60 * 1000);
    const clarificationResponse = validateConversationResponse({
      visibleText: questionText,
      actions: [],
      memories: [],
      epistemic: {
        schemaVersion: 1,
        responseKind: "clarificationRequired",
        epistemicState: "insufficientInformation",
        confidenceLevel: "low",
        usedSourceTypes: ["currentUserMessage"],
        groundingReferences: [{
          schemaVersion: 1,
          sourceType: "currentUserMessage",
          section: null,
          factKey: null,
          freshness: "current",
          confirmation: "confirmed",
          projectionVersion: 0,
        }],
        personalClaims: [],
        missingInformation: [{
          schemaVersion: 1,
          code: "missingChoice",
          domain: "general",
          field: "intent",
          isRequired: true,
          canClarify: true,
        }],
        contradictions: [],
        clarification: {
          schemaVersion: 1,
          clarificationId: `nlu-${source.sessionGeneration}`,
          reasonCode: `nlu_${ambiguityType}`,
          questionText,
          expectedAnswerType: "freeTextBounded",
          allowedChoices: [],
          missingFieldCodes: ["missingChoice"],
          createdAt: createdAt.toISOString(),
          expiresAt: expiresAt.toISOString(),
          attemptNumber: 1,
          maximumAttempts: 3,
          sessionGeneration: source.sessionGeneration,
          draft: null,
        },
        uncertaintyCodes: ["missingRequiredInformation"],
        contextStateObserved: source.conversationContext.state,
        warningCodes: [],
        responseId: `nlu-clarification-${source.sessionGeneration}`,
      },
    }, source);
    return {
      reply: clarificationResponse.visibleText,
      actions: clarificationResponse.actions,
      memories: clarificationResponse.memories,
      epistemic: clarificationResponse.epistemic,
    };
  }

  if (!isGuidedDiscussion && detectedIntent.primaryIntent === "task" &&
      taskCreation.isCreation && taskCreation.title.length === 0) {
    const clarificationResponse = validateConversationResponse({
      visibleText: "Quelle tâche veux-tu créer ?",
      actions: [],
      memories: [],
      epistemic: {
        schemaVersion: 1,
        responseKind: "clarificationRequired",
        epistemicState: "insufficientInformation",
        confidenceLevel: "low",
        usedSourceTypes: ["currentUserMessage"],
        groundingReferences: [{
          schemaVersion: 1,
          sourceType: "currentUserMessage",
          section: null,
          factKey: null,
          freshness: "current",
          confirmation: "confirmed",
          projectionVersion: 0,
        }],
        personalClaims: [],
        missingInformation: [{
          schemaVersion: 1,
          code: "missingTaskTarget",
          domain: "task",
          field: "target",
          isRequired: true,
          canClarify: true,
        }],
        contradictions: [],
        clarification: {
          schemaVersion: 1,
          clarificationId:
              `task-title-${source.sessionGeneration}`,
          reasonCode: "task_title_required",
          questionText: "Quelle tâche veux-tu créer ?",
          expectedAnswerType: "freeTextBounded",
          allowedChoices: [],
          missingFieldCodes: ["missingTaskTarget"],
          createdAt: now().toISOString(),
          expiresAt: null,
          attemptNumber: 1,
          maximumAttempts: 3,
          sessionGeneration: source.sessionGeneration,
          draft: null,
        },
        uncertaintyCodes: ["missingRequiredInformation"],
        contextStateObserved: source.conversationContext.state,
        warningCodes: [],
        responseId: `task-clarification-${source.sessionGeneration}`,
      },
    }, source);
    return {
      reply: clarificationResponse.visibleText,
      actions: clarificationResponse.actions,
      memories: clarificationResponse.memories,
      epistemic: clarificationResponse.epistemic,
    };
  }

  if (!isGuidedDiscussion && detectedIntent.primaryIntent === "event") {
    const eventClarification = buildEventClarification({
      message,
      now: now(),
      correlationId,
      sessionGeneration: source.sessionGeneration,
      contextState: source.conversationContext.state,
    });
    if (eventClarification !== null) {
      const validated = validateConversationResponse(
          eventClarification,
          source,
      );
      return {
        reply: validated.visibleText,
        actions: validated.actions,
        memories: validated.memories,
        epistemic: validated.epistemic,
      };
    }
  }

  const systemContent = `
${systemPrompt({
    today,
    profile,
    profileContext,
    memories,
    memoryReasoning,
    events,
    conversationContext,
    conversationHistory,
    detectedIntent,
    autonomyMode: source.autonomyMode,
    conversationMode: source.conversationMode,
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
    correlationId,
    env: dependencies.env || process.env,
    metadata: {
      intent: detectedIntent.primaryIntent,
      tier: modelDecision.tier,
      model: modelDecision.model,
      reasoningEffort: modelDecision.reasoningEffort,
    },
  });

  const startedAt = Date.now();
  let parsed;
  try {
    parsed = await runWithOpenAiDeadline(
        (signal) => generateResponse({
          apiKey: dependencies.apiKey,
          systemContent,
          userMessage: message,
          model: modelDecision.model,
          tier: modelDecision.tier,
          reasoningEffort: modelDecision.reasoningEffort,
          logger,
          env: dependencies.env || process.env,
          correlationId,
          signal,
        }),
        timeoutMs,
    );
  } catch (error) {
    if (error && error.message === "OPENAI_TIMEOUT") {
      writeDiagnostic({
        logger,
        level: "error",
        event: "ZELIA_OPENAI_TIMEOUT",
        component: "chat_orchestration",
        step: "openai_deadline",
        code: "timeout",
        correlationId,
        env: dependencies.env || process.env,
        metadata: {
          model: modelDecision.model,
          tier: modelDecision.tier,
          reasoningEffort: modelDecision.reasoningEffort,
          durationMs: Date.now() - startedAt,
        },
      });
    }
    throw error;
  }

  const validatedResponse = validateConversationResponse({
    visibleText: parsed.visibleText,
    actions: sanitizeEventMutations(
        sanitizeEventParticipants(parsed.actions, message, logger),
        message,
        logger),
    memories: parsed.memories,
    epistemic: parsed.epistemic,
  }, source);

  return {
    reply: validatedResponse.visibleText,
    actions: validatedResponse.actions,
    memories: validatedResponse.memories,
    epistemic: validatedResponse.epistemic,
  };
}

module.exports = {
  OPENAI_TIMEOUT_MS,
  buildBrainContext,
  runWithOpenAiDeadline,
  handleChatRequest,
};
