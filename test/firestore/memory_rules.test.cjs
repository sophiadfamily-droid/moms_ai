const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, serverTimestamp, setDoc} = require("firebase/firestore");

const projectId = "zelia-ai-app";
const ownerId = "memory-owner";
const memoryId = "memory-proposal";
let environment;

function memory(overrides = {}) {
  const canonicalKey =
    "v1|planning|preferred_appointment_period|authenticated_user|scope|" +
    "personal_appointments|none";
  return {
    schemaVersion: 1,
    memoryId,
    accountScopeId: ownerId,
    memoryRevision: 1,
    text: "Je préfère les rendez-vous le matin",
    normalizedText: "je prefere les rendez vous le matin",
    category: "preference",
    semanticType: "preference",
    importance: 4,
    sensitivity: "standard",
    provenance: "memory",
    isHealth: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    confirmationStatus: "unconfirmed",
    lifecycleState: "proposed",
    lifecycleStatus: "proposed",
    evidenceClassification: "directExplicit",
    evidenceSubjectType: "user",
    evidenceRisks: [],
    isCorrection: false,
    semanticIdentity: {
      schemaVersion: 1,
      domain: "planning",
      attribute: "preferred_appointment_period",
      subjectScope: "authenticated_user",
      contextType: "personal_appointments",
      canonicalKey,
      eligibleForAutomaticContradiction: true,
    },
    canonicalKey,
    semanticValue: "morning",
    eligibleForAutomaticContradiction: true,
    lastMutationId: "memory-mutation-1",
    tombstone: false,
    lifecycleHistory: [],
    ...overrides,
  };
}

test.before(async () => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, "../../firestore.rules"),
    "utf8",
  );
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
});

test.after(async () => {
  await environment.cleanup();
});

test.beforeEach(async () => {
  await environment.clearFirestore();
});

test("owner can create a semantic memory proposal", async () => {
  const db = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(
    setDoc(doc(db, "users", ownerId, "memories", memoryId), memory()),
  );
});

test("another account cannot create the memory proposal", async () => {
  const db = environment.authenticatedContext("memory-other").firestore();
  await assertFails(
    setDoc(doc(db, "users", ownerId, "memories", memoryId), memory()),
  );
});

test("unknown memory fields remain refused", async () => {
  const db = environment.authenticatedContext(ownerId).firestore();
  await assertFails(
    setDoc(
      doc(db, "users", ownerId, "memories", memoryId),
      memory({unexpectedField: true}),
    ),
  );
});
