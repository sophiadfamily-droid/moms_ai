const assert = require("node:assert/strict");
const test = require("node:test");

const {
  normalizeText,
  detectPlanningComplexity,
} = require("../../brain/engines/planningComplexityDetector");

test("normalizes accents and apostrophes", () => {
  assert.equal(
      normalizeText("Organise l’école et mes tâches"),
      "organise l ecole et mes taches",
  );
});

test("keeps a standard appointment request non-complex", () => {
  const result = detectPlanningComplexity(
      "Ajoute un rendez-vous médecin demain à 14h",
  );

  assert.equal(result.requiresComplexPlanning, false);
});

test("keeps a simple slot search non-complex", () => {
  const result = detectPlanningComplexity(
      "Trouve-moi un créneau pour le médecin la semaine prochaine",
  );

  assert.equal(result.requiresComplexPlanning, false);
});

test("detects full-day organization as complex", () => {
  const result = detectPlanningComplexity(
      "Organise toute ma journée en tenant compte de l'école, " +
      "de mes rendez-vous, de mes tâches et de mes trajets",
  );

  assert.equal(result.requiresComplexPlanning, true);
  assert.ok(result.reasons.includes("explicit_complex_planning"));
});

test("detects multi-domain planning as complex", () => {
  const result = detectPlanningComplexity(
      "Organise mon planning avec mon travail, les rendez-vous, " +
      "les tâches et les activités des enfants",
  );

  assert.equal(result.requiresComplexPlanning, true);
  assert.ok(result.reasons.includes("multiple_life_domains"));
});

test("detects comparison of several weekly scenarios as complex", () => {
  const result = detectPlanningComplexity(
      "Compare plusieurs possibilités pour organiser ma semaine",
  );

  assert.equal(result.requiresComplexPlanning, true);
  assert.ok(result.reasons.includes("scenario_comparison"));
});
