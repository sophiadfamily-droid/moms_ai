/* eslint-disable max-len */
const {
  normalizeNaturalLanguage,
} = require("./naturalLanguageNormalizer");

/**
 * Normalise le texte avant détection.
 *
 * @param {string} value texte source
 * @return {string}
 */
function normalizeText(value) {
  return normalizeNaturalLanguage(value).normalizedText
      .replace(/[^a-z0-9]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
}

/**
 * Vérifie une expression complète sans confondre des sous-chaînes.
 *
 * Exemple : "cours" ne doit pas correspondre à "courses".
 *
 * @param {string} text texte déjà normalisé
 * @param {string} phrase expression recherchée
 * @return {boolean}
 */
function containsPhrase(text, phrase) {
  const normalizedPhrase = normalizeText(phrase);

  if (!text || !normalizedPhrase) {
    return false;
  }

  return (` ${text} `).includes(` ${normalizedPhrase} `);
}

const TASK_CREATION_PHRASES = [
  "cree une tache",
  "creer une tache",
  "ajoute une tache",
  "note moi une tache",
  "mets dans mes taches",
  "ajoute a ma liste de taches",
];

/**
 * Extrait uniquement les données certaines d'une création de tâche explicite.
 *
 * @param {string} message message utilisateur
 * @param {Date} referenceDate date de référence injectée
 * @return {{isCreation: boolean, title: string, priority: string,
 *   isImportant: boolean, dueDate: string}}
 */
function extractTaskCreation(message, referenceDate = new Date()) {
  const text = normalizeText(message);
  const phrase = TASK_CREATION_PHRASES.find(
      (candidate) => containsPhrase(text, candidate),
  );
  if (!phrase) {
    return {
      isCreation: false,
      title: "",
      priority: "",
      isImportant: false,
      dueDate: "",
    };
  }
  let remainder = ` ${text} `.replace(` ${phrase} `, " ").trim();
  const highPriority = /\b(prioritaire|priorite haute|haute priorite|urgent)\b/
      .test(remainder);
  const tomorrow = /\bdemain\b/.test(remainder);
  remainder = remainder
      .replace(/\b(prioritaire|priorite haute|haute priorite|urgent)\b/g, " ")
      .replace(/\b(pour|a faire|echeance)\b/g, " ")
      .replace(/\bdemain\b/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  const due = new Date(referenceDate);
  due.setUTCDate(due.getUTCDate() + 1);
  return {
    isCreation: true,
    title: remainder,
    priority: highPriority ? "high" : "",
    isImportant: highPriority,
    dueDate: tomorrow ? due.toISOString().slice(0, 10) : "",
  };
}

/**
 * Détecte une intention probable à partir du message utilisateur.
 *
 * Cette détection reste déterministe, rapide et sans coût OpenAI.
 *
 * @param {string} message message utilisateur
 * @return {{
 *   primaryIntent: string,
 *   confidence: number,
 *   reasons: string[]
 * }}
 */
function detectIntent(message) {
  const normalization = normalizeNaturalLanguage(message);
  const text = normalization.normalizedText;

  if (!text) {
    return {
      primaryIntent: "unknown",
      confidence: 0,
      reasons: [],
      understandingLevel: "noMatch",
      candidateIntents: [],
      ambiguityType: null,
      actionAllowed: false,
      normalization,
    };
  }

  const shoppingKeywords = [
    "plus de",
    "plus d",
    "j ai plus",
    "il manque",
    "manque",
    "on n a plus",
    "termine",
    "fini",
    "epuise",
    "besoin de",
    "ajoute aux courses",
    "ajoute a la liste de courses",
    "mets dans les courses",
    "mets sur la liste de courses",
    "aux courses",
    "liste de courses",
    "racheter",
    "reprendre",
  ];

  const taskKeywords = [
    "je dois",
    "il faut",
    "faut que",
    "penser a",
    "rappelle moi",
    "fais moi penser",
    "ne pas oublier",
    "appeler",
    "envoyer",
    "payer",
    "repondre",
    "relancer",
    "reserver",
    "preparer",
    "chercher",
    "recuperer",
    "deposer",
    "comparer",
    "verifier",
  ];

  const eventKeywords = [
    "rdv",
    "rendez vous",
    "j ai rendez vous",
    "reunion",
    "consultation",
    "cours",
    "seance",
    "entrainement",
    "anniversaire",
    "vol",
    "train",
    "restaurant",
    "diner",
    "dejeuner",
    "appel prevu",
    "dentiste",
    "medecin",
    "docteur",
    "pediatre",
    "kine",
    "osteopathe",
    "hopital",
    "clinique",
    "creneau",
    "trouve moi un creneau",
    "propose moi un creneau",
    "cherche moi un creneau",
    "place moi un rendez vous",
  ];

  const reasons = [];
  const nonCreationTaskContexts = [
    "definition",
    "definis",
    "que veut dire",
    "cette tache est",
    "si je",
    "supposons",
    "imagine",
    "citation",
  ];
  const hasExplicitTaskCreation = TASK_CREATION_PHRASES.some(
      (phrase) => containsPhrase(text, phrase),
  ) && !nonCreationTaskContexts.some(
      (phrase) => containsPhrase(text, phrase),
  );

  const hasShopping = shoppingKeywords.some(
      (keyword) => containsPhrase(text, keyword),
  );

  const hasTask = hasExplicitTaskCreation || taskKeywords.some(
      (keyword) => containsPhrase(text, keyword),
  );

  const hasEvent = eventKeywords.some(
      (keyword) => containsPhrase(text, keyword),
  );

  if (hasShopping) reasons.push("shopping_keyword");
  if (hasTask) {
    reasons.push(
        hasExplicitTaskCreation ? "task_creation_phrase" : "task_keyword",
    );
  }
  if (hasEvent) reasons.push("event_keyword");

  const candidates = [
    ifIntent(hasShopping, "shopping"),
    ifIntent(hasTask, "task"),
    ifIntent(hasEvent, "event"),
  ].filter(Boolean);
  const criticalNegation =
      /\b(?:ne|n)\s+\w*(?:\s+\w+){0,4}\s+(?:pas|plus|jamais)\b/.test(text) ||
      /\b(?:annule|supprime|cree|ajoute|deplace|veux)\s+pas\b/.test(text) ||
      /^(?:pas|non)\b/.test(text);
  const ambiguities = normalization.preservedAmbiguities;
  const ambiguousPlus = ambiguities.includes("positive_or_quantity_plus") ||
      ambiguities.includes("stockout_or_additional_plus");
  const unresolvedReference = ambiguities.includes("unresolved_reference");
  const multipleActions = ambiguities.includes("multiple_actions") ||
      candidates.length > 1;
  if (criticalNegation || ambiguousPlus ||
      unresolvedReference || multipleActions) {
    return {
      primaryIntent: candidates.length === 1 ? candidates[0] : "unknown",
      confidence: 0,
      reasons: [...reasons, criticalNegation ?
        "critical_negation" : "multiple_or_ambiguous_meanings"],
      understandingLevel: "ambiguous",
      candidateIntents: candidates,
      ambiguityType: criticalNegation ? "negation_scope" :
        ambiguousPlus ? "plus_meaning" :
          unresolvedReference ? "unresolved_reference" : "multiple_intents",
      actionAllowed: false,
      normalization,
    };
  }

  if (hasEvent) {
    return {
      primaryIntent: "event",
      confidence: 0.85,
      reasons,
      understandingLevel: matchLevel(normalization),
      candidateIntents: ["event"],
      ambiguityType: null,
      actionAllowed: false,
      normalization,
    };
  }

  if (hasShopping) {
    return {
      primaryIntent: "shopping",
      confidence: 0.8,
      reasons,
      understandingLevel: matchLevel(normalization),
      candidateIntents: ["shopping"],
      ambiguityType: null,
      actionAllowed: false,
      normalization,
    };
  }

  if (hasTask) {
    return {
      primaryIntent: "task",
      confidence: 0.75,
      reasons,
      understandingLevel: matchLevel(normalization),
      candidateIntents: ["task"],
      ambiguityType: null,
      actionAllowed: false,
      normalization,
    };
  }

  return {
    primaryIntent: "general",
    confidence: 0.4,
    reasons,
    understandingLevel: "noMatch",
    candidateIntents: ["general"],
    ambiguityType: null,
    actionAllowed: false,
    normalization,
  };
}

/**
 * @param {boolean} condition whether the intent matched
 * @param {string} intent intent code
 * @return {string|null}
 */
function ifIntent(condition, intent) {
  return condition ? intent : null;
}

/**
 * @param {{normalizationCodes: string[]}} normalization normalization result
 * @return {string}
 */
function matchLevel(normalization) {
  return normalization.normalizationCodes.length === 0 ?
    "exactMatch" : "normalizedMatch";
}

module.exports = {
  normalizeText,
  containsPhrase,
  extractTaskCreation,
  detectIntent,
  normalizeNaturalLanguage,
};
