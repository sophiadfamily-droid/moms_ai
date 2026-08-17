const structuredScheduleExtractionJsonSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["proposals"],
  properties: {
    proposals: {
      type: "array",
      minItems: 0,
      maxItems: 100,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "target",
          "temporalKind",
          "title",
          "dateIso",
          "weekdays",
          "startTime",
          "endTime",
          "place",
          "confidence",
          "uncertainties",
        ],
        properties: {
          target: {
            type: "string",
            enum: [
              "event", "workSchedule", "schoolSchedule",
              "activitySchedule", "otherSchedule",
            ],
          },
          temporalKind: {
            type: "string",
            enum: ["dated", "recurringWeekly"],
          },
          title: {type: "string", minLength: 1, maxLength: 300},
          dateIso: {
            anyOf: [
              {type: "string", pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"},
              {type: "null"},
            ],
          },
          weekdays: {
            type: "array",
            maxItems: 7,
            items: {type: "integer", minimum: 1, maximum: 7},
          },
          startTime: {
            anyOf: [
              {type: "string", pattern: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"},
              {type: "null"},
            ],
          },
          endTime: {
            anyOf: [
              {type: "string", pattern: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"},
              {type: "null"},
            ],
          },
          place: {
            anyOf: [
              {type: "string", minLength: 1, maxLength: 500},
              {type: "null"},
            ],
          },
          confidence: {
            type: "string",
            enum: ["high", "medium", "low"],
          },
          uncertainties: {
            type: "array",
            items: {
              type: "string",
              enum: [
                "title", "date", "weekdays", "startTime", "endTime",
                "place", "recurrence",
              ],
            },
          },
        },
      },
    },
  },
});

module.exports = {structuredScheduleExtractionJsonSchema};
