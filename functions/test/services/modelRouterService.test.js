const assert = require("node:assert/strict");
const test = require("node:test");

const {
  MODEL_TIERS,
  REASONING_EFFORTS,
  selectModelTier,
  resolveModel,
  routeModel,
} = require("../../services/modelRouterService");

test("routes task and shopping intents to the fast tier", () => {
  assert.equal(
      selectModelTier({primaryIntent: "task"}),
      MODEL_TIERS.FAST,
  );

  assert.equal(
      selectModelTier({primaryIntent: "shopping"}),
      MODEL_TIERS.FAST,
  );
});

test("routes standard conversation and events to the balanced tier", () => {
  assert.equal(
      selectModelTier({primaryIntent: "general"}),
      MODEL_TIERS.BALANCED,
  );

  assert.equal(
      selectModelTier({primaryIntent: "event"}),
      MODEL_TIERS.BALANCED,
  );
});

test("routes complex planning to the reasoning tier", () => {
  assert.equal(
      selectModelTier({
        primaryIntent: "event",
        requiresComplexPlanning: true,
      }),
      MODEL_TIERS.REASONING,
  );
});

test("uses safe default models when no configuration exists", () => {
  assert.equal(
      resolveModel(MODEL_TIERS.FAST, {}),
      "gpt-5.6-luna",
  );

  assert.equal(
      resolveModel(MODEL_TIERS.BALANCED, {}),
      "gpt-5.6-terra",
  );

  assert.equal(
      resolveModel(MODEL_TIERS.REASONING, {}),
      "gpt-5.6-sol",
  );
});

test("selects an explicit reasoning effort for every tier", () => {
  assert.deepEqual(REASONING_EFFORTS, {
    [MODEL_TIERS.FAST]: "none",
    [MODEL_TIERS.BALANCED]: "low",
    [MODEL_TIERS.REASONING]: "medium",
  });
});

test("uses configured models without changing application code", () => {
  const decision = routeModel({
    primaryIntent: "task",
    env: {
      ZELIA_MODEL_FAST: "future-fast-model",
    },
  });

  assert.deepEqual(decision, {
    tier: MODEL_TIERS.FAST,
    model: "future-fast-model",
    reasoningEffort: "none",
  });
});
