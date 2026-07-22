const assert = require("node:assert/strict");
const test = require("node:test");

const {
  MAX_PARTICIPANT_LABEL_LENGTH,
  sanitizeEventParticipants,
  validateExplicitEventParticipant,
} = require("../../services/eventParticipantContract");

const validParticipant = {
  label: "Person A",
  entityType: "person",
  evidence: "explicit_user_input",
};

test("accepts a literal explicit participant", () => {
  assert.deepEqual(
      validateExplicitEventParticipant(
          validParticipant,
          "Ajoute un rendez-vous avec Person A demain",
      ),
      validParticipant,
  );
});

test("matches case, accents, apostrophes, and surrounding punctuation", () => {
  const participant = {...validParticipant, label: "Élodie Martin"};
  assert.deepEqual(
      validateExplicitEventParticipant(
          participant,
          "Rendez-vous avec (elodie MARTIN), demain.",
      ),
      participant,
  );
});

test("rejects absent, relational, and pronominal references", () => {
  assert.equal(
      validateExplicitEventParticipant(
          validParticipant,
          "Ajoute un rendez-vous",
      ),
      null,
  );
  for (const label of [
    "elle",
    "mon médecin",
    "ma mère",
    "notre médecin Martin",
  ]) {
    assert.equal(
        validateExplicitEventParticipant(
            {...validParticipant, label},
            `Ajoute un rendez-vous avec ${label}`,
        ),
        null,
    );
  }
});

test("rejects invalid shape, provenance, type, and label length", () => {
  const message = "Rendez-vous avec Person A";
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    entityType: "place",
  }, message), null);
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    evidence: "model_inference",
  }, message), null);
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    entityId: "forbidden",
  }, message), null);
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    aliases: [],
  }, message), null);
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    metadata: {},
  }, message), null);
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    label: " ",
  }, message), null);
  const longLabel = "a".repeat(MAX_PARTICIPANT_LABEL_LENGTH + 1);
  assert.equal(validateExplicitEventParticipant({
    ...validParticipant,
    label: longLabel,
  }, longLabel), null);
});

test("removes invalid participant without rejecting the event", () => {
  const logs = [];
  const actions = [{
    type: "event",
    title: "Rendez-vous",
    participant: validParticipant,
  }];
  const result = sanitizeEventParticipants(
      actions,
      "Ajoute un rendez-vous demain",
      {info: (message, data) => logs.push({message, data})},
  );

  assert.deepEqual(result, [{type: "event", title: "Rendez-vous"}]);
  assert.equal(logs[0].data.code, "invalid_event_participant_removed");
  assert.deepEqual(actions[0].participant, validParticipant);
});

test("removes participant from non-event actions", () => {
  assert.deepEqual(
      sanitizeEventParticipants(
          [{type: "task", title: "Appeler", participant: validParticipant}],
          "Appeler Person A",
          {info() {}},
      ),
      [{type: "task", title: "Appeler"}],
  );
});
