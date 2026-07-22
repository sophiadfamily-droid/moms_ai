const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ACTION_TYPES,
  actionSchema,
  memorySchema,
  eventParticipantSchema,
  zeliaResponseJsonSchema,
} = require("../../brain/zeliaResponseJsonSchema");

test("defines the supported action types", () => {
  assert.deepEqual(
      ACTION_TYPES,
      ["shopping", "task", "event"],
  );
});

test("requires every top-level response field", () => {
  assert.deepEqual(
      zeliaResponseJsonSchema.required,
      ["reply", "actions", "memories"],
  );

  assert.equal(
      zeliaResponseJsonSchema.additionalProperties,
      false,
  );
});

test("defines actions as a strict array of action objects", () => {
  const actions = zeliaResponseJsonSchema.properties.actions;

  assert.equal(actions.type, "array");
  assert.equal(actions.items, actionSchema);
  assert.equal(actionSchema.additionalProperties, false);
});

test("requires the separate travel fields", () => {
  const requiredFields = new Set(actionSchema.required);

  assert.equal(requiredFields.has("travelMinutes"), true);
  assert.equal(requiredFields.has("travelGoMinutes"), true);
  assert.equal(requiredFields.has("travelBackMinutes"), true);
  assert.equal(requiredFields.has("usesSeparateTravelTimes"), true);
  assert.equal(requiredFields.has("marginMinutes"), true);
  assert.equal(requiredFields.has("departureContext"), true);
  assert.equal(requiredFields.has("arrivalContext"), true);
});

test("requires recurring, task, and shopping compatibility fields", () => {
  const requiredFields = new Set(actionSchema.required);

  assert.equal(requiredFields.has("recurringUntil"), true);
  assert.equal(requiredFields.has("isImportant"), true);
  assert.equal(requiredFields.has("dueDate"), true);
  assert.equal(requiredFields.has("planning"), true);
  assert.equal(requiredFields.has("priority"), true);
  assert.equal(requiredFields.has("isUrgent"), true);
  assert.equal(requiredFields.has("section"), true);
});

test("defines a closed nullable event participant contract", () => {
  const requiredFields = new Set(actionSchema.required);
  const objectSchema = eventParticipantSchema.anyOf[0];

  assert.equal(requiredFields.has("participant"), true);
  assert.equal(actionSchema.properties.participant, eventParticipantSchema);
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

  assert.equal(
      actionSchema.additionalProperties,
      false,
  );

  assert.equal(
      memorySchema.additionalProperties,
      false,
  );
});
