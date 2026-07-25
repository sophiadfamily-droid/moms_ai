const MAX_TITLE_LENGTH = 120;
const MAX_CATEGORY_LENGTH = 80;
const MAX_NOTES_LENGTH = 1000;
const {
  comparisonText,
  validateExplicitEventParticipant,
} = require("./eventParticipantContract");

const TARGET_KEYS = new Set(["title", "date", "time", "category"]);
const CHANGE_KEYS = new Set([
  "title", "date", "time", "durationMinutes", "travelGoMinutes",
  "travelBackMinutes", "marginMinutes", "notes", "category",
]);

/**
 * Nettoie un texte borné sans l'interpréter.
 * @param {*} value valeur reçue
 * @param {number} maximum longueur maximale
 * @return {string|null} texte sûr ou null
 */
function cleanText(value, maximum) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().replace(/\s+/g, " ");
  if (cleaned.length > maximum) return null;
  return cleaned;
}

/**
 * Vérifie qu'un objet ne contient que des clés autorisées.
 * @param {*} value valeur reçue
 * @param {Set<string>} allowed clés autorisées
 * @return {boolean} résultat fermé
 */
function exactKeys(value, allowed) {
  return value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).every((key) => allowed.has(key));
}

/**
 * Vérifie le format de date fermé du contrat.
 * @param {string} value date reçue
 * @return {boolean} format accepté
 */
function validDate(value) {
  return value === "" || /^\d{4}-\d{2}-\d{2}$/.test(value);
}

/**
 * Vérifie le format d'heure fermé du contrat.
 * @param {string} value heure reçue
 * @return {boolean} format accepté
 */
function validTime(value) {
  return value === "" || /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
}

/**
 * Vérifie une valeur entière bornée.
 * @param {*} value valeur reçue
 * @param {number} minimum borne minimale
 * @param {number} maximum borne maximale
 * @return {boolean} valeur acceptée
 */
function boundedInteger(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

/**
 * Valide et copie une mutation d'événement fermée.
 * @param {*} action action reçue
 * @param {string} userMessage message utilisateur original
 * @return {Object|null} mutation sûre ou null
 */
function validateEventMutation(action, userMessage = "") {
  if (!action || action.type !== "event_mutation" ||
      !exactKeys(action.target, TARGET_KEYS)) return null;

  const target = {};
  for (const [key, maximum] of Object.entries({
    title: MAX_TITLE_LENGTH, date: 10, time: 5, category: MAX_CATEGORY_LENGTH,
  })) {
    if (!(key in action.target) || action.target[key] === null) continue;
    const value = cleanText(action.target[key], maximum);
    if (value == null || value === "") return null;
    target[key] = value;
  }
  if (Object.keys(target).length === 0 ||
      (target.date && !validDate(target.date)) ||
      (target.time && !validTime(target.time))) return null;
  const message = comparisonText(userMessage);
  const targetEvidence = [target.title, target.category]
      .filter((value) => value)
      .every((value) => (` ${message} `)
          .includes(` ${comparisonText(value)} `));
  if (!targetEvidence) return null;

  if (action.operation === "replace_participant") {
    if (!exactKeys(action, new Set([
      "type", "operation", "target", "participant",
    ]))) return null;
    const participant = validateExplicitEventParticipant(
        action.participant, userMessage);
    const explicitReplacement = ["remplace", "remplacer", "change", "changer"]
        .some((term) => (` ${message} `).includes(` ${term} `));
    if (participant == null || !explicitReplacement) return null;
    return {type: "event_mutation", operation: action.operation, target,
      participant};
  }

  if (action.operation === "remove_participant") {
    if (!exactKeys(action, new Set(["type", "operation", "target"]))) {
      return null;
    }
    const explicitRemoval = ["retire", "retirer", "enleve", "enlever"]
        .some((term) => (` ${message} `).includes(` ${term} `));
    const participantSubject = ["participant", "personne"]
        .some((term) => (` ${message} `).includes(` ${term} `));
    const namedRemoval =
      /\b(?:retire|enleve)\s+.+\s+(?:de|du)\s+/.test(message);
    const deletesEvent = new RegExp(
        "\\b(?:retire|enleve)\\s+" +
        "(?:(?:le|la|mon|ma)\\s+)?(?:evenement|rendez vous)\\b",
    ).test(message);
    if (!explicitRemoval || deletesEvent ||
        (!participantSubject && !namedRemoval)) return null;
    return {type: "event_mutation", operation: action.operation, target};
  }

  if (action.operation !== "update" ||
      !exactKeys(action, new Set(["type", "operation", "target", "changes"])) ||
      !exactKeys(action.changes, CHANGE_KEYS)) return null;

  const changes = {};
  const textLimits = {title: MAX_TITLE_LENGTH, date: 10, time: 5,
    notes: MAX_NOTES_LENGTH, category: MAX_CATEGORY_LENGTH};
  for (const [key, maximum] of Object.entries(textLimits)) {
    if (!(key in action.changes) || action.changes[key] === null) continue;
    const value = cleanText(action.changes[key], maximum);
    if (value == null || (key !== "notes" && value === "")) return null;
    changes[key] = value;
  }
  const integerLimits = {durationMinutes: [1, 1440], travelGoMinutes: [0, 480],
    travelBackMinutes: [0, 480], marginMinutes: [0, 240]};
  for (const [key, limits] of Object.entries(integerLimits)) {
    if (!(key in action.changes) || action.changes[key] === null) continue;
    if (!boundedInteger(action.changes[key], limits[0], limits[1])) return null;
    changes[key] = action.changes[key];
  }
  if ((changes.date && !validDate(changes.date)) ||
      (changes.time && !validTime(changes.time)) ||
      Object.keys(changes).length === 0) return null;
  const hasExplicitMutation = [
    "decale", "deplacer", "deplace", "modifie", "modifier", "change",
    "changer", "avance", "avancer", "repousse", "repousser",
  ].some((term) => (` ${message} `).includes(` ${term} `));
  const textualEvidence = [target.title, target.category, changes.title,
    changes.notes, changes.category].filter((value) => value);
  if (!hasExplicitMutation || textualEvidence.some((value) =>
    !(` ${message} `.includes(` ${comparisonText(value)} `)))) return null;
  return {type: "event_mutation", operation: "update", target, changes};
}

/**
 * Retire les mutations invalides sans altérer les autres actions.
 * @param {*} actions actions reçues
 * @param {string} userMessage message utilisateur original
 * @param {Object} logger logger injecté
 * @return {Array} actions assainies
 */
function sanitizeEventMutations(actions, userMessage, logger = console) {
  if (!Array.isArray(actions)) return [];
  return actions.flatMap((action) => {
    if (!action || action.type !== "event_mutation") return [action];
    const valid = validateEventMutation(action, userMessage);
    if (valid) return [valid];
    writeDiagnostic({logger, level: "info", event: "EVENT_MUTATION_REMOVED",
      component: "event_guard", step: "mutation_validation",
      code: "invalid-event-mutation-removed"});
    return [];
  });
}

module.exports = {sanitizeEventMutations, validateEventMutation};
const {writeDiagnostic} = require("./diagnostics");
