/* eslint-disable max-len */

/**
 * Normalise le texte avant détection.
 *
 * @param {string} value texte source
 * @return {string}
 */
function normalizeText(value) {
  return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[’']/g, " ")
      .toLowerCase()
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
  const text = normalizeText(message);

  if (!text) {
    return {
      primaryIntent: "unknown",
      confidence: 0,
      reasons: [],
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

  const hasShopping = shoppingKeywords.some(
      (keyword) => containsPhrase(text, keyword),
  );

  const hasTask = taskKeywords.some(
      (keyword) => containsPhrase(text, keyword),
  );

  const hasEvent = eventKeywords.some(
      (keyword) => containsPhrase(text, keyword),
  );

  if (hasShopping) reasons.push("shopping_keyword");
  if (hasTask) reasons.push("task_keyword");
  if (hasEvent) reasons.push("event_keyword");

  if (hasEvent) {
    return {
      primaryIntent: "event",
      confidence: 0.85,
      reasons,
    };
  }

  if (hasShopping) {
    return {
      primaryIntent: "shopping",
      confidence: 0.8,
      reasons,
    };
  }

  if (hasTask) {
    return {
      primaryIntent: "task",
      confidence: 0.75,
      reasons,
    };
  }

  return {
    primaryIntent: "general",
    confidence: 0.4,
    reasons,
  };
}

module.exports = {
  normalizeText,
  containsPhrase,
  detectIntent,
};
