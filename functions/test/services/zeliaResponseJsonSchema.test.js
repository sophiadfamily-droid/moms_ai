const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ACTION_TYPES,
  CREATION_ACTION_TYPES,
  actionSchema,
  creationActionSchema,
  eventMutationActionSchema,
  eventMutationChangesSchema,
  eventMutationTargetSchema,
  memorySchema,
  eventParticipantSchema,
  zeliaResponseJsonSchema,
} = require("../../brain/zeliaResponseJsonSchema");
const {
  RESPONSE_SCHEMA_NAME,
  buildZeliaResponseRequest,
} = require("../../services/openaiService");

const UNSUPPORTED_KEYWORDS = new Set([
  "allOf",
  "not",
  "dependentRequired",
  "dependentSchemas",
  "if",
  "then",
  "else",
]);

/**
 * Audits the strict Structured Outputs subset with exact JSON paths.
 * @param {object} schema Schema to inspect.
 * @return {{errors: string[], depth: number, properties: number,
 * enumValues: number}}
 */
function auditStructuredOutputsSchema(schema) {
  const errors = [];
  let depth = 0;
  let properties = 0;
  let enumValues = 0;

  /**
   * Detects values that JSON.stringify would reject or silently discard.
   * @param {*} value Current value.
   * @param {string} path JSON path.
   * @param {Set<object>} ancestors Objects above this value.
   */
  function inspectJsonValue(value, path, ancestors) {
    if (value === undefined) {
      errors.push(`${path}: undefined value`);
      return;
    }
    if (value === null || typeof value !== "object") return;
    if (ancestors.has(value)) {
      errors.push(`${path}: circular reference`);
      return;
    }
    const nextAncestors = new Set(ancestors);
    nextAncestors.add(value);
    if (Array.isArray(value)) {
      value.forEach((item, index) =>
        inspectJsonValue(item, `${path}[${index}]`, nextAncestors));
      return;
    }
    for (const [key, child] of Object.entries(value)) {
      inspectJsonValue(child, `${path}.${key}`, nextAncestors);
    }
  }

  /**
   * Visits every serialized occurrence while detecting ancestor cycles.
   * @param {*} value Current value.
   * @param {string} path JSON path.
   * @param {number} currentDepth Structural depth.
   * @param {Set<object>} ancestors Objects above this value.
   */
  function visit(value, path, currentDepth, ancestors) {
    depth = Math.max(depth, currentDepth);
    if (value === undefined) return;
    if (value === null || typeof value !== "object") return;
    if (ancestors.has(value)) return;
    const nextAncestors = new Set(ancestors);
    nextAncestors.add(value);

    for (const keyword of Object.keys(value)) {
      if (UNSUPPORTED_KEYWORDS.has(keyword)) {
        errors.push(`${path}.${keyword}: unsupported keyword`);
      }
    }
    if (value.type === "object") {
      if (!value.properties || typeof value.properties !== "object" ||
          Array.isArray(value.properties)) {
        errors.push(`${path}.properties: expected an object`);
      } else {
        const propertyKeys = Object.keys(value.properties);
        properties += propertyKeys.length;
        if (value.additionalProperties !== false) {
          errors.push(`${path}.additionalProperties: expected false`);
        }
        if (!Array.isArray(value.required)) {
          errors.push(`${path}.required: expected an array`);
        } else {
          const missing = propertyKeys.filter(
              (key) => !value.required.includes(key),
          );
          const extra = value.required.filter(
              (key) => !propertyKeys.includes(key),
          );
          if (missing.length > 0) {
            errors.push(
                `${path}.required: missing ${missing.join(", ")}`,
            );
          }
          if (extra.length > 0) {
            errors.push(
                `${path}.required: unknown ${extra.join(", ")}`,
            );
          }
        }
      }
    }
    if (Array.isArray(value.enum)) enumValues += value.enum.length;

    for (const [key, child] of Object.entries(value)) {
      if (key === "properties") {
        for (const [property, propertySchema] of Object.entries(child)) {
          visit(
              propertySchema,
              `${path}.properties.${property}`,
              currentDepth + 1,
              nextAncestors,
          );
        }
      } else if (key === "items") {
        visit(child, `${path}.items`, currentDepth + 1, nextAncestors);
      } else if (key === "anyOf") {
        child.forEach((branch, index) => visit(
            branch,
            `${path}.anyOf[${index}]`,
            currentDepth + 1,
            nextAncestors,
        ));
      } else if (key === "$defs") {
        for (const [definition, definitionSchema] of Object.entries(child)) {
          visit(
              definitionSchema,
              `${path}.$defs.${definition}`,
              currentDepth + 1,
              nextAncestors,
          );
        }
      }
    }
  }

  if (schema.type !== "object") {
    errors.push("$: root must have type object");
  }
  if (Object.prototype.hasOwnProperty.call(schema, "anyOf")) {
    errors.push("$.anyOf: root anyOf is unsupported");
  }
  inspectJsonValue(schema, "$", new Set());
  visit(schema, "$", 1, new Set());
  if (depth > 10) errors.push(`$: depth ${depth} exceeds 10`);
  if (properties >= 5000) {
    errors.push(`$: property count ${properties} must be below 5000`);
  }
  if (enumValues >= 1000) {
    errors.push(`$: enum value count ${enumValues} must be below 1000`);
  }

  let serialized;
  try {
    serialized = JSON.stringify(schema);
    JSON.parse(serialized);
  } catch (error) {
    errors.push(`$: JSON serialization failed: ${error.message}`);
  }
  return {errors, depth, properties, enumValues};
}

test("defines the supported action types", () => {
  assert.deepEqual(
      ACTION_TYPES,
      ["shopping", "task", "event", "event_mutation"],
  );
  assert.deepEqual(CREATION_ACTION_TYPES, ["shopping", "task", "event"]);
});

test("requires every top-level response field", () => {
  assert.deepEqual(
      zeliaResponseJsonSchema.required,
      ["visibleText", "actions", "memories", "epistemic"],
  );

  assert.equal(
      zeliaResponseJsonSchema.additionalProperties,
      false,
  );
});

test("conforms recursively to the strict Structured Outputs subset", () => {
  const audit = auditStructuredOutputsSchema(zeliaResponseJsonSchema);
  assert.deepEqual(audit.errors, []);
  assert.ok(audit.depth <= 10);
  assert.ok(audit.properties < 5000);
  assert.ok(audit.enumValues < 1000);
});

test("reports the exact path for strict-schema violations", () => {
  const invalid = {
    type: "object",
    properties: {
      branch: {
        anyOf: [{
          type: "object",
          properties: {value: {type: "string", example: undefined}},
          required: [],
          additionalProperties: false,
        }],
      },
    },
    required: [],
    additionalProperties: true,
  };
  assert.deepEqual(auditStructuredOutputsSchema(invalid).errors, [
    "$.properties.branch.anyOf[0].properties.value.example: undefined value",
    "$.additionalProperties: expected false",
    "$.required: missing branch",
    "$.properties.branch.anyOf[0].required: missing value",
  ]);
});

test("builds the exact strict json_schema response format", () => {
  const request = buildZeliaResponseRequest({
    systemContent: "SYSTEM",
    userMessage: "USER",
  });
  assert.deepEqual(request.text, {
    format: {
      type: "json_schema",
      name: "zelia_response",
      strict: true,
      schema: zeliaResponseJsonSchema,
    },
  });
  assert.equal(RESPONSE_SCHEMA_NAME, "zelia_response");
});

test("defines a closed epistemic response contract", () => {
  const epistemic = zeliaResponseJsonSchema.properties.epistemic;

  assert.equal(epistemic.type, "object");
  assert.equal(epistemic.additionalProperties, false);
  assert.deepEqual(epistemic.properties.schemaVersion.enum, [1]);
  assert.equal(epistemic.required.includes("responseKind"), true);
  assert.equal(epistemic.required.includes("groundingReferences"), true);
  assert.equal(epistemic.required.includes("missingInformation"), true);
  assert.equal(epistemic.required.includes("contradictions"), true);
});

test("defines actions as a strict array of action objects", () => {
  const actions = zeliaResponseJsonSchema.properties.actions;

  assert.equal(actions.type, "array");
  assert.equal(actions.items, actionSchema);
  assert.deepEqual(actionSchema.anyOf, [
    creationActionSchema,
    eventMutationActionSchema,
  ]);
});

test("requires the separate travel fields", () => {
  const requiredFields = new Set(creationActionSchema.required);

  assert.equal(requiredFields.has("travelMinutes"), true);
  assert.equal(requiredFields.has("travelGoMinutes"), true);
  assert.equal(requiredFields.has("travelBackMinutes"), true);
  assert.equal(requiredFields.has("usesSeparateTravelTimes"), true);
  assert.equal(requiredFields.has("marginMinutes"), true);
  assert.equal(requiredFields.has("departureContext"), true);
  assert.equal(requiredFields.has("arrivalContext"), true);
});

test("requires recurring, task, and shopping compatibility fields", () => {
  const requiredFields = new Set(creationActionSchema.required);

  assert.equal(requiredFields.has("recurringUntil"), true);
  assert.equal(requiredFields.has("isImportant"), true);
  assert.equal(requiredFields.has("dueDate"), true);
  assert.equal(requiredFields.has("planning"), true);
  assert.equal(requiredFields.has("priority"), true);
  assert.equal(requiredFields.has("isUrgent"), true);
  assert.equal(requiredFields.has("section"), true);
});

test("defines a closed nullable event participant contract", () => {
  const requiredFields = new Set(creationActionSchema.required);
  const objectSchema = eventParticipantSchema.anyOf[0];

  assert.equal(requiredFields.has("participant"), true);
  assert.equal(
      creationActionSchema.properties.participant,
      eventParticipantSchema,
  );
  assert.equal(objectSchema.additionalProperties, false);
  assert.deepEqual(
      objectSchema.required,
      ["label", "entityType", "evidence"],
  );
  assert.deepEqual(objectSchema.properties.entityType.enum, ["person"]);
  assert.deepEqual(
      objectSchema.properties.evidence.enum,
      ["explicit_user_input"],
  );
  assert.equal(objectSchema.properties.label.maxLength, 120);
  assert.equal(eventParticipantSchema.anyOf[1].type, "null");
});

test("defines memories using the Flutter memory contract", () => {
  assert.equal(memorySchema.additionalProperties, false);

  assert.deepEqual(
      memorySchema.required,
      ["text", "category", "importance"],
  );

  assert.equal(
      memorySchema.properties.importance.minimum,
      0,
  );

  assert.equal(
      memorySchema.properties.importance.maximum,
      3,
  );
});

test("uses strict schemas at every object level", () => {
  assert.equal(
      zeliaResponseJsonSchema.additionalProperties,
      false,
  );

  assert.equal(creationActionSchema.additionalProperties, false);
  for (const variant of eventMutationActionSchema.anyOf) {
    assert.equal(variant.additionalProperties, false);
  }

  assert.equal(
      memorySchema.additionalProperties,
      false,
  );
});

test("defines closed event mutation operations", () => {
  const [update, replace, remove] = eventMutationActionSchema.anyOf;
  assert.deepEqual(update.required,
      ["type", "operation", "target", "changes"]);
  assert.deepEqual(update.properties.type.enum,
      ["event_mutation"]);
  assert.deepEqual(update.properties.operation.enum,
      ["update"]);
  assert.deepEqual(replace.required,
      ["type", "operation", "target", "participant"]);
  assert.deepEqual(replace.properties.operation.enum,
      ["replace_participant"]);
  assert.deepEqual(remove.required, ["type", "operation", "target"]);
  assert.deepEqual(remove.properties.operation.enum, ["remove_participant"]);
  assert.equal(eventMutationTargetSchema.additionalProperties, false);
  assert.equal(eventMutationChangesSchema.additionalProperties, false);
  assert.deepEqual(
      eventMutationTargetSchema.required,
      Object.keys(eventMutationTargetSchema.properties),
  );
  assert.deepEqual(
      eventMutationChangesSchema.required,
      Object.keys(eventMutationChangesSchema.properties),
  );
  assert.equal("id" in eventMutationTargetSchema.properties, false);
  assert.equal("participantIdentity" in eventMutationChangesSchema.properties,
      false);
});
