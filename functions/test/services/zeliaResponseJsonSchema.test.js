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
  assert.equal(eventMutationActionSchema.additionalProperties, false);

  assert.equal(
      memorySchema.additionalProperties,
      false,
  );
});

test("defines a closed update-only event mutation action", () => {
  assert.deepEqual(eventMutationActionSchema.required,
      ["type", "operation", "target", "changes"]);
  assert.deepEqual(eventMutationActionSchema.properties.type.enum,
      ["event_mutation"]);
  assert.deepEqual(eventMutationActionSchema.properties.operation.enum,
      ["update"]);
  assert.equal(eventMutationTargetSchema.additionalProperties, false);
  assert.equal(eventMutationChangesSchema.additionalProperties, false);
  assert.equal("id" in eventMutationTargetSchema.properties, false);
  assert.equal("participantIdentity" in eventMutationChangesSchema.properties,
      false);
});
