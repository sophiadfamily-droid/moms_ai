/* eslint-disable max-len */

/**
 * Moteur de planification de Zelia.
 * Cette première version centralise les règles simples de planning.
 */
class PlannerEngine {
  /**
   * Vérifie si une action doit demander une durée.
   * @param {Object} action
   * @return {boolean}
   */
  static needsDuration(action) {
    if (!action || action.type !== "event") {
      return false;
    }

    const duration = Number(action.durationMinutes || 0);
    return duration <= 0;
  }

  /**
   * Vérifie si une action agenda semble complète.
   * @param {Object} action
   * @return {boolean}
   */
  static isEventReady(action) {
    if (!action || action.type !== "event") {
      return false;
    }

    return Boolean(action.date && action.time && action.durationMinutes > 0);
  }

  /**
   * Retourne la prochaine question logique pour un événement incomplet.
   * @param {Object} action
   * @return {string}
   */
  static nextMissingEventStep(action) {
    if (!action || action.type !== "event") {
      return "unknown";
    }

    if (!action.date) return "date";
    if (!action.time) return "time";
    if (!action.durationMinutes || action.durationMinutes <= 0) {
      return "duration";
    }

    return "ready";
  }
}

module.exports = PlannerEngine;
