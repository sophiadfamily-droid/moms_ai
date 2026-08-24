"use strict";
/* eslint-disable require-jsdoc */

function normalize(value) {
  return value.toLowerCase().normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
}

function requestedShoppingView(message) {
  const text = normalize(message);
  const shoppingWords =
    /\b(course|courses|achat|achats|acheter|liste)\b/.test(text);
  const remainingWords =
    /\b(reste|restent|manque|manquent|besoin|dois|quoi|liste)\b/.test(text);
  const urgent =
    /\b(urgent|urgente|urgents|urgentes|prioritaire|prioritaires)\b/
        .test(text);
  if (!shoppingWords || (!remainingWords && !urgent)) return null;
  return urgent ? "urgent" : "remaining";
}

function shoppingSection(context) {
  return context.sections.find((section) =>
    section.type === "shopping") || null;
}

function itemLabel(item) {
  const title = item.facts.title;
  if (typeof title !== "string" || title.trim().length === 0) return null;
  const quantity = item.facts.quantity;
  return typeof quantity === "string" && quantity.trim().length > 0 ?
    `${title.trim()} (${quantity.trim()})` : title.trim();
}

function joinFrench(values) {
  if (values.length < 2) return values[0] || "";
  return `${values.slice(0, -1).join(", ")} et ${values.at(-1)}`;
}

function canonicalShoppingFactAnswer(request, {
  sourceType = "lifeContextShopping",
} = {}) {
  const view = requestedShoppingView(request.message);
  if (view === null) return null;

  const context = request.conversationContext;
  const section = shoppingSection(context);
  if (section === null || !["available", "availableStale", "empty"]
      .includes(section.availability)) {
    return null;
  }

  const candidates = section.items.filter((item) =>
    item.type === "shoppingItem" &&
    ["confirmed", "needsConfirmation"].includes(item.confirmation) &&
    item.facts.status === "active" &&
    (view !== "urgent" || ["1", "urgent"].includes(item.facts.urgency)),
  );
  const labels = candidates.map(itemLabel).filter(Boolean);
  const stale = section.freshness === "stale" ||
    candidates.some((item) => item.freshness === "stale");
  let visibleText;
  if (labels.length === 0) {
    visibleText = view === "urgent" ?
      "Tu n’as aucun achat urgent pour le moment." :
      "Ta liste de courses est vide pour le moment.";
  } else if (view === "urgent") {
    visibleText = `À acheter en priorité : ${joinFrench(labels)}.`;
  } else {
    visibleText = `Il te reste à acheter : ${joinFrench(labels)}.`;
  }
  if (stale) {
    const qualified = visibleText.charAt(0).toLowerCase() +
      visibleText.slice(1);
    visibleText = `D’après la dernière liste disponible, ${qualified}`;
  }

  const serverVerified = sourceType === "serverVerifiedShopping";
  const groundingReferences = labels.length === 0 ? [] : [{
    schemaVersion: 1,
    sourceType,
    section: serverVerified ? null : "shopping",
    factKey: serverVerified ? null : "title",
    freshness: stale ? "stale" : "current",
    confirmation: "confirmed",
    projectionVersion: context.projectionVersion,
  }];
  return {
    visibleText,
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: stale ? "answerWithCaveat" : "answer",
      epistemicState: stale ? "stale" : "grounded",
      confidenceLevel: stale ? "medium" : "high",
      usedSourceTypes: labels.length === 0 ? [] : [sourceType],
      groundingReferences,
      personalClaims: labels.length === 0 ? [] : [{
        claimId: `shopping-${view}`,
        category: "shoppingFact",
        sourceReferenceIndexes: [0],
        certainty: stale ? "stale" : "grounded",
      }],
      missingInformation: [],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: stale ? ["staleSource"] : [],
      contextStateObserved: context.state,
      warningCodes: [],
      responseId: `shopping-${view}-${context.projectionVersion}`,
    },
  };
}

function canonicalShoppingContextUnavailableAnswer(request) {
  if (requestedShoppingView(request.message) === null) return null;
  const context = request.conversationContext;
  return {
    visibleText: "Je n’arrive pas à lire ta liste actuelle. " +
      "Ouvre la liste de courses, puis réessaie.",
    actions: [],
    memories: [],
    epistemic: {
      schemaVersion: 1,
      responseKind: "contextUnavailable",
      epistemicState: "contextUnavailable",
      confidenceLevel: "unavailable",
      usedSourceTypes: [],
      groundingReferences: [],
      personalClaims: [],
      missingInformation: [{
        schemaVersion: 1,
        code: "missingContext",
        domain: "shopping",
        field: "activeItems",
        isRequired: true,
        canClarify: false,
      }],
      contradictions: [],
      clarification: null,
      uncertaintyCodes: ["unavailableSource"],
      contextStateObserved: context.state,
      warningCodes: ["shoppingContextUnavailable"],
      responseId: `shopping-unavailable-${context.projectionVersion}`,
    },
  };
}

module.exports = {
  canonicalShoppingContextUnavailableAnswer,
  canonicalShoppingFactAnswer,
  requestedShoppingView,
};
