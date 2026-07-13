const assert = require("node:assert/strict");
const test = require("node:test");

const {
  detectIntent,
} = require("../../brain/engines/intentDetector");

const {
  detectPlanningComplexity,
} = require("../../brain/engines/planningComplexityDetector");

const {
  MODEL_TIERS,
  routeModel,
} = require("../../services/modelRouterService");

const TEST_MODELS = Object.freeze({
  ZELIA_MODEL_FAST: "test-fast-model",
  ZELIA_MODEL_BALANCED: "test-balanced-model",
  ZELIA_MODEL_REASONING: "test-reasoning-model",
});

/**
 * Reproduit le routage réellement effectué dans functions/index.js.
 *
 * @param {string} message message utilisateur
 * @return {{
 *   intent: Object,
 *   complexity: Object,
 *   decision: Object
 * }}
 */
function routeMessage(message) {
  const intent = detectIntent(message);
  const complexity = detectPlanningComplexity(message);

  const decision = routeModel({
    primaryIntent: intent.primaryIntent,
    requiresComplexPlanning:
        complexity.requiresComplexPlanning,
    env: TEST_MODELS,
  });

  return {
    intent,
    complexity,
    decision,
  };
}

test("routes a simple shopping request to the fast model", () => {
  const result = routeMessage(
      "Ajoute du lait et de l'eau aux courses",
  );

  assert.equal(result.intent.primaryIntent, "shopping");
  assert.equal(
      result.complexity.requiresComplexPlanning,
      false,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.FAST,
    model: "test-fast-model",
  });
});

test("routes a simple task to the fast model", () => {
  const result = routeMessage(
      "Rappelle-moi d'appeler l'assurance",
  );

  assert.equal(result.intent.primaryIntent, "task");
  assert.equal(
      result.complexity.requiresComplexPlanning,
      false,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.FAST,
    model: "test-fast-model",
  });
});

test("routes a standard appointment to the balanced model", () => {
  const result = routeMessage(
      "J'ai rendez-vous chez le médecin demain à 14h",
  );

  assert.equal(result.intent.primaryIntent, "event");
  assert.equal(
      result.complexity.requiresComplexPlanning,
      false,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.BALANCED,
    model: "test-balanced-model",
  });
});

test("keeps a simple slot search on the balanced model", () => {
  const result = routeMessage(
      "Trouve-moi un créneau pour le dentiste la semaine prochaine",
  );

  assert.equal(result.intent.primaryIntent, "event");
  assert.equal(
      result.complexity.requiresComplexPlanning,
      false,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.BALANCED,
    model: "test-balanced-model",
  });
});

test("routes full-day organization to the reasoning model", () => {
  const result = routeMessage(
      "Organise toute ma journée en tenant compte de l'école, " +
      "de mes rendez-vous, de mes tâches et de mes trajets",
  );

  assert.equal(
      result.complexity.requiresComplexPlanning,
      true,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.REASONING,
    model: "test-reasoning-model",
  });
});

test("routes weekly scenario comparison to the reasoning model", () => {
  const result = routeMessage(
      "Compare plusieurs possibilités pour organiser ma semaine",
  );

  assert.equal(
      result.complexity.requiresComplexPlanning,
      true,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.REASONING,
    model: "test-reasoning-model",
  });
});

test("routes an ordinary general question to the balanced model", () => {
  const result = routeMessage(
      "Explique-moi comment mieux organiser mes documents",
  );

  assert.equal(result.intent.primaryIntent, "general");
  assert.equal(
      result.complexity.requiresComplexPlanning,
      false,
  );
  assert.deepEqual(result.decision, {
    tier: MODEL_TIERS.BALANCED,
    model: "test-balanced-model",
  });
});
