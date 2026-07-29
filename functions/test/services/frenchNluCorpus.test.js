"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const corpus = require("../fixtures/frenchNluCorpus");
const sharedCases = require(
    "../../../test/fixtures/nlu_contract_cases.json",
);
const {
  UNDERSTANDING_LEVELS,
  normalizeNaturalLanguage,
} = require("../../brain/engines/naturalLanguageNormalizer");
const {detectIntent} = require("../../brain/engines/intentDetector");

test("versioned French corpus contains the required 200 examples", () => {
  assert.equal(corpus.length, 200);
  const counts = Object.groupBy(corpus, (entry) => entry.expectedIntent);
  assert.equal(counts.task.length, 40);
  assert.equal(counts.event.length, 40);
  assert.equal(counts.shopping.length, 35);
  assert.equal(counts.routine.length, 25);
  assert.equal(counts.memory.length, 25);
  assert.equal(counts.priority.length, 20);
  assert.equal(counts.ambiguous.length, 15);
  assert.ok(corpus.every((entry) => entry.synthetic === true));
  assert.equal(new Set(corpus.map((entry) => entry.rawText)).size, 200);
});

test("corpus normalization is stable with an explicit 100% target", () => {
  const successful = corpus.filter((entry) =>
    normalizeNaturalLanguage(entry.rawText).normalizedText ===
      entry.normalizedText,
  );
  assert.equal(successful.length / corpus.length, 1);
});

test("critical negations and ambiguities never authorize an action", () => {
  const critical = corpus.filter((entry) =>
    entry.expectedIntent === "ambiguous",
  );
  for (const entry of critical) {
    const result = detectIntent(entry.rawText);
    assert.equal(result.actionAllowed, false, entry.rawText);
  }
});

test("normalizer exposes only closed understanding levels", () => {
  assert.deepEqual(UNDERSTANDING_LEVELS, [
    "exactMatch",
    "normalizedMatch",
    "probableMatch",
    "ambiguous",
    "noMatch",
  ]);
});

test("Node matches the shared Flutter and Node contract fixtures", () => {
  for (const item of sharedCases) {
    const result = normalizeNaturalLanguage(item.raw);
    assert.equal(result.normalizedText, item.normalized, item.raw);
    assert.deepEqual(result.preservedAmbiguities, item.ambiguities, item.raw);
  }
});
