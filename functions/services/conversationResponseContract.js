"use strict";
/* eslint-disable require-jsdoc */

const RESPONSE_VALIDATOR_VERSION = 1;
const MAX_RESPONSE_BYTES = 64000;
const RESPONSE_KEYS = new Set([
  "visibleText", "actions", "memories", "epistemic",
]);
const EPISTEMIC_KEYS = new Set([
  "schemaVersion", "responseKind", "epistemicState", "confidenceLevel",
  "usedSourceTypes", "groundingReferences", "personalClaims",
  "missingInformation", "contradictions", "clarification",
  "uncertaintyCodes", "contextStateObserved", "warningCodes", "responseId",
]);
const SOURCE_TYPES = new Set([
  "currentUserMessage", "validatedHistoryMessage", "lifeContextHuman",
  "lifeContextIdentity", "lifeContextEvent", "lifeContextTask",
  "lifeContextRoutine", "lifeContextMemory", "lifeContextRelation",
  "confirmedClarification", "confirmedActionResult", "generalKnowledge",
]);
const PERSONAL_SOURCES = new Set([
  "lifeContextHuman", "lifeContextIdentity", "lifeContextEvent",
  "lifeContextTask", "lifeContextRoutine", "lifeContextMemory",
  "lifeContextRelation",
]);
const NON_ACTION_KINDS = new Set([
  "clarificationRequired", "cannotDetermine", "contextUnavailable",
  "unsupportedRequest", "safeFailure",
]);
const RESPONSE_KINDS = new Set([
  "answer", "answerWithCaveat", "clarificationRequired",
  "confirmationRequired", "actionProposal", "actionResult",
  "cannotDetermine", "contextUnavailable", "unsupportedRequest", "safeFailure",
]);
const EPISTEMIC_STATES = new Set([
  "grounded", "groundedPartial", "uncertain", "conflicting", "stale",
  "contextUnavailable", "insufficientInformation", "unsupported", "invalid",
]);
const CONFIDENCE_LEVELS = new Set(["high", "medium", "low", "unavailable"]);
const REFERENCE_KEYS = new Set([
  "schemaVersion", "sourceType", "section", "factKey", "freshness",
  "confirmation",
  "projectionVersion",
]);
const CLAIM_KEYS = new Set([
  "claimId", "category", "sourceReferenceIndexes", "certainty",
]);
const CLAIM_CATEGORIES = new Set([
  "humanFact", "eventFact", "taskFact", "routineFact", "memoryFact",
  "relationshipFact", "actionResultFact",
]);
const MISSING_KEYS = new Set([
  "schemaVersion", "code", "domain", "field", "isRequired", "canClarify",
]);
const MISSING_CODES = new Set([
  "missingDate", "missingTime", "missingDuration",
  "missingTravelOutbound", "missingTravelReturn", "missingDeadline",
  "missingTaskTarget", "missingPerson", "missingHousehold",
  "missingResidence", "missingConfirmation", "missingChoice",
  "missingActionType", "missingContext", "missingCurrentValue",
]);
const CONTRADICTION_KEYS = new Set([
  "schemaVersion", "type", "domain", "field", "requiresClarification",
  "blocksAction", "code",
]);
const CONTRADICTION_TYPES = new Set([
  "twoConfirmedValues", "localVsCloud", "currentVsHistorical",
  "userMessageVsStoredContext", "clarificationVsStoredContext",
  "actionResultVsPendingState", "staleVsCurrent", "unsupportedCombination",
]);
const CLARIFICATION_KEYS = new Set([
  "schemaVersion", "clarificationId", "reasonCode", "questionText",
  "expectedAnswerType", "allowedChoices", "missingFieldCodes", "createdAt",
  "expiresAt", "attemptNumber", "maximumAttempts", "sessionGeneration",
]);
const ANSWER_TYPES = new Set([
  "freeTextBounded", "yesNo", "date", "time", "duration", "choice",
  "personChoice", "locationChoice", "confirmation",
]);
const UNCERTAINTY_CODES = new Set([
  "partialContext", "staleSource", "unavailableSource", "unconfirmedSource",
  "conflictingSources", "missingRequiredInformation",
  "clarificationLimitReached", "groundingUnavailable",
]);
const FORBIDDEN_MODEL_CONFIRMATION_KEYS = new Set([
  "confirmationId", "responseId", "actionFingerprint", "mutationId",
  "confirmationToken", "confirmationState", "accepted", "consumedAt",
]);

class ConversationResponseValidationError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function fail(code) {
  throw new ConversationResponseValidationError(code);
}

function record(value) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail("response_record_invalid");
  }
  return value;
}

function exactKeys(value, keys) {
  return Object.keys(record(value)).every((key) => keys.has(key)) &&
    Object.keys(value).length === keys.size;
}

function serializedBytes(value) {
  return Buffer.byteLength(JSON.stringify(value), "utf8");
}

function contextHasReference(reference, context) {
  if (!PERSONAL_SOURCES.has(reference.sourceType)) {
    return reference.section === null && reference.factKey === null;
  }
  if (reference.projectionVersion !== context.projectionVersion ||
      typeof reference.section !== "string" ||
      typeof reference.factKey !== "string") {
    return false;
  }
  return context.sections.some((section) =>
    section.type === reference.section &&
    section.availability !== "unavailable" &&
    section.items.some((item) =>
      Object.prototype.hasOwnProperty.call(item.facts, reference.factKey)));
}

function completeAction(action) {
  if (typeof action !== "object" || action === null || Array.isArray(action)) {
    return false;
  }
  if (action.type === "event_mutation") {
    return typeof action.operation === "string" &&
      typeof action.target === "object" && action.target !== null;
  }
  if (!["shopping", "task", "event"].includes(action.type) ||
      typeof action.title !== "string" || action.title.trim().length === 0) {
    return false;
  }
  if (action.type !== "event") return true;
  return typeof action.date === "string" && action.date.length > 0 &&
    typeof action.time === "string" && action.time.length > 0 &&
    Number.isInteger(action.durationMinutes) && action.durationMinutes > 0 &&
    (action.usesSeparateTravelTimes !== true ||
      Number.isInteger(action.travelGoMinutes) &&
      Number.isInteger(action.travelBackMinutes));
}

function rejectsFabricatedConfirmation(action) {
  return Object.keys(action).some((key) =>
    FORBIDDEN_MODEL_CONFIRMATION_KEYS.has(key));
}

function validateGrounding(epistemic, context) {
  if (!Array.isArray(epistemic.groundingReferences) ||
      epistemic.groundingReferences.length > 20 ||
      !Array.isArray(epistemic.personalClaims) ||
      epistemic.personalClaims.length > 10) {
    fail("response_grounding_bounds");
  }
  for (const reference of epistemic.groundingReferences) {
    if (!exactKeys(reference, REFERENCE_KEYS) ||
        reference.schemaVersion !== 1 ||
        !SOURCE_TYPES.has(reference.sourceType) ||
        !["current", "stale", "historical", "unknown"]
            .includes(reference.freshness) ||
        !["confirmed", "needsConfirmation", "proposed", "inferred"]
            .includes(reference.confirmation) ||
        !Number.isInteger(reference.projectionVersion) ||
        !contextHasReference(reference, context)) {
      fail("response_grounding_reference_invalid");
    }
    if (reference.freshness === "stale" &&
        !["stale", "groundedPartial"].includes(epistemic.epistemicState)) {
      fail("response_stale_as_current");
    }
  }
  for (const claim of epistemic.personalClaims) {
    if (!exactKeys(claim, CLAIM_KEYS) ||
        typeof claim.claimId !== "string" || claim.claimId.length === 0 ||
        claim.claimId.length > 80 ||
        !CLAIM_CATEGORIES.has(claim.category) ||
        !["grounded", "groundedPartial", "uncertain", "stale"]
            .includes(claim.certainty) ||
        !Array.isArray(claim.sourceReferenceIndexes) ||
        claim.sourceReferenceIndexes.length === 0 ||
        claim.sourceReferenceIndexes.length > 3 ||
        claim.sourceReferenceIndexes.some((index) =>
          !Number.isInteger(index) ||
          index < 0 ||
          index >= epistemic.groundingReferences.length) ||
        claim.sourceReferenceIndexes.every((index) =>
          epistemic.groundingReferences[index].sourceType ===
            "generalKnowledge")) {
      fail("response_personal_claim_ungrounded");
    }
  }
}

function validateSupportingData(epistemic, request) {
  if (epistemic.missingInformation.length > 10 ||
      epistemic.contradictions.length > 6) {
    fail("response_epistemic_bounds");
  }
  for (const item of epistemic.missingInformation) {
    if (!exactKeys(item, MISSING_KEYS) ||
        item.schemaVersion !== 1 ||
        !MISSING_CODES.has(item.code) ||
        typeof item.domain !== "string" || item.domain.length === 0 ||
        item.domain.length > 40 ||
        typeof item.field !== "string" || item.field.length === 0 ||
        item.field.length > 40 ||
        typeof item.isRequired !== "boolean" ||
        typeof item.canClarify !== "boolean") {
      fail("response_missing_information_invalid");
    }
  }
  for (const item of epistemic.contradictions) {
    if (!exactKeys(item, CONTRADICTION_KEYS) ||
        item.schemaVersion !== 1 ||
        !CONTRADICTION_TYPES.has(item.type) ||
        typeof item.domain !== "string" || item.domain.length === 0 ||
        item.domain.length > 40 ||
        typeof item.field !== "string" || item.field.length === 0 ||
        item.field.length > 40 ||
        typeof item.requiresClarification !== "boolean" ||
        typeof item.blocksAction !== "boolean" ||
        typeof item.code !== "string" || item.code.length === 0 ||
        item.code.length > 80) {
      fail("response_contradiction_invalid");
    }
  }
  const clarification = epistemic.clarification;
  if (clarification !== null &&
      (!exactKeys(clarification, CLARIFICATION_KEYS) ||
       clarification.schemaVersion !== 1 ||
       typeof clarification.clarificationId !== "string" ||
       clarification.clarificationId.length === 0 ||
       typeof clarification.reasonCode !== "string" ||
       clarification.reasonCode.length === 0 ||
       typeof clarification.questionText !== "string" ||
       clarification.questionText.length === 0 ||
       clarification.questionText.length > 240 ||
       !ANSWER_TYPES.has(clarification.expectedAnswerType) ||
       !Array.isArray(clarification.allowedChoices) ||
       clarification.allowedChoices.length > 6 ||
       !Array.isArray(clarification.missingFieldCodes) ||
       clarification.missingFieldCodes.length === 0 ||
       clarification.missingFieldCodes.length > 6 ||
       clarification.missingFieldCodes.some((code) =>
         !MISSING_CODES.has(code)) ||
       !Number.isInteger(clarification.attemptNumber) ||
       clarification.attemptNumber < 1 ||
       clarification.attemptNumber > 3 ||
       clarification.maximumAttempts !== 3 ||
       !Number.isInteger(clarification.sessionGeneration))) {
    fail("response_clarification_invalid");
  }
  if (!Array.isArray(epistemic.usedSourceTypes) ||
      epistemic.usedSourceTypes.some((type) => !SOURCE_TYPES.has(type)) ||
      !Array.isArray(epistemic.uncertaintyCodes) ||
      epistemic.uncertaintyCodes.some((code) =>
        !UNCERTAINTY_CODES.has(code)) ||
      !Array.isArray(epistemic.warningCodes) ||
      request.sessionGeneration < 0) {
    fail("response_epistemic_codes_invalid");
  }
}

function validateSemantics(response, request) {
  const epistemic = response.epistemic;
  if (!exactKeys(epistemic, EPISTEMIC_KEYS) ||
      epistemic.schemaVersion !== 1 ||
      !RESPONSE_KINDS.has(epistemic.responseKind) ||
      !EPISTEMIC_STATES.has(epistemic.epistemicState) ||
      !CONFIDENCE_LEVELS.has(epistemic.confidenceLevel) ||
      epistemic.contextStateObserved !== request.conversationContext.state ||
      !Array.isArray(response.actions) || !Array.isArray(response.memories) ||
      !Array.isArray(epistemic.missingInformation) ||
      !Array.isArray(epistemic.contradictions)) {
    fail("response_epistemic_invalid");
  }
  if (epistemic.responseKind === "answerWithCaveat" &&
      !["groundedPartial", "uncertain", "stale"]
          .includes(epistemic.epistemicState) ||
      epistemic.responseKind === "contextUnavailable" &&
      epistemic.epistemicState !== "contextUnavailable") {
    fail("response_epistemic_state_mismatch");
  }
  validateSupportingData(epistemic, request);
  validateGrounding(epistemic, request.conversationContext);
  if (!request.allowedStructuredResponseKinds.includes(
      epistemic.responseKind,
  ) || request.autonomyMode === "paused" &&
      response.actions.length > 0) {
    fail("response_autonomy_policy_blocked");
  }
  const blockingMissing = epistemic.missingInformation.some((item) =>
    item && item.isRequired === true);
  const blockingContradiction = epistemic.contradictions.some((item) =>
    item && item.blocksAction === true);
  if (response.actions.some((action) =>
    !completeAction(action) || rejectsFabricatedConfirmation(action)) ||
      response.actions.length > 0 &&
        (blockingMissing || blockingContradiction ||
         !["actionProposal", "confirmationRequired"]
             .includes(epistemic.responseKind)) ||
      NON_ACTION_KINDS.has(epistemic.responseKind) &&
        response.actions.length > 0) {
    fail("response_action_incomplete");
  }
  if (epistemic.responseKind === "clarificationRequired") {
    if (epistemic.clarification === null ||
        epistemic.missingInformation.length === 0 &&
        !epistemic.contradictions.some((item) =>
          item && item.requiresClarification === true)) {
      fail("response_clarification_invalid");
    }
    epistemic.clarification.sessionGeneration = request.sessionGeneration;
  } else if (epistemic.clarification !== null) {
    fail("response_clarification_unexpected");
  }
  if (epistemic.responseKind === "actionResult" &&
      !epistemic.usedSourceTypes.includes("confirmedActionResult")) {
    fail("response_action_result_unconfirmed");
  }
}

function validateConversationResponse(response, request) {
  if (!exactKeys(response, RESPONSE_KEYS) ||
      typeof response.visibleText !== "string" ||
      response.visibleText.trim().length === 0 ||
      response.visibleText.length > 4000 ||
      serializedBytes(response) > MAX_RESPONSE_BYTES) {
    fail("conversation_response_invalid");
  }
  validateSemantics(response, request);
  return response;
}

module.exports = {
  ConversationResponseValidationError,
  MAX_RESPONSE_BYTES,
  RESPONSE_VALIDATOR_VERSION,
  validateConversationResponse,
};
