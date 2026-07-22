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
    title: {type: "string", maxLength: 120},
    date: {type: "string"},
    time: {type: "string"},
    category: {type: "string", maxLength: 80},
  },
  required: [],
});

const eventMutationChangesSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    title: {type: "string", maxLength: 120},
    date: {type: "string"},
    time: {type: "string"},
    durationMinutes: {type: "integer", minimum: 1, maximum: 1440},
    travelGoMinutes: {type: "integer", minimum: 0, maximum: 480},
    travelBackMinutes: {type: "integer", minimum: 0, maximum: 480},
    marginMinutes: {type: "integer", minimum: 0, maximum: 240},
    notes: {type: "string", maxLength: 1000},
    category: {type: "string", maxLength: 80},
  },
  required: [],
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

const zeliaResponseJsonSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    reply: {
      type: "string",
    },
    actions: {
      type: "array",
      items: actionSchema,
    },
    memories: {
      type: "array",
      items: memorySchema,
    },
  },
  required: [
    "reply",
    "actions",
    "memories",
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
  zeliaResponseJsonSchema,
};
