/* eslint-disable max-len */

/**
 * Builder central des réponses utilisateur.
 */
class ResponseBuilder {
  /**
   * Réponse après création d'une tâche.
   * @param {string} title
   * @return {string}
   */
  static taskCreated(title) {
    return "Je le garde dans tes tâches 💕";
  }

  /**
   * Réponse après ajout aux courses.
   * @param {string[]} items
   * @return {string}
   */
  static shoppingAdded(items) {
    if (!items || items.length === 0) {
      return "Je l’ai ajouté aux courses 💕";
    }

    if (items.length === 1) {
      return `J’ai ajouté ${items[0]} aux courses 💕`;
    }

    return `J’ai ajouté ${items.join(", ")} aux courses 💕`;
  }

  /**
   * Réponse quand une durée est manquante.
   * @param {string} title
   * @return {string}
   */
  static eventNeedsDuration(title) {
    return `Je prépare « ${title} » 💕\n\nIl me manque juste la durée.`;
  }

  /**
   * Réponse après création d'un événement.
   * @param {string} title
   * @return {string}
   */
  static eventCreated(title) {
    return `C’est noté 💕 J’ai ajouté « ${title} » à ton agenda.`;
  }

  /**
   * Réponse de secours.
   * @return {string}
   */
  static fallback() {
    return "Je suis là 💕";
  }
}

module.exports = ResponseBuilder;
