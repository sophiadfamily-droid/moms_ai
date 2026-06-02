/* eslint-disable max-len */

/**
 * Détecte une intention probable à partir du message utilisateur.
 * Cette première version est volontairement simple, lisible et stable.
 * @param {string} message message utilisateur
 * @return {Object}
 */
function detectIntent(message) {
  const text = (message || "").toLowerCase().trim();

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
    "j'ai plus",
    "il manque",
    "manque",
    "on n'a plus",
    "terminé",
    "fini",
    "épuisé",
    "besoin de",
    "ajoute aux courses",
    "mets dans les courses",
    "racheter",
    "reprendre",
  ];

  const taskKeywords = [
    "je dois",
    "il faut",
    "faut que",
    "penser à",
    "rappelle-moi",
    "fais-moi penser",
    "ne pas oublier",
    "appeler",
    "envoyer",
    "payer",
    "répondre",
    "relancer",
    "réserver",
    "organiser",
    "préparer",
    "chercher",
    "récupérer",
    "déposer",
    "comparer",
    "vérifier",
  ];

  const eventKeywords = [
    "rdv",
    "rendez-vous",
    "j'ai rendez-vous",
    "réunion",
    "consultation",
    "cours",
    "séance",
    "entraînement",
    "anniversaire",
    "vol",
    "train",
    "restaurant",
    "dîner",
    "déjeuner",
    "appel prévu",
  ];

  const reasons = [];

  const hasShopping = shoppingKeywords.some((keyword) => text.includes(keyword));
  const hasTask = taskKeywords.some((keyword) => text.includes(keyword));
  const hasEvent = eventKeywords.some((keyword) => text.includes(keyword));

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
  detectIntent,
};
