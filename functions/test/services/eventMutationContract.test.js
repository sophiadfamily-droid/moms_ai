const assert = require("node:assert/strict");
const test = require("node:test");

const {
  sanitizeEventMutations,
  validateEventMutation,
} = require("../../services/eventMutationContract");

const valid = {
  type: "event_mutation",
  operation: "update",
  target: {title: "Rendez-vous médecin", date: "2026-07-23", time: "10:00"},
  changes: {time: "11:00"},
};

test("accepts a closed update mutation", () => {
  assert.deepEqual(validateEventMutation(
      valid,
      "Décale mon Rendez-vous médecin du 23 juillet de 10 h à 11 h",
  ), valid);
});

test("rejects unknown operations, empty target and empty changes", () => {
  assert.equal(
      validateEventMutation({...valid, operation: "delete"}, "modifie"),
      null,
  );
  assert.equal(validateEventMutation({...valid, target: {}}, "modifie"), null);
  assert.equal(validateEventMutation({...valid, changes: {}}, "modifie"), null);
});

test("rejects extra, identity, participant and id fields", () => {
  for (const mutation of [
    {...valid, extra: true},
    {...valid, target: {...valid.target, id: "forbidden"}},
    {...valid, changes: {...valid.changes, participantIdentity: {}}},
    {...valid, changes: {...valid.changes, participantMutation: {}}},
  ]) {
    assert.equal(
        validateEventMutation(mutation, "modifie Rendez-vous médecin"),
        null,
    );
  }
});

test("rejects malformed and out-of-bounds changes", () => {
  assert.equal(
      validateEventMutation({...valid, changes: {time: null}}, "modifie"),
      null,
  );
  assert.equal(validateEventMutation({
    ...valid, changes: {durationMinutes: 0},
  }, "modifie"), null);
  assert.equal(validateEventMutation({
    ...valid, changes: {travelGoMinutes: 481},
  }, "modifie"), null);
});

test("rejects a mutation not grounded in the original message", () => {
  assert.equal(validateEventMutation(valid, "Parle-moi de mon agenda"), null);
  assert.equal(validateEventMutation(valid, "Décale mon rendez-vous dentiste"),
      null);
});

test("removes an invalid mutation without corrupting valid actions", () => {
  const logs = [];
  const creation = {type: "event", title: "Autre"};
  const result = sanitizeEventMutations(
      [creation, {...valid, operation: "remove"}, valid],
      "Décale le Rendez-vous médecin à 11 h",
      {info: (message, data) => logs.push({message, data})},
  );
  assert.deepEqual(result, [creation, valid]);
  assert.equal(logs[0].data.code, "invalid_event_mutation_removed");
});
