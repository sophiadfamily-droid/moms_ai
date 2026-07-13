const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeText,
  containsPhrase,
  detectIntent,
} = require("../../brain/engines/intentDetector");

test("normalizes accents and apostrophes", () => {
  assert.equal(
      normalizeText("J’ai rendez-vous chez le médecin"),
      "j ai rendez vous chez le medecin",
  );
});

test("does not confuse cours with courses", () => {
  assert.equal(
      containsPhrase(normalizeText("Ajoute du lait aux courses"), "cours"),
      false,
  );

  assert.equal(
      detectIntent("Ajoute du lait et de l'eau aux courses").primaryIntent,
      "shopping",
  );
});

test("detects an actual course as an event", () => {
  assert.equal(
      detectIntent("J'ai un cours demain à 10h").primaryIntent,
      "event",
  );
});

test("detects a dentist slot request as an event", () => {
  assert.equal(
      detectIntent(
          "Trouve-moi un créneau pour le dentiste la semaine prochaine",
      ).primaryIntent,
      "event",
  );
});

test("detects a reminder as a task", () => {
  assert.equal(
      detectIntent("Rappelle-moi d'appeler l'assurance").primaryIntent,
      "task",
  );
});

test("keeps an explanatory organization question as general", () => {
  assert.equal(
      detectIntent(
          "Explique-moi comment mieux organiser mes documents",
      ).primaryIntent,
      "general",
  );
});
