"use strict";
/* eslint-disable require-jsdoc */

const REQUEST_SCHEMA_VERSION = 2;
const CONTEXT_SCHEMA_VERSION = 1;
const REDACTION_VERSION = 1;
const PURPOSE = "conversation.transport.v1";
const MAX_MESSAGE_CHARACTERS = 4000;
const MAX_MESSAGE_BYTES = 12000;
const MAX_HISTORY_MESSAGES = 8;
const MAX_HISTORY_MESSAGE_CHARACTERS = 1000;
const MAX_HISTORY_BYTES = 8000;
const MAX_CONTEXT_BYTES = 24000;
const MAX_REQUEST_BYTES = 48000;
const MAX_SECTIONS = 7;
const MAX_ITEMS = 40;
const MAX_FACTS = 12;
const MAX_FACT_TEXT = 80;

const REQUEST_KEYS = new Set([
  "schemaVersion", "message", "sessionGeneration", "conversationContext",
  "conversationHistory",
  "profile", "profileContext", "memories", "memoryReasoning", "events",
]);
const CONTEXT_KEYS = new Set([
  "schemaVersion", "projectionVersion", "purpose", "generatedAt", "state",
  "sections", "budgetRequested", "budgetUsed", "omittedCount",
  "truncatedSections", "warningCodes", "redactionVersion",
]);
const SECTION_KEYS = new Set([
  "type", "availability", "freshness", "items", "budgetLimit", "budgetUsed",
  "omittedCount", "truncated",
]);
const ITEM_KEYS = new Set(["type", "confirmation", "freshness", "facts"]);
const HISTORY_KEYS = new Set(["role", "text"]);
const SECTION_TYPES = new Set([
  "human", "identity", "event", "task", "routine", "memory", "relation",
]);
const STATES = new Set([
  "complete", "partial", "stale", "unavailable", "timeout",
  "unauthenticated", "accountMismatch", "invalidProjection", "cancelled",
  "unknownFailure",
]);
const AVAILABILITY = new Set([
  "available", "availableStale", "empty", "unavailable", "corrupted",
  "unsupported", "accountMismatch",
]);
const FRESHNESS = new Set(["current", "stale", "unknown"]);
const CONFIRMATIONS = new Set([
  "confirmed", "proposed", "inferred", "needsConfirmation",
  "rejected", "historical",
]);
const FACT_KEYS = new Set([
  "displayName", "status", "kind", "start", "end", "dueDate",
  "durationMinutes", "travelGoMinutes", "travelBackMinutes", "marginMinutes",
  "recurringType", "syncStatus", "revision", "days", "startTime", "endTime",
  "travelMinutes", "title", "category", "sourceNodeId", "targetNodeId",
  "actionRequired", "importance", "urgency", "flexibility",
]);
const FORBIDDEN_KEYS = new Set([
  "uid", "accountScopeId", "token", "secret", "password", "cookie",
  "allergies", "medicalNotes", "bloodType", "doctorName",
  "emergencyContactName", "emergencyContactPhone", "address", "phone",
  "prompt", "payload", "memoryContext", "snapshot", "graph", "tombstone",
  "offlineQueue", "conflict",
]);

class ConversationContextValidationError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function fail(code) {
  throw new ConversationContextValidationError(code);
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exactKeys(value, allowed) {
  return isRecord(value) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function bytes(value) {
  return Buffer.byteLength(JSON.stringify(value), "utf8");
}

function emptyRecord(value) {
  return isRecord(value) && Object.keys(value).length === 0;
}

function emptyArray(value) {
  return Array.isArray(value) && value.length === 0;
}

function validateFacts(facts) {
  if (!isRecord(facts) || Object.keys(facts).length === 0 ||
      Object.keys(facts).length > MAX_FACTS) {
    fail("context_facts_invalid");
  }
  for (const [key, value] of Object.entries(facts)) {
    if (!FACT_KEYS.has(key) || FORBIDDEN_KEYS.has(key) ||
        typeof value !== "string" || value.length === 0 ||
        value.length > MAX_FACT_TEXT) {
      fail("context_fact_invalid");
    }
  }
  return {...facts};
}

function validateItem(item) {
  if (!exactKeys(item, ITEM_KEYS) || typeof item.type !== "string" ||
      item.type.length === 0 || !CONFIRMATIONS.has(item.confirmation) ||
      !FRESHNESS.has(item.freshness)) {
    fail("context_item_invalid");
  }
  return {
    type: item.type,
    confirmation: item.confirmation,
    freshness: item.freshness,
    facts: validateFacts(item.facts),
  };
}

function validateSection(section) {
  if (!exactKeys(section, SECTION_KEYS) ||
      !SECTION_TYPES.has(section.type) ||
      !AVAILABILITY.has(section.availability) ||
      !FRESHNESS.has(section.freshness) ||
      !Array.isArray(section.items) ||
      !Number.isInteger(section.budgetLimit) || section.budgetLimit < 1 ||
      !Number.isInteger(section.budgetUsed) || section.budgetUsed < 0 ||
      section.budgetUsed > section.budgetLimit ||
      !Number.isInteger(section.omittedCount) || section.omittedCount < 0 ||
      typeof section.truncated !== "boolean") {
    fail("context_section_invalid");
  }
  return {
    type: section.type,
    availability: section.availability,
    freshness: section.freshness,
    items: section.items.map(validateItem),
    budgetLimit: section.budgetLimit,
    budgetUsed: section.budgetUsed,
    omittedCount: section.omittedCount,
    truncated: section.truncated,
  };
}

function validateContext(context) {
  if (!exactKeys(context, CONTEXT_KEYS) ||
      context.schemaVersion !== CONTEXT_SCHEMA_VERSION ||
      !Number.isInteger(context.projectionVersion) ||
      context.projectionVersion < 0 ||
      context.purpose !== PURPOSE || !STATES.has(context.state) ||
      typeof context.generatedAt !== "string" ||
      Number.isNaN(Date.parse(context.generatedAt)) ||
      !Array.isArray(context.sections) ||
      context.sections.length > MAX_SECTIONS ||
      !Number.isInteger(context.budgetRequested) ||
      context.budgetRequested < 1 ||
      !Number.isInteger(context.budgetUsed) || context.budgetUsed < 0 ||
      context.budgetUsed > context.budgetRequested ||
      !Number.isInteger(context.omittedCount) || context.omittedCount < 0 ||
      !Array.isArray(context.truncatedSections) ||
      !Array.isArray(context.warningCodes) ||
      context.redactionVersion !== REDACTION_VERSION) {
    fail("conversation_context_invalid");
  }
  const sections = context.sections.map(validateSection);
  if (sections.reduce((sum, section) => sum + section.items.length, 0) >
      MAX_ITEMS) {
    fail("context_items_exceeded");
  }
  const sanitized = {
    schemaVersion: CONTEXT_SCHEMA_VERSION,
    projectionVersion: context.projectionVersion,
    purpose: PURPOSE,
    generatedAt: context.generatedAt,
    state: context.state,
    sections,
    budgetRequested: context.budgetRequested,
    budgetUsed: context.budgetUsed,
    omittedCount: context.omittedCount,
    truncatedSections: context.truncatedSections.filter(
        (value) => SECTION_TYPES.has(value)),
    warningCodes: context.warningCodes.filter(
        (value) => typeof value === "string" && value.length <= 80),
    redactionVersion: REDACTION_VERSION,
  };
  if (bytes(sanitized) > MAX_CONTEXT_BYTES) fail("context_size_exceeded");
  return sanitized;
}

function validateHistory(history) {
  if (!Array.isArray(history) || history.length > MAX_HISTORY_MESSAGES) {
    fail("conversation_history_invalid");
  }
  const seen = new Set();
  const sanitized = [];
  for (const item of history) {
    if (!exactKeys(item, HISTORY_KEYS) ||
        !["user", "assistant"].includes(item.role) ||
        typeof item.text !== "string" || item.text.trim().length === 0 ||
        item.text.length > MAX_HISTORY_MESSAGE_CHARACTERS) {
      fail("conversation_history_message_invalid");
    }
    const key = `${item.role}\u0000${item.text}`;
    if (seen.has(key)) continue;
    seen.add(key);
    sanitized.push({role: item.role, text: item.text});
  }
  if (bytes(sanitized) > MAX_HISTORY_BYTES) fail("history_size_exceeded");
  return sanitized;
}

function validateConversationRequest(payload) {
  if (!exactKeys(payload, REQUEST_KEYS) ||
      payload.schemaVersion !== REQUEST_SCHEMA_VERSION ||
      !Number.isInteger(payload.sessionGeneration) ||
      payload.sessionGeneration < 0 ||
      typeof payload.message !== "string" ||
      payload.message.trim().length === 0 ||
      payload.message.length > MAX_MESSAGE_CHARACTERS ||
      Buffer.byteLength(payload.message, "utf8") > MAX_MESSAGE_BYTES ||
      !emptyRecord(payload.profile) ||
      !emptyRecord(payload.profileContext) ||
      !emptyArray(payload.memories) ||
      !emptyArray(payload.memoryReasoning) ||
      !emptyArray(payload.events)) {
    fail("conversation_request_invalid");
  }
  const sanitized = {
    schemaVersion: REQUEST_SCHEMA_VERSION,
    message: payload.message,
    sessionGeneration: payload.sessionGeneration,
    conversationContext: validateContext(payload.conversationContext),
    conversationHistory: validateHistory(payload.conversationHistory),
    profile: {},
    profileContext: {},
    memories: [],
    memoryReasoning: [],
    events: [],
  };
  if (bytes(sanitized) > MAX_REQUEST_BYTES) fail("request_size_exceeded");
  return sanitized;
}

module.exports = {
  ConversationContextValidationError,
  validateConversationRequest,
  REQUEST_SCHEMA_VERSION,
  MAX_REQUEST_BYTES,
};
