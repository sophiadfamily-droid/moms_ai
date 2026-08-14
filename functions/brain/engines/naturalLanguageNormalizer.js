"use strict";

const SAFE_TOKEN_REPLACEMENTS = Object.freeze({
  prebdre: "prendre",
  ajoutr: "ajouter",
  demian: "demain",
  deamin: "demain",
  deman: "demain",
  dem1: "demain",
  dmain: "demain",
  apresdemain: "apres demain",
  mtn: "maintenant",
  rapel: "rappel",
  rdv: "rendez vous",
  rendezvous: "rendez vous",
  rendezvou: "rendez vous",
  rendevous: "rendez vous",
  rendevouz: "rendez vous",
  rendezvouz: "rendez vous",
  crenau: "creneau",
  crenaux: "creneau",
  creneux: "creneau",
  heur: "heure",
  heurs: "heure",
  hure: "heure",
  hures: "heure",
  minut: "minute",
  mins: "minutes",
  stp: "s il te plait",
  svp: "s il vous plait",
  aujourdhui: "aujourd hui",
  auj: "aujourd hui",
  ajd: "aujourd hui",
  ojd: "aujourd hui",
  aprem: "apres midi",
  proposemoi: "propose moi",
  trouvemoi: "trouve moi",
  cherchemoi: "cherche moi",
  calemoi: "cale moi",
  ajoutemoi: "ajoute moi",
  rappellemoi: "rappelle moi",
  jveux: "je veux",
  jvoudrais: "je voudrais",
  doeuf: "d oeuf",
  doeufs: "d oeufs",
});

const UNDERSTANDING_LEVELS = Object.freeze([
  "exactMatch",
  "normalizedMatch",
  "probableMatch",
  "ambiguous",
  "noMatch",
]);
const NEGATED_ACTION = new RegExp(
    String.raw`\b(?:ne|n)\s+(?:cree|creer|ajoute|ajouter|annule|annuler|` +
    String.raw`supprime|supprimer|decale|deplacer|veux)\b.{0,40}` +
    String.raw`\b(?:pas|plus)\b`,
);
const ACTION_TOKEN = new RegExp(
    String.raw`\b(?:cree|ajoute|achete|annule|decale|deplace|supprime|` +
    String.raw`rappelle|planifie|cale)\b`,
    "g",
);

/**
 * Applies only bounded transformations that do not change user intent.
 *
 * @param {unknown} input source text
 * @return {{
 *  originalText: string,
 *  normalizedText: string,
 *  tokens: string[],
 *  detectedLanguage: string,
 *  normalizationCodes: string[],
 *  preservedAmbiguities: string[]
 * }}
 */
function normalizeNaturalLanguage(input) {
  const originalText = String(input || "");
  const normalizationCodes = [];
  const preservedAmbiguities = [];
  let value = originalText.trim();
  if (value !== originalText) normalizationCodes.push("trimmed");
  const lower = value.toLowerCase();
  if (lower !== value) normalizationCodes.push("lowercased");
  value = lower.replace(/[’‘`´]/g, "'");
  if (value !== lower) normalizationCodes.push("apostrophe_normalized");
  const folded = value.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .replace(/œ/g, "oe");
  if (folded !== value) normalizationCodes.push("accents_folded");
  value = folded
      .replace(/['-]/g, " ")
      // A colon is meaningful inside a clock expression such as 14:30.
      .replace(/[.!?;,()[\]{}"…]+/g, " ")
      .replace(/[\u{1F300}-\u{1FAFF}]/gu, " ")
      .replace(/\s+/g, " ")
      .trim();

  const beforeOral = value;
  value = value
      .replace(/^jai\b/, "j ai")
      .replace(/^ya\b/, "y a")
      .replace(/^jveu\b/, "je veux")
      .replace(/^je veu\b/, "je veux")
      .replace(/\bneuf heure et demie\b/g, "09:30")
      .replace(/\bneuf heures trente\b/g, "09:30")
      .replace(/\bneuf heure\b/g, "09:00");
  if (value !== beforeOral) {
    normalizationCodes.push("oral_form_normalized");
  }

  let corrected = false;
  const tokens = value ? value.split(" ") : [];
  const correctedTokens = [];
  for (const token of tokens) {
    const replacement = SAFE_TOKEN_REPLACEMENTS[token];
    if (replacement) {
      correctedTokens.push(...replacement.split(" "));
      corrected = true;
    } else {
      correctedTokens.push(token);
    }
  }
  value = correctedTokens.join(" ");
  if (corrected) normalizationCodes.push("safe_typo_corrected");

  const beforePhrases = value;
  value = value
      .replace(
          new RegExp(
              String.raw`\b(?:la\s+)?(?:sem|semain|semiane|semaine)\s+` +
              String.raw`(?:proch|prochane|prochiane|prochaine)\b`,
              "g",
          ),
          "la semaine prochaine",
      )
      .replace(/\s+/g, " ")
      .trim();
  if (value !== beforePhrases) {
    normalizationCodes.push("safe_phrase_normalized");
  }

  if (/\b(?:je veux|ajoute)\s+plus\b/.test(value)) {
    preservedAmbiguities.push("positive_or_quantity_plus");
  }
  if (/\b(?:j ai|y a|on a)\s+plus\b/.test(value) &&
      !/\b(?:ne|n)\b/.test(value)) {
    preservedAmbiguities.push("stockout_or_additional_plus");
  }
  if (NEGATED_ACTION.test(value) ||
      /\b(?:cree|ajoute|annule|supprime|decale|veux)\s+pas\b/.test(value)) {
    preservedAmbiguities.push("critical_negation_scope");
  }
  if (/^(?:mets|met|decale)\s+(?:le|la|l)\b/.test(value)) {
    preservedAmbiguities.push("unresolved_reference");
  }
  const actionCount = (value.match(ACTION_TOKEN) || []).length;
  if (actionCount > 1 && /\b(?:et|puis|ensuite)\b/.test(value)) {
    preservedAmbiguities.push("multiple_actions");
  }
  if (hasNegationNormalized(value)) {
    normalizationCodes.push("negation_preserved");
  }

  return Object.freeze({
    originalText,
    normalizedText: value,
    tokens: Object.freeze(value ? value.split(" ") : []),
    detectedLanguage: detectLanguage(value),
    normalizationCodes: Object.freeze(normalizationCodes),
    preservedAmbiguities: Object.freeze(preservedAmbiguities),
  });
}

/**
 * @param {string} normalized normalized text
 * @return {boolean}
 */
function hasNegationNormalized(normalized) {
  return /\b(?:ne|n|pas|jamais|aucun|aucune|rien|personne|plus)\b/
      .test(normalized);
}

/**
 * @param {string} value normalized text
 * @return {string}
 */
function detectLanguage(value) {
  if (!value) return "und";
  const matches = value.match(
      /\b(?:je|tu|il|elle|nous|vous|les|des|une|pour|demain|rendez|tache)\b/g,
  );
  return matches && matches.length > 0 ? "fr" : "und";
}

module.exports = {
  UNDERSTANDING_LEVELS,
  normalizeNaturalLanguage,
  hasNegationNormalized,
};
