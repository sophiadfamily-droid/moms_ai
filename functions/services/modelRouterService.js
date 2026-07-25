const MODEL_TIERS = Object.freeze({
  FAST: "fast",
  BALANCED: "balanced",
  REASONING: "reasoning",
});

const DEFAULT_MODELS = Object.freeze({
  [MODEL_TIERS.FAST]: "gpt-5.6-luna",
  [MODEL_TIERS.BALANCED]: "gpt-5.6-terra",
  [MODEL_TIERS.REASONING]: "gpt-5.6-sol",
});

const REASONING_EFFORTS = Object.freeze({
  [MODEL_TIERS.FAST]: "none",
  [MODEL_TIERS.BALANCED]: "low",
  [MODEL_TIERS.REASONING]: "medium",
});

/**
 * Retourne le niveau de modèle adapté à l'intention détectée.
 *
 * Cette première version conserve un routage volontairement simple.
 * Les actions déterministes ne doivent pas utiliser un modèle plus
 * puissant que nécessaire.
 *
 * @param {Object} params paramètres de sélection
 * @param {string} params.primaryIntent intention principale
 * @param {boolean} params.requiresComplexPlanning planification complexe
 * @return {string}
 */
function selectModelTier({
  primaryIntent = "general",
  requiresComplexPlanning = false,
} = {}) {
  if (requiresComplexPlanning) {
    return MODEL_TIERS.REASONING;
  }

  if (primaryIntent === "task" || primaryIntent === "shopping") {
    return MODEL_TIERS.FAST;
  }

  return MODEL_TIERS.BALANCED;
}

/**
 * Résout l'identifiant de modèle associé à un niveau.
 *
 * Les variables d'environnement permettront d'activer de nouveaux
 * modèles sans modification du code ni exposition côté Flutter.
 *
 * @param {string} tier niveau demandé
 * @param {Object} env variables d'environnement
 * @return {string}
 */
function resolveModel(tier, env = process.env) {
  const configuredModels = {
    [MODEL_TIERS.FAST]: env.ZELIA_MODEL_FAST,
    [MODEL_TIERS.BALANCED]: env.ZELIA_MODEL_BALANCED,
    [MODEL_TIERS.REASONING]: env.ZELIA_MODEL_REASONING,
  };

  return configuredModels[tier] || DEFAULT_MODELS[tier];
}

/**
 * Construit la décision complète de routage.
 *
 * @param {Object} params paramètres de sélection
 * @param {string} params.primaryIntent intention principale
 * @param {boolean} params.requiresComplexPlanning planification complexe
 * @param {Object} params.env variables d'environnement
 * @return {{tier: string, model: string, reasoningEffort: string}}
 */
function routeModel({
  primaryIntent = "general",
  requiresComplexPlanning = false,
  env = process.env,
} = {}) {
  const tier = selectModelTier({
    primaryIntent,
    requiresComplexPlanning,
  });

  return {
    tier,
    model: resolveModel(tier, env),
    reasoningEffort: REASONING_EFFORTS[tier],
  };
}

module.exports = {
  MODEL_TIERS,
  DEFAULT_MODELS,
  REASONING_EFFORTS,
  selectModelTier,
  resolveModel,
  routeModel,
};
