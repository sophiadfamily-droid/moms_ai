const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  arrayUnion,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

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

test("owner can remember a preference from a general life category", async () => {
  const generalId = "general-memory-proposal";
  const canonicalKey =
    "v1|preference|general_preference|authenticated_user|scope|general|none";
  const semanticIdentity = {
    schemaVersion: 1,
    domain: "preference",
    attribute: "general_preference",
    subjectScope: "authenticated_user",
    contextType: "general",
    canonicalKey,
    eligibleForAutomaticContradiction: false,
  };
  const db = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(
    setDoc(
      doc(db, "users", ownerId, "memories", generalId),
      memory({
        memoryId: generalId,
        category: "shopping",
        semanticType: "unknown",
        semanticIdentity,
        canonicalKey,
        semanticValue: "souviens toi que je prefere faire mes courses le matin",
        eligibleForAutomaticContradiction: false,
      }),
    ),
  );
});

test("owner can activate an explicitly requested general preference", async () => {
  const generalId = "explicit-general-memory";
  const canonicalKey =
    "v1|preference|general_preference|authenticated_user|scope|general|none";
  const db = environment.authenticatedContext(ownerId).firestore();
  const reference = doc(db, "users", ownerId, "memories", generalId);
  await assertSucceeds(
    setDoc(
      reference,
      memory({
        memoryId: generalId,
        category: "preference",
        semanticType: "preference",
        semanticIdentity: {
          schemaVersion: 1,
          domain: "preference",
          attribute: "general_preference",
          subjectScope: "authenticated_user",
          contextType: "general",
          canonicalKey,
          eligibleForAutomaticContradiction: false,
        },
        canonicalKey,
        semanticValue: "j aime preparer mes affaires la veille",
        eligibleForAutomaticContradiction: false,
        lastMutationId: "propose::proposed:explicit-general-memory:",
        lifecycleHistory: [
          {
            action: "propose",
            previousState: null,
            newState: "proposed",
            occurredAt: "2026-08-17T09:00:00.000Z",
            source: "explicit_user_message",
            actor: "system",
            memoryId: generalId,
          },
        ],
      }),
    ),
  );
  await assertSucceeds(
    updateDoc(reference, {
      memoryRevision: 2,
      lifecycleState: "active",
      lifecycleStatus: "active",
      confirmationStatus: "confirmed",
      confirmedAt: new Date("2026-08-17T09:00:00.000Z"),
      tombstone: false,
      lastMutationId: "activate:confirmed:active:explicit-general-memory:",
      updatedAt: serverTimestamp(),
      lifecycleHistory: arrayUnion(
        {
          action: "confirm",
          previousState: "proposed",
          newState: "confirmed",
          occurredAt: "2026-08-17T09:00:00.000Z",
          source: "explicit_user_memory_directive",
          actor: "user",
          memoryId: generalId,
        },
        {
          action: "activate",
          previousState: "confirmed",
          newState: "active",
          occurredAt: "2026-08-17T09:00:00.000Z",
          source: "explicit_user_memory_directive",
          actor: "user",
          memoryId: generalId,
        },
      ),
    }),
  );
});

test("owner can create an explicit preference already active atomically", async () => {
  const generalId = "atomic-explicit-general-memory";
  const canonicalKey =
    "v1|preference|general_preference|authenticated_user|scope|general|none";
  const occurredAt = "2026-08-17T09:00:00.000Z";
  const db = environment.authenticatedContext(ownerId).firestore();

  await assertSucceeds(
    setDoc(
      doc(db, "users", ownerId, "memories", generalId),
      memory({
        memoryId: generalId,
        category: "preference",
        semanticType: "preference",
        semanticIdentity: {
          schemaVersion: 1,
          domain: "preference",
          attribute: "general_preference",
          subjectScope: "authenticated_user",
          contextType: "general",
          canonicalKey,
          eligibleForAutomaticContradiction: false,
        },
        canonicalKey,
        semanticValue: "j aime preparer mes affaires la veille",
        eligibleForAutomaticContradiction: false,
        lifecycleState: "active",
        lifecycleStatus: "active",
        confirmationStatus: "confirmed",
        confirmedAt: new Date(occurredAt),
        lastMutationId: "activate:confirmed:active:atomic-explicit-general-memory:",
        lifecycleHistory: [
          {
            action: "propose",
            previousState: null,
            newState: "proposed",
            occurredAt,
            source: "explicit_user_message",
            actor: "system",
            memoryId: generalId,
          },
          {
            action: "confirm",
            previousState: "proposed",
            newState: "confirmed",
            occurredAt,
            source: "explicit_user_memory_directive",
            actor: "user",
            memoryId: generalId,
          },
          {
            action: "activate",
            previousState: "confirmed",
            newState: "active",
            occurredAt,
            source: "explicit_user_memory_directive",
            actor: "user",
            memoryId: generalId,
          },
        ],
      }),
    ),
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
