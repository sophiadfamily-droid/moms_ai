"use strict";
/* eslint-disable require-jsdoc */

const MONTHS = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];

function normalizedText(value) {
  return value
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[’']/g, " ")
      .toLowerCase();
}

function requestedRelationshipDate(message) {
  const text = normalizedText(message);
  const asksQuestion = /\b(quel(?:le)?|quand|connais|sais|rappelle|dis moi)\b/
      .test(text) || text.includes("c est quoi");
  if (!asksQuestion) return null;
  if (/\b(mariage|mariee?|maries?)\b/.test(text)) {
    return {
      factKey: "marriageDate",
      visiblePrefix: "Ta date de mariage est le",
    };
  }
  if (/\b(fiancailles|fiancee?|fiances?)\b/.test(text)) {
    return {
      factKey: "engagementDate",
      visiblePrefix: "Ta date de fiançailles est le",
    };
  }
  return null;
}

function frenchDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year ||
      parsed.getUTCMonth() !== month - 1 ||
      parsed.getUTCDate() !== day) {
    return null;
  }
  return `${day} ${MONTHS[month - 1]} ${year}`;
}

function canonicalProfileFactAnswer(request) {
  const requested = requestedRelationshipDate(request.message);
  if (requested === null) return null;

  const context = request.conversationContext;
  const candidates = [];
  for (const section of context.sections) {
    if (section.type !== "human" ||
        !["available", "availableStale"].includes(section.availability)) {
      continue;
    }
    for (const item of section.items) {
      const value = item.facts[requested.factKey];
      if (typeof value !== "string" || frenchDate(value) === null ||
          !["confirmed", "needsConfirmation"].includes(item.confirmation)) {
        continue;
      }
      candidates.push({section, item, value});
    }
  }

  const values = [...new Set(candidates.map((candidate) => candidate.value))];
  if (values.length !== 1) return null;
  const candidate = candidates.find((item) => item.value === values[0]);
  const stale = candidate.section.freshness === "stale" ||
      candidate.item.freshness === "stale";
  const confirmation = candidate.item.confirmation;
  const certain = confirmation === "confirmed";
  const formatted = frenchDate(candidate.value);
  const qualifiedPrefix = requested.visiblePrefix.toLowerCase();
  const visibleText = stale || !certain ?
    `D’après les dernières informations disponibles, ` +
      `${qualifiedPrefix} ${formatted}.` :
    `${requested.visiblePrefix} ${formatted}.`;

  const sourceType = "lifeContextHuman";
  return {
    visibleText,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: stale || !certain ? "answerWithCaveat" : "answer",
      epistemicState: stale ? "stale" :
        certain ? "grounded" : "groundedPartial",
      confidenceLevel: stale || !certain ? "medium" : "high",
      usedSourceTypes: [sourceType],
      groundingReferences: [{
        schemaVersion: 1,
        sourceType,
        section: "human",
        factKey: requested.factKey,
        freshness: stale ? "stale" : "current",
        confirmation,
        projectionVersion: context.projectionVersion,
      }],
      personalClaims: [{
        claimId: `profile-${requested.factKey}`,
        category: "relationshipFact",
        sourceReferenceIndexes: [0],
        certainty: stale || !certain ? "groundedPartial" : "grounded",
      }],
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: stale ? ["staleSource"] :
        !certain ? ["unconfirmedSource"] : [],
      contextStateObserved: context.state,
      warningCodes: [],
      responseId: `profile-${requested.factKey}-${context.projectionVersion}`,
    },
  };
}

module.exports = {
  canonicalProfileFactAnswer,
  requestedRelationshipDate,
};
