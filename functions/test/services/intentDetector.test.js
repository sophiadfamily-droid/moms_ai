const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeText,
  containsPhrase,
  extractTaskCreation,
  detectIntent,
} = require("../../brain/engines/intentDetector");

test("normalizes accents and apostrophes", () => {
  assert.equal(
      normalizeText("J’ai rendez-vous chez le médecin"),
      "j ai rendez vous chez le medecin",
  );
});

test("extracts known task fields without inventing a title", () => {
  assert.deepEqual(
      extractTaskCreation(
          "Crée une tâche prioritaire pour demain.",
          new Date("2026-07-27T10:00:00.000Z"),
      ),
      {
        isCreation: true,
        title: "",
        priority: "high",
        isImportant: true,
        dueDate: "2026-07-28",
      },
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

test("detects an explicit incomplete task creation request", () => {
  assert.equal(
      detectIntent("Crée une tâche prioritaire pour demain.").primaryIntent,
      "task",
  );
});

test("detects normalized explicit task creation formulations", () => {
  for (const message of [
    "CRÉER UNE TÂCHE !",
    "Ajoute une tâche.",
    "Note-moi une tâche",
    "Mets dans mes tâches : appeler Léa",
    "Ajoute à ma liste de tâches.",
  ]) {
    assert.equal(detectIntent(message).primaryIntent, "task", message);
  }
});

test("does not turn task mentions into creation", () => {
  for (const message of [
    "Cette tâche est prioritaire.",
    "Quelle est la définition d’une tâche ?",
    "Quelles sont mes priorités ?",
    "Supposons que je crée une tâche.",
  ]) {
    assert.equal(detectIntent(message).primaryIntent, "general", message);
  }
});

test("keeps an explanatory organization question as general", () => {
  assert.equal(
      detectIntent(
          "Explique-moi comment mieux organiser mes documents",
      ).primaryIntent,
      "general",
  );
});
