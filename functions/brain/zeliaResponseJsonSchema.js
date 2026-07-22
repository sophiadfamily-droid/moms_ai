const ACTION_TYPES = Object.freeze([
  "shopping",
  "task",
  "event",
]);

const eventParticipantSchema = Object.freeze({
  anyOf: [
    {
      type: "object",
      additionalProperties: false,
      properties: {
        label: {type: "string", minLength: 1, maxLength: 120},
        entityType: {type: "string", enum: ["person"]},
        evidence: {type: "string", enum: ["explicit_user_input"]},
      },
      required: ["label", "entityType", "evidence"],
    },
    {type: "null"},
  ],
});

const actionSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: {
    type: {
      type: "string",
      enum: ACTION_TYPES,
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
  actionSchema,
  eventParticipantSchema,
  memorySchema,
  zeliaResponseJsonSchema,
};
