"use strict";
/* eslint-disable require-jsdoc */

const {
  normalizeNaturalLanguage,
} = require("../brain/engines/naturalLanguageNormalizer");

const EVENT_TITLES = Object.freeze([
  ["dentiste", "Rendez-vous dentiste"],
  ["medecin", "Consultation médecin"],
  ["docteur", "Consultation médecin"],
  ["pediatre", "Rendez-vous pédiatre"],
  ["kine", "Rendez-vous kiné"],
  ["osteopathe", "Rendez-vous ostéopathe"],
  ["reunion", "Réunion"],
  ["consultation", "Consultation"],
  ["rendez vous", "Rendez-vous"],
  ["rdv", "Rendez-vous"],
]);

function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

function extractDate(text, referenceDate) {
  const date = new Date(referenceDate);
  if (/\bdemain\b/.test(text)) {
    date.setUTCDate(date.getUTCDate() + 1);
    return isoDate(date);
  }
  if (/\baujourd hui\b/.test(text)) return isoDate(date);
  return null;
}

function extractTime(text) {
  const match = /\b([01]?\d|2[0-3])\s*h(?:\s*([0-5]\d))?\b/.exec(text);
  if (!match) return null;
  return `${match[1].padStart(2, "0")}:${(match[2] || "00").padStart(2, "0")}`;
}

function hasExplicitDuration(text) {
  return /\b(?:pendant|duree|durer|prevoir)\s+\d+\s*(?:h|min|minutes?)\b/
      .test(text) ||
    /\b\d+\s*minutes?\b/.test(text);
}

function extractTitle(text) {
  const entry = EVENT_TITLES.find(([keyword]) =>
    (` ${text} `).includes(` ${keyword} `));
  return entry ? entry[1] : null;
}

function questionFor(expectedField) {
  if (expectedField === "date") return "Quel jour est prévu ce rendez-vous ?";
  if (expectedField === "time") return "À quelle heure est-il prévu ?";
  return "Je prépare ce rendez-vous. Il me manque juste la durée.";
}

/**
 * Construit une clarification Event non exécutable depuis les seules données
 * temporelles déterministes du message courant.
 *
 * @param {Object} input
 * @return {Object|null}
 */
function buildEventClarification(input) {
  const normalized = normalizeNaturalLanguage(input.message).normalizedText;
  const title = extractTitle(normalized);
  if (!title || hasExplicitDuration(normalized)) return null;
  const date = extractDate(normalized, input.now);
  const startTime = extractTime(normalized);
  const expectedField = date === null ? "date" :
    startTime === null ? "time" : "duration";
  const createdAt = new Date(input.now);
  const expiresAt = new Date(createdAt.getTime() + 15 * 60 * 1000);
  const questionText = questionFor(expectedField);
  const missingCode = expectedField === "date" ? "missingDate" :
    expectedField === "time" ? "missingTime" : "missingDuration";

  return {
    visibleText: questionText,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: "clarificationRequired",
      epistemicState: "insufficientInformation",
      confidenceLevel: "high",
      usedSourceTypes: ["currentUserMessage"],
      groundingReferences: [{
        schemaVersion: 1,
        sourceType: "currentUserMessage",
        section: null,
        factKey: null,
        freshness: "current",
        confirmation: "confirmed",
        projectionVersion: 0,
      }],
      personalClaims: [],
      missingInformation: [{
        schemaVersion: 1,
        code: missingCode,
        domain: "event",
        field: expectedField,
        isRequired: true,
        canClarify: true,
      }],
      contradictions: [],
      clarification: {
        schemaVersion: 1,
        clarificationId: `event-${input.correlationId}`,
        reasonCode: `event_${expectedField}_required`,
        questionText,
        expectedAnswerType: expectedField,
        allowedChoices: [],
        missingFieldCodes: [missingCode],
        createdAt: createdAt.toISOString(),
        expiresAt: expiresAt.toISOString(),
        attemptNumber: 1,
        maximumAttempts: 3,
        sessionGeneration: input.sessionGeneration,
        draft: {
          schemaVersion: 1,
          draftType: "eventCreation",
          logicalRequestId: input.correlationId,
          draftId: `event-draft-${input.correlationId}`,
          title,
          date,
          startTime,
          durationMinutes: null,
          travelGoMinutes: null,
          travelBackMinutes: null,
          marginMinutes: null,
          expectedField,
          createdAt: createdAt.toISOString(),
          expiresAt: expiresAt.toISOString(),
          sessionGeneration: input.sessionGeneration,
        },
      },
      uncertaintyCodes: ["missingRequiredInformation"],
      contextStateObserved: input.contextState,
      warningCodes: [],
      responseId: `event-clarification-${input.correlationId}`,
    },
  };
}

module.exports = {buildEventClarification};
