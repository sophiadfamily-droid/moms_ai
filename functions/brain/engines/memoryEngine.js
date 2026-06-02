/* eslint-disable max-len */

/**
 * Moteur mémoire de Zelia.
 * Cette première version centralise les règles simples de mémoire.
 */
class MemoryEngine {
  /**
   * Vérifie si un texte ressemble à une information durable à mémoriser.
   * @param {string} text
   * @return {boolean}
   */
  static looksLikePersistentMemory(text) {
    const value = (text || "").toLowerCase().trim();

    if (!value) {
      return false;
    }

    const memoryTriggers = [
      "souviens-toi",
      "rappelle-toi",
      "retenir",
      "mémorise",
      "garde en mémoire",
      "à partir de maintenant",
      "dorénavant",
      "habituellement",
      "tous les jours",
      "toutes les semaines",
      "chaque semaine",
      "chaque mois",
    ];

    return memoryTriggers.some((trigger) => value.includes(trigger));
  }

  /**
   * Retourne une catégorie mémoire simple.
   * @param {string} text
   * @return {string}
   */
  static categorizeMemory(text) {
    const value = (text || "").toLowerCase();

    if (
      value.includes("école") ||
      value.includes("enfant") ||
      value.includes("famille")
    ) {
      return "family";
    }

    if (
      value.includes("travail") ||
      value.includes("business") ||
      value.includes("projet")
    ) {
      return "work";
    }

    if (
      value.includes("sport") ||
      value.includes("santé") ||
      value.includes("rdv médical")
    ) {
      return "health";
    }

    return "personal";
  }

  /**
   * Construit un objet mémoire standard.
   * @param {string} text
   * @return {Object}
   */
  static buildMemory(text) {
    return {
      text,
      category: MemoryEngine.categorizeMemory(text),
    };
  }
}

module.exports = MemoryEngine;
