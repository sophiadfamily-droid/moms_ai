const MAX_PARTICIPANT_LABEL_LENGTH = 120;

const DISALLOWED_REFERENCES = new Set([
  "il", "elle", "lui", "eux", "elles", "on",
  "mon pere", "ma mere", "mes parents", "mon enfant", "mes enfants",
  "mon fils", "ma fille", "mon conjoint", "ma conjointe", "mon partenaire",
  "ma partenaire", "mon medecin", "mon docteur", "ma docteure",
]);

const DISALLOWED_REFERENCE_PREFIXES = new Set([
  "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
  "notre", "nos", "votre", "vos", "leur", "leurs",
]);

/**
 * Normalisation conservatrice utilisée uniquement pour vérifier qu'un
 * libellé proposé est littéralement présent dans le message utilisateur.
 * Elle ne traduit, ne corrige et ne déduit rien.
 *
 * @param {*} value valeur à normaliser
 * @return {string} suite de mots comparable
 */
function comparisonText(value) {
  if (typeof value !== "string") return "";
  return value
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLocaleLowerCase("fr-FR")
      .replace(/[’']/g, " ")
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .trim()
      .replace(/\s+/g, " ");
}

/**
 * Valide une proposition de participant et sa présence littérale dans
 * l'entrée utilisateur. Le résultat du modèle n'est jamais une preuve.
 *
 * @param {*} participant participant structuré proposé
 * @param {string} userMessage message utilisateur original
 * @return {Object|null} participant sûr ou null
 */
function validateExplicitEventParticipant(participant, userMessage) {
  if (
    !participant ||
    typeof participant !== "object" ||
    Array.isArray(participant)
  ) {
    return null;
  }

  const keys = Object.keys(participant);
  const allowedKeys = ["label", "entityType", "evidence"];
  if (
    keys.length !== allowedKeys.length ||
    keys.some((key) => !allowedKeys.includes(key)) ||
    typeof participant.label !== "string" ||
    participant.entityType !== "person" ||
    participant.evidence !== "explicit_user_input"
  ) {
    return null;
  }

  const label = participant.label.trim().replace(/\s+/g, " ");
  if (!label || label.length > MAX_PARTICIPANT_LABEL_LENGTH) return null;

  const comparableLabel = comparisonText(label);
  const comparableMessage = comparisonText(userMessage);
  const firstLabelWord = comparableLabel.split(" ")[0];
  if (
    !comparableLabel ||
    DISALLOWED_REFERENCES.has(comparableLabel) ||
    DISALLOWED_REFERENCE_PREFIXES.has(firstLabelWord) ||
    !(` ${comparableMessage} `.includes(` ${comparableLabel} `))
  ) {
    return null;
  }

  return Object.freeze({
    label,
    entityType: "person",
    evidence: "explicit_user_input",
  });
}

/**
 * Retire les participants non prouvés sans invalider le reste de l'action.
 *
 * @param {*} actions actions générées
 * @param {string} userMessage message utilisateur original
 * @param {Object} logger logger injecté
 * @return {Array} copies assainies des actions
 */
function sanitizeEventParticipants(actions, userMessage, logger = console) {
  if (!Array.isArray(actions)) return [];

  return actions.map((rawAction) => {
    if (
      !rawAction ||
      typeof rawAction !== "object" ||
      Array.isArray(rawAction)
    ) {
      return rawAction;
    }
    const action = {...rawAction};
    if (!("participant" in action)) return action;

    const participant = action.type === "event" ?
      validateExplicitEventParticipant(action.participant, userMessage) :
      null;
    if (participant == null) {
      delete action.participant;
      logger.info("EVENT PARTICIPANT REMOVED", {
        code: "invalid_event_participant_removed",
      });
    } else {
      action.participant = participant;
    }
    return action;
  });
}

module.exports = {
  MAX_PARTICIPANT_LABEL_LENGTH,
  comparisonText,
  sanitizeEventParticipants,
  validateExplicitEventParticipant,
};
