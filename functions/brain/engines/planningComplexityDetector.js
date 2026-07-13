/* eslint-disable max-len */

/**
 * Normalise un texte pour rendre la détection déterministe
 * malgré les accents, apostrophes et variations de casse.
 *
 * @param {string} value texte à normaliser
 * @return {string}
 */
function normalizeText(value) {
  return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[’']/g, " ")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();
}

/**
 * Détecte si une demande nécessite une planification complexe.
 *
 * Une simple création de rendez-vous ou recherche de créneau reste
 * volontairement en niveau balanced. Le niveau reasoning est réservé
 * aux demandes globales qui combinent plusieurs éléments ou contraintes.
 *
 * @param {string} message message utilisateur
 * @return {{
 *   requiresComplexPlanning: boolean,
 *   score: number,
 *   reasons: string[]
 * }}
 */
function detectPlanningComplexity(message) {
  const text = normalizeText(message);

  if (!text) {
    return {
      requiresComplexPlanning: false,
      score: 0,
      reasons: [],
    };
  }

  const reasons = [];

  const explicitComplexPhrases = [
    "organise toute ma journee",
    "organiser toute ma journee",
    "planifie toute ma journee",
    "planifier toute ma journee",
    "organise ma semaine",
    "organiser ma semaine",
    "planifie ma semaine",
    "planifier ma semaine",
    "refais mon planning",
    "reorganise mon planning",
    "optimise mon planning",
    "optimiser mon planning",
    "organise mon emploi du temps",
    "organiser mon emploi du temps",
  ];

  const orchestrationTerms = [
    "organise",
    "organiser",
    "planifie",
    "planifier",
    "reorganise",
    "reorganiser",
    "optimise",
    "optimiser",
    "repartis",
    "repartir",
  ];

  const broadScopeTerms = [
    "toute ma journee",
    "ma journee",
    "mon planning",
    "mon emploi du temps",
    "ma semaine",
    "toute la semaine",
    "les prochains jours",
  ];

  const constraintTerms = [
    "en tenant compte",
    "prends en compte",
    "selon mes",
    "mes contraintes",
    "mes priorites",
    "mes horaires",
    "mes trajets",
    "l ecole",
    "ecole",
    "travail",
    "garde",
    "rendez vous",
    "taches",
    "courses",
    "avant ",
    "apres ",
    "finir avant",
    "disponibilites",
  ];

  const comparisonTerms = [
    "compare plusieurs",
    "plusieurs possibilites",
    "plusieurs options",
    "meilleure organisation",
    "meilleur planning",
    "differents scenarios",
    "differentes possibilites",
  ];

  const domainTerms = [
    "agenda",
    "rendez vous",
    "taches",
    "courses",
    "ecole",
    "travail",
    "enfant",
    "trajet",
    "repas",
    "activites",
  ];

  const hasExplicitComplexPhrase = explicitComplexPhrases.some(
      (phrase) => text.includes(phrase),
  );

  const hasOrchestration = orchestrationTerms.some(
      (term) => text.includes(term),
  );

  const hasBroadScope = broadScopeTerms.some(
      (term) => text.includes(term),
  );

  const matchedConstraints = constraintTerms.filter(
      (term) => text.includes(term),
  );

  const hasComparison = comparisonTerms.some(
      (term) => text.includes(term),
  );

  const matchedDomains = domainTerms.filter(
      (term) => text.includes(term),
  );

  if (hasExplicitComplexPhrase) {
    reasons.push("explicit_complex_planning");
  }

  if (hasOrchestration) {
    reasons.push("orchestration_request");
  }

  if (hasBroadScope) {
    reasons.push("broad_time_scope");
  }

  if (matchedConstraints.length >= 2) {
    reasons.push("multiple_constraints");
  }

  if (matchedDomains.length >= 3) {
    reasons.push("multiple_life_domains");
  }

  if (hasComparison) {
    reasons.push("scenario_comparison");
  }

  let score = 0;

  if (hasExplicitComplexPhrase) score += 3;
  if (hasOrchestration) score += 1;
  if (hasBroadScope) score += 1;
  if (matchedConstraints.length >= 2) score += 1;
  if (matchedDomains.length >= 3) score += 1;
  if (hasComparison) score += 2;

  const requiresComplexPlanning =
      hasExplicitComplexPhrase ||
      (hasOrchestration && hasBroadScope && score >= 3) ||
      (hasComparison && hasBroadScope) ||
      (hasOrchestration && matchedDomains.length >= 3);

  return {
    requiresComplexPlanning,
    score,
    reasons,
  };
}

module.exports = {
  normalizeText,
  detectPlanningComplexity,
};
