const assert = require("node:assert/strict");
const test = require("node:test");

const {
  canonicalShoppingFactAnswer,
  requestedShoppingView,
} = require("../../services/canonicalShoppingFactAnswer");

/**
 * Builds a bounded shopping context request.
 * @param {string} message User question.
 * @param {object} options Shopping section overrides.
 * @return {object} Canonical request subset.
 */
function request(message, {items = [], availability = "available"} = {}) {
  return {
    message,
    conversationContext: {
      projectionVersion: 3,
      state: "complete",
      sections: [{
        type: "shopping",
        availability,
        freshness: "current",
        items,
      }],
    },
  };
}

/**
 * Builds a projected active shopping item.
 * @param {string} title Product title.
 * @param {object} options Shopping fact overrides.
 * @return {object} Projected shopping item.
 */
function item(title, {urgent = false, quantity = ""} = {}) {
  return {
    type: "shoppingItem",
    confirmation: "confirmed",
    freshness: "current",
    facts: {
      status: "active",
      title,
      urgency: urgent ? "1" : "0",
      createdAt: "2026-08-24T08:00:00.000Z",
      ...(quantity ? {quantity} : {}),
    },
  };
}

test("detects varied questions about remaining shopping", () => {
  for (const message of [
    "Qu’est-ce qu’il me reste à acheter ?",
    "C'est quoi ma liste de courses ?",
    "De quoi ai-je besoin pour les courses ?",
    "Quels achats me manquent ?",
  ]) {
    assert.equal(requestedShoppingView(message), "remaining");
  }
  assert.equal(requestedShoppingView("Ajoute des fraises aux courses"), null);
});

test("answers from the current shopping section without the model", () => {
  const result = canonicalShoppingFactAnswer(request(
      "Qu’est-ce qu’il me reste à acheter ?",
      {items: [item("Fraises", {quantity: "2 barquettes"}), item("Lait")]},
  ));
  assert.equal(
      result.visibleText,
      "Il te reste à acheter : Fraises (2 barquettes) et Lait.");
  assert.equal(result.epistemic.personalClaims[0].category, "shoppingFact");
});

test("marks an authenticated server read as independently verifiable", () => {
  const result = canonicalShoppingFactAnswer(request(
      "Qu’est-ce qu’il me reste à acheter ?",
      {items: [item("Fraises")]},
  ), {sourceType: "serverVerifiedShopping"});
  assert.deepEqual(result.epistemic.groundingReferences[0], {
    schemaVersion: 1,
    sourceType: "serverVerifiedShopping",
    section: null,
    factKey: null,
    freshness: "current",
    confirmation: "confirmed",
    projectionVersion: 3,
  });
});

test("filters urgent shopping and handles an empty current list", () => {
  const urgent = canonicalShoppingFactAnswer(request(
      "Quels sont mes achats urgents ?",
      {items: [item("Kiwis", {urgent: true}), item("Lait")]},
  ));
  assert.equal(urgent.visibleText, "À acheter en priorité : Kiwis.");

  const empty = canonicalShoppingFactAnswer(request(
      "Que dois-je acheter ?", {items: [], availability: "empty"},
  ));
  assert.equal(
      empty.visibleText,
      "Ta liste de courses est vide pour le moment.",
  );
});

test("does not pretend to know an unavailable shopping section", () => {
  assert.equal(canonicalShoppingFactAnswer(request(
      "Que dois-je acheter ?", {availability: "unavailable"},
  )), null);
});
