const CREATION_ACTION_TYPES = Object.freeze([
  "shopping",
  "task",
  "event",
]);

const ACTION_TYPES = Object.freeze([
  ...CREATION_ACTION_TYPES,
  "event_mutation",
]);

const eventParticipantObjectSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    label: {type: "string", minLength: 1, maxLength: 120},
    entityType: {type: "string", enum: ["person"]},
    evidence: {type: "string", enum: ["explicit_user_input"]},
  },
  required: ["label", "entityType", "evidence"],
});

const eventParticipantSchema = Object.freeze({
  anyOf: [eventParticipantObjectSchema, {type: "null"}],
});

const creationActionSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    type: {
      type: "string",
      enum: CREATION_ACTION_TYPES,
    },
    title: {
      type: "string",
    },
    date: {
      type: "string",
    },
    time: {
      type: "string",
    },
    durationMinutes: {
      type: "integer",
      minimum: 0,
    },
    needsDuration: {
      type: "boolean",
    },
    isRecurring: {
      type: "boolean",
    },
    recurringType: {
      type: "string",
    },
    recurringWeekday: {
      type: "integer",
      minimum: 0,
      maximum: 7,
    },
    recurringUntil: {
      type: "string",
    },
    category: {
      type: "string",
    },
    notes: {
      type: "string",
    },
    isImportant: {
      type: "boolean",
    },
    dueDate: {
      type: "string",
    },
    planning: {
      type: "string",
    },
    priority: {
      type: "string",
    },
    isUrgent: {
      type: "boolean",
    },
    section: {
      type: "string",
    },
    travelMinutes: {
      type: "integer",
      minimum: 0,
    },
    travelGoMinutes: {
      type: "integer",
      minimum: 0,
    },
    travelBackMinutes: {
      type: "integer",
      minimum: 0,
    },
    usesSeparateTravelTimes: {
      type: "boolean",
    },
    marginMinutes: {
      type: "integer",
      minimum: 0,
    },
    departureContext: {
      type: "string",
    },
    arrivalContext: {
      type: "string",
    },
    participant: eventParticipantSchema,
  },
  required: [
    "type",
    "title",
    "date",
    "time",
    "durationMinutes",
    "needsDuration",
    "isRecurring",
    "recurringType",
    "recurringWeekday",
    "recurringUntil",
    "category",
    "notes",
    "isImportant",
    "dueDate",
    "planning",
    "priority",
    "isUrgent",
    "section",
    "travelMinutes",
    "travelGoMinutes",
    "travelBackMinutes",
    "usesSeparateTravelTimes",
    "marginMinutes",
    "departureContext",
    "arrivalContext",
    "participant",
  ],
});

const eventMutationTargetSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    title: {type: ["string", "null"], maxLength: 120},
    date: {type: ["string", "null"]},
    time: {type: ["string", "null"]},
    category: {type: ["string", "null"], maxLength: 80},
  },
  required: ["title", "date", "time", "category"],
});

const eventMutationChangesSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    title: {type: ["string", "null"], maxLength: 120},
    date: {type: ["string", "null"]},
    time: {type: ["string", "null"]},
    durationMinutes: {
      type: ["integer", "null"], minimum: 1, maximum: 1440,
    },
    travelGoMinutes: {
      type: ["integer", "null"], minimum: 0, maximum: 480,
    },
    travelBackMinutes: {
      type: ["integer", "null"], minimum: 0, maximum: 480,
    },
    marginMinutes: {
      type: ["integer", "null"], minimum: 0, maximum: 240,
    },
    notes: {type: ["string", "null"], maxLength: 1000},
    category: {type: ["string", "null"], maxLength: 80},
  },
  required: [
    "title",
    "date",
    "time",
    "durationMinutes",
    "travelGoMinutes",
    "travelBackMinutes",
    "marginMinutes",
    "notes",
    "category",
  ],
});

const eventMutationActionSchema = Object.freeze({
  anyOf: [
    {
      type: "object",
      additionalProperties: false,
      properties: {
        type: {type: "string", enum: ["event_mutation"]},
        operation: {type: "string", enum: ["update"]},
        target: eventMutationTargetSchema,
        changes: eventMutationChangesSchema,
      },
      required: ["type", "operation", "target", "changes"],
    },
    {
      type: "object",
      additionalProperties: false,
      properties: {
        type: {type: "string", enum: ["event_mutation"]},
        operation: {type: "string", enum: ["replace_participant"]},
        target: eventMutationTargetSchema,
        participant: eventParticipantObjectSchema,
      },
      required: ["type", "operation", "target", "participant"],
    },
    {
      type: "object",
      additionalProperties: false,
      properties: {
        type: {type: "string", enum: ["event_mutation"]},
        operation: {type: "string", enum: ["remove_participant"]},
        target: eventMutationTargetSchema,
      },
      required: ["type", "operation", "target"],
    },
  ],
});

const actionSchema = Object.freeze({
  anyOf: [creationActionSchema, eventMutationActionSchema],
});

const memorySchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    text: {
      type: "string",
    },
    category: {
      type: "string",
    },
    importance: {
      type: "integer",
      minimum: 0,
      maximum: 3,
    },
  },
  required: [
    "text",
    "category",
    "importance",
  ],
});

const groundingReferenceSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    schemaVersion: {type: "integer", enum: [1]},
    sourceType: {
      type: "string",
      enum: [
        "currentUserMessage", "validatedHistoryMessage", "lifeContextHuman",
        "lifeContextIdentity", "lifeContextEvent", "lifeContextTask",
        "lifeContextRoutine", "lifeContextMemory", "lifeContextRelation",
        "confirmedClarification", "confirmedActionResult", "generalKnowledge",
      ],
    },
    section: {anyOf: [{type: "string"}, {type: "null"}]},
    factKey: {anyOf: [{type: "string"}, {type: "null"}]},
    freshness: {type: "string", enum: ["current", "stale", "unknown"]},
    confirmation: {
      type: "string",
      enum: [
        "confirmed", "proposed", "inferred", "needsConfirmation",
        "rejected", "historical",
      ],
    },
    projectionVersion: {type: "integer", minimum: 0},
  },
  required: [
    "schemaVersion", "sourceType", "section", "factKey", "freshness",
    "confirmation",
    "projectionVersion",
  ],
});

const personalClaimSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    claimId: {type: "string", minLength: 1, maxLength: 80},
    category: {
      type: "string",
      enum: [
        "humanFact", "eventFact", "taskFact", "routineFact", "memoryFact",
        "relationshipFact", "actionResultFact",
      ],
    },
    sourceReferenceIndexes: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: {type: "integer", minimum: 0},
    },
    certainty: {
      type: "string",
      enum: ["grounded", "groundedPartial", "uncertain", "stale"],
    },
  },
  required: [
    "claimId", "category", "sourceReferenceIndexes", "certainty",
  ],
});

const missingInformationSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    schemaVersion: {type: "integer", enum: [1]},
    code: {
      type: "string",
      enum: [
        "missingDate", "missingTime", "missingDuration",
        "missingTravelOutbound", "missingTravelReturn", "missingDeadline",
        "missingTaskTarget", "missingPerson", "missingHousehold",
        "missingResidence", "missingConfirmation", "missingChoice",
        "missingActionType", "missingContext", "missingCurrentValue",
      ],
    },
    domain: {type: "string", minLength: 1, maxLength: 40},
    field: {type: "string", minLength: 1, maxLength: 40},
    isRequired: {type: "boolean"},
    canClarify: {type: "boolean"},
  },
  required: [
    "schemaVersion", "code", "domain", "field", "isRequired", "canClarify",
  ],
});

const contradictionSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    schemaVersion: {type: "integer", enum: [1]},
    type: {
      type: "string",
      enum: [
        "twoConfirmedValues", "localVsCloud", "currentVsHistorical",
        "userMessageVsStoredContext", "clarificationVsStoredContext",
        "actionResultVsPendingState", "staleVsCurrent",
        "unsupportedCombination",
      ],
    },
    domain: {type: "string", minLength: 1, maxLength: 40},
    field: {type: "string", minLength: 1, maxLength: 40},
    requiresClarification: {type: "boolean"},
    blocksAction: {type: "boolean"},
    code: {type: "string", minLength: 1, maxLength: 80},
  },
  required: [
    "schemaVersion", "type", "domain", "field", "requiresClarification",
    "blocksAction", "code",
  ],
});

const clarificationSchema = Object.freeze({
  anyOf: [
    {type: "null"},
    {
      type: "object",
      additionalProperties: false,
      properties: {
        schemaVersion: {type: "integer", enum: [1]},
        clarificationId: {type: "string", minLength: 1, maxLength: 80},
        reasonCode: {type: "string", minLength: 1, maxLength: 80},
        questionText: {type: "string", minLength: 1, maxLength: 240},
        expectedAnswerType: {
          type: "string",
          enum: [
            "freeTextBounded", "yesNo", "date", "time", "duration", "choice",
            "personChoice", "locationChoice", "confirmation",
          ],
        },
        allowedChoices: {
          type: "array",
          maxItems: 6,
          items: {type: "string", minLength: 1, maxLength: 80},
        },
        missingFieldCodes: {
          type: "array",
          minItems: 1,
          maxItems: 6,
          items: missingInformationSchema.properties.code,
        },
        createdAt: {type: "string"},
        expiresAt: {anyOf: [{type: "string"}, {type: "null"}]},
        attemptNumber: {type: "integer", minimum: 1, maximum: 3},
        maximumAttempts: {type: "integer", enum: [3]},
        sessionGeneration: {type: "integer", minimum: 0},
      },
      required: [
        "schemaVersion", "clarificationId", "reasonCode", "questionText",
        "expectedAnswerType", "allowedChoices", "missingFieldCodes",
        "createdAt", "expiresAt", "attemptNumber", "maximumAttempts",
        "sessionGeneration",
      ],
    },
  ],
});

const epistemicSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    schemaVersion: {type: "integer", enum: [1]},
    responseKind: {
      type: "string",
      enum: [
        "answer", "answerWithCaveat", "clarificationRequired",
        "confirmationRequired", "actionProposal", "actionResult",
        "cannotDetermine", "contextUnavailable", "unsupportedRequest",
        "safeFailure",
      ],
    },
    epistemicState: {
      type: "string",
      enum: [
        "grounded", "groundedPartial", "uncertain", "conflicting", "stale",
        "contextUnavailable", "insufficientInformation", "unsupported",
        "invalid",
      ],
    },
    confidenceLevel: {
      type: "string",
      enum: ["high", "medium", "low", "unavailable"],
    },
    usedSourceTypes: {
      type: "array",
      maxItems: 12,
      items: groundingReferenceSchema.properties.sourceType,
    },
    groundingReferences: {
      type: "array",
      maxItems: 20,
      items: groundingReferenceSchema,
    },
    personalClaims: {type: "array", maxItems: 10, items: personalClaimSchema},
    missingInformation: {
      type: "array",
      maxItems: 10,
      items: missingInformationSchema,
    },
    contradictions: {
      type: "array",
      maxItems: 6,
      items: contradictionSchema,
    },
    clarification: clarificationSchema,
    uncertaintyCodes: {
      type: "array",
      maxItems: 10,
      items: {
        type: "string",
        enum: [
          "partialContext", "staleSource", "unavailableSource",
          "unconfirmedSource", "conflictingSources",
          "missingRequiredInformation", "clarificationLimitReached",
          "groundingUnavailable",
        ],
      },
    },
    contextStateObserved: {
      type: "string",
      enum: [
        "complete", "partial", "stale", "unavailable", "timeout",
        "unauthenticated", "accountMismatch", "invalidProjection", "cancelled",
        "unknownFailure",
      ],
    },
    warningCodes: {
      type: "array",
      maxItems: 10,
      items: {type: "string", maxLength: 80},
    },
    responseId: {type: "string", minLength: 1, maxLength: 80},
  },
  required: [
    "schemaVersion", "responseKind", "epistemicState", "confidenceLevel",
    "usedSourceTypes", "groundingReferences", "personalClaims",
    "missingInformation", "contradictions", "clarification",
    "uncertaintyCodes", "contextStateObserved", "warningCodes", "responseId",
  ],
});

const zeliaResponseJsonSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    visibleText: {
      type: "string",
      minLength: 1,
      maxLength: 4000,
    },
    actions: {
      type: "array",
      items: actionSchema,
    },
    memories: {
      type: "array",
      items: memorySchema,
    },
    epistemic: epistemicSchema,
  },
  required: [
    "visibleText",
    "actions",
    "memories",
    "epistemic",
  ],
});

module.exports = {
  ACTION_TYPES,
  CREATION_ACTION_TYPES,
  actionSchema,
  creationActionSchema,
  eventMutationActionSchema,
  eventMutationChangesSchema,
  eventMutationTargetSchema,
  eventParticipantSchema,
  eventParticipantObjectSchema,
  memorySchema,
  epistemicSchema,
  zeliaResponseJsonSchema,
};
