"use strict";
/* eslint-disable require-jsdoc */

const MAX_SHOPPING_DOCUMENTS = 100;
const MAX_PROJECTED_ITEMS = 25;

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function isoDate(value) {
  if (value && typeof value.toDate === "function") {
    value = value.toDate();
  }
  const date = value instanceof Date ? value :
    typeof value === "string" ? new Date(value) : null;
  return date && !Number.isNaN(date.getTime()) ? date.toISOString() : null;
}

function normalizedIdentity(value) {
  return text(value).toLowerCase().normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
}

function canonicalStateFromDocument(document, position = 0) {
  const data = document && typeof document.data === "function" ?
    document.data() : null;
  if (!isRecord(data)) return null;
  const payload = isRecord(data.payload) ? data.payload : data;
  const title = text(payload.title);
  if (title.length === 0) return null;

  const updatedAt = isoDate(data.updatedAt) || isoDate(payload.updatedAt) ||
    isoDate(payload.createdAt) || isoDate(data.createdAt);

  return {
    identity: normalizedIdentity(title),
    active: data.isTombstone !== true && payload.isBought !== true,
    updatedAt,
    position,
    item: {
      title,
      quantity: text(payload.quantity),
      isUrgent: payload.isUrgent === true,
      createdAt: isoDate(payload.createdAt) || isoDate(data.createdAt),
    },
  };
}

function canonicalItemFromDocument(document) {
  const state = canonicalStateFromDocument(document);
  return state && state.active ? state.item : null;
}

async function loadCanonicalShoppingItems({
  firestore,
  uid,
  limit = MAX_SHOPPING_DOCUMENTS,
}) {
  if (!firestore || typeof uid !== "string" || uid.trim().length === 0 ||
      !Number.isInteger(limit) || limit < 1 || limit > 200) {
    throw new Error("CANONICAL_SHOPPING_LOAD_INVALID");
  }
  const snapshot = await firestore.collection("users").doc(uid)
      .collection("shopping_items")
      .orderBy("updatedAt", "desc")
      .limit(limit)
      .get();
  const latestByIdentity = new Map();
  snapshot.docs.forEach((document, position) => {
    const state = canonicalStateFromDocument(document, position);
    if (state === null || state.identity.length === 0) return;
    const previous = latestByIdentity.get(state.identity);
    const stateOrder = state.updatedAt || "";
    const previousOrder = previous ? previous.updatedAt || "" : "";
    if (previous === undefined || stateOrder > previousOrder ||
        (stateOrder === previousOrder && state.position > previous.position)) {
      latestByIdentity.set(state.identity, state);
    }
  });
  return [...latestByIdentity.values()].filter((state) => state.active)
      .map((state) => state.item)
      .sort((first, second) =>
        (second.createdAt || "").localeCompare(first.createdAt || ""));
}

function withCanonicalShoppingContext(source, shoppingItems) {
  const items = shoppingItems.slice(0, MAX_PROJECTED_ITEMS).map((item) => {
    const facts = {
      status: "active",
      title: item.title,
      urgency: item.isUrgent ? "1" : "0",
    };
    if (item.quantity) facts.quantity = item.quantity;
    if (item.createdAt) facts.createdAt = item.createdAt;
    return {
      type: "shoppingItem",
      confirmation: "confirmed",
      freshness: "current",
      facts,
    };
  });
  const section = {
    type: "shopping",
    availability: items.length === 0 ? "empty" : "available",
    freshness: "current",
    items,
    budgetLimit: MAX_PROJECTED_ITEMS,
    budgetUsed: items.length,
    omittedCount: Math.max(0, shoppingItems.length - items.length),
    truncated: shoppingItems.length > items.length,
  };
  const sections = source.conversationContext.sections
      .filter((candidate) => candidate.type !== "shopping");
  return {
    ...source,
    conversationContext: {
      ...source.conversationContext,
      sections: [...sections, section],
    },
  };
}

module.exports = {
  canonicalItemFromDocument,
  loadCanonicalShoppingItems,
  withCanonicalShoppingContext,
};
