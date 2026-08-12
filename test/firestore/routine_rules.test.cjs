const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  runTransaction,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "zelia-ai-app";
const ownerId = "routine-owner";
const otherId = "routine-other";
const proposalId = "a".repeat(64);
const logicalRequestId = "request-synthetic";
const title = "activite-synthetique";
let environment;

function future(minutes = 30) {
  return Timestamp.fromMillis(Date.now() + minutes * 60 * 1000);
}

function past(minutes = 1) {
  return Timestamp.fromMillis(Date.now() - minutes * 60 * 1000);
}

function proposal(overrides = {}) {
  const now = Timestamp.now();
  return {
    schemaVersion: 1,
    proposalId,
    logicalRequestId,
    accountScopeId: ownerId,
    state: "awaitingConfirmation",
    title,
    recurrenceType: "weekly",
    days: [2],
    startTime: "09:00",
    durationMinutes: 60,
    travelGoMinutes: 10,
    travelBackMinutes: 20,
    marginMinutes: 5,
    humanPersonId: null,
    locationEntityId: null,
    anchorDateIso: null,
    weekOfMonth: null,
    createdAt: now,
    updatedAt: now,
    expiresAt: future(),
    ...overrides,
  };
}

function routine(source = proposal(), overrides = {}) {
  const now = Timestamp.now();
  const value = {
    schemaVersion: source.schemaVersion,
    id: source.proposalId,
    proposalId: source.proposalId,
    logicalRequestId: source.logicalRequestId,
    accountScopeId: source.accountScopeId,
    title: source.title,
    recurrenceType: source.recurrenceType,
    days: source.days,
    startTime: source.startTime,
    durationMinutes: source.durationMinutes,
    travelGoMinutes: source.travelGoMinutes,
    travelBackMinutes: source.travelBackMinutes,
    marginMinutes: source.marginMinutes,
    humanPersonId: source.humanPersonId,
    locationEntityId: source.locationEntityId,
    anchorDateIso: source.anchorDateIso,
    weekOfMonth: source.weekOfMonth,
    status: "active",
    createdAt: now,
    updatedAt: now,
  };
  return {...value, ...overrides};
}

function dbFor(uid = ownerId) {
  return environment.authenticatedContext(uid).firestore();
}

function proposalRef(db, uid = ownerId, id = proposalId) {
  return doc(db, "users", uid, "routineProposals", id);
}

function routineRef(db, uid = ownerId, id = proposalId) {
  return doc(db, "users", uid, "routines", id);
}

function overrideRef(db, uid = ownerId, id = "override-a") {
  return doc(db, "users", uid, "routineOccurrenceOverrides", id);
}

function occurrenceOverride(overrides = {}) {
  const now = Timestamp.now();
  return {
    schemaVersion: 1,
    overrideId: "override-a",
    accountScopeId: ownerId,
    routineId: proposalId,
    sourceDateIso: "2026-08-04",
    type: "cancelled",
    replacementDateIso: null,
    replacementStartTime: null,
    replacementEntityId: null,
    tombstone: false,
    overrideRevision: 1,
    lastMutationId: "mutation-a",
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

async function seedProposal(value) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(proposalRef(context.firestore()), value);
  });
}

async function seedRoutine(value) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(routineRef(context.firestore()), value);
  });
}

async function commit(db, value = proposal()) {
  await runTransaction(db, async (transaction) => {
    const proposalDocument = proposalRef(db);
    const routineDocument = routineRef(db);
    await transaction.get(proposalDocument);
    await transaction.get(routineDocument);
    transaction.set(routineDocument, routine(value));
    transaction.update(proposalDocument, {
      state: "committed",
      updatedAt: Timestamp.now(),
    });
  });
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

test("owner creates and reads a collecting proposal", async () => {
  const db = dbFor();
  const value = proposal({
    state: "collecting",
    title: null,
    startTime: null,
    durationMinutes: null,
  });
  await assertSucceeds(setDoc(proposalRef(db), value));
  await assertSucceeds(getDoc(proposalRef(db)));
});

test("owner completes collecting proposal to awaitingConfirmation", async () => {
  const db = dbFor();
  const collecting = proposal({state: "collecting"});
  await assertSucceeds(setDoc(proposalRef(db), collecting));
  await assertSucceeds(
    setDoc(
      proposalRef(db),
      {...collecting, state: "awaitingConfirmation", updatedAt: Timestamp.now()},
      {merge: false},
    ),
  );
});

test("atomic confirmation creates routine and commits proposal", async () => {
  const db = dbFor();
  const value = proposal();
  await assertSucceeds(setDoc(proposalRef(db), value));
  await assertSucceeds(commit(db, value));
  assert.equal((await getDoc(routineRef(db))).exists(), true);
  assert.equal((await getDoc(proposalRef(db))).data().state, "committed");
});

for (const [name, changes] of [
  ["weekly", {}],
  ["weekdays", {recurrenceType: "weekdays", days: []}],
  ["biweekly", {recurrenceType: "biweekly", anchorDateIso: "2026-07-27"}],
  ["monthly nth weekday", {recurrenceType: "monthlyNthWeekday", weekOfMonth: 2}],
  ["monthly last weekday", {recurrenceType: "monthlyNthWeekday", weekOfMonth: -1}],
]) {
  test(`valid recurrence commits atomically: ${name}`, async () => {
    const db = dbFor();
    const value = proposal({
      humanPersonId: "person-synthetic",
      locationEntityId: "place-synthetic",
      ...changes,
    });
    await setDoc(proposalRef(db), value);
    await assertSucceeds(commit(db, value));
    assert.equal((await getDoc(routineRef(db))).exists(), true);
    assert.equal((await getDoc(proposalRef(db))).data().state, "committed");
  });
}

test("identical existing routine permits idempotent commit", async () => {
  const db = dbFor();
  const value = proposal();
  await seedProposal(value);
  await seedRoutine(routine(value));
  await assertSucceeds(
    updateDoc(proposalRef(db), {
      state: "committed",
      updatedAt: Timestamp.now(),
    }),
  );
});

test("owner reads own routine while other and unauthenticated users cannot", async () => {
  const value = proposal();
  await seedRoutine(routine(value));
  await assertSucceeds(getDoc(routineRef(dbFor())));
  await assertFails(getDoc(routineRef(dbFor(otherId))));
  await assertFails(
    getDoc(routineRef(environment.unauthenticatedContext().firestore())),
  );
});

test("foreign scope, extra field and wrong type are refused", async () => {
  const db = dbFor();
  await assertFails(
    setDoc(proposalRef(db), proposal({accountScopeId: otherId})),
  );
  await assertFails(setDoc(proposalRef(db), proposal({unexpected: true})));
  await assertFails(setDoc(proposalRef(db), proposal({durationMinutes: "60"})));
});

for (const [name, changes] of [
  ["weekly empty days", {recurrenceType: "weekly", days: []}],
  ["weekly anchor", {recurrenceType: "weekly", anchorDateIso: "2026-07-27"}],
  ["weekdays days", {recurrenceType: "weekdays", days: [2]}],
  ["weekdays anchor", {recurrenceType: "weekdays", days: [], anchorDateIso: "2026-07-27"}],
  ["biweekly missing anchor", {recurrenceType: "biweekly", days: [2]}],
  ["biweekly empty days", {recurrenceType: "biweekly", days: [], anchorDateIso: "2026-07-27"}],
  ["monthly missing week", {recurrenceType: "monthlyNthWeekday", days: [2]}],
  ["monthly multiple days", {recurrenceType: "monthlyNthWeekday", days: [2, 3], weekOfMonth: 2}],
  ["monthly invalid week", {recurrenceType: "monthlyNthWeekday", days: [2], weekOfMonth: 0}],
  ["monthly anchor", {recurrenceType: "monthlyNthWeekday", days: [2], weekOfMonth: -1, anchorDateIso: "2026-07-27"}],
]) {
  test(`invalid recurrence is refused: ${name}`, async () => {
    await assertFails(setDoc(proposalRef(dbFor()), proposal(changes)));
  });
}

for (const [field, value] of [
  ["startTime", "25:99"],
  ["startTime", "9h30"],
  ["anchorDateIso", "abcdefghij"],
  ["anchorDateIso", "2026-99-99"],
  ["anchorDateIso", "2026-00-00"],
]) {
  test(`invalid temporal value is refused: ${field} ${value}`, async () => {
    const changes = field === "anchorDateIso"
      ? {recurrenceType: "biweekly", [field]: value}
      : {[field]: value};
    await assertFails(setDoc(proposalRef(dbFor()), proposal(changes)));
  });
}

for (const field of ["createdAt", "updatedAt", "expiresAt"]) {
  test(`non Timestamp ${field} is refused`, async () => {
    await assertFails(
      setDoc(proposalRef(dbFor()), proposal({[field]: "arbitrary"})),
    );
    await assertFails(
      setDoc(proposalRef(dbFor()), proposal({[field]: ""})),
    );
  });
}

for (const field of [
  "title",
  "recurrenceType",
  "startTime",
  "durationMinutes",
]) {
  test(`awaitingConfirmation without ${field} is refused`, async () => {
    const value = proposal();
    delete value[field];
    await assertFails(setDoc(proposalRef(dbFor()), value));
  });
}

test("collecting cannot jump directly to committed", async () => {
  const db = dbFor();
  await setDoc(proposalRef(db), proposal({state: "collecting"}));
  await assertFails(
    updateDoc(proposalRef(db), {
      state: "committed",
      updatedAt: Timestamp.now(),
    }),
  );
});

test("expired proposal refuses atomic confirmation without partial write", async () => {
  const db = dbFor();
  const value = proposal({createdAt: past(2), updatedAt: past(2), expiresAt: past()});
  await seedProposal(value);
  await assertFails(commit(db, value));
  assert.equal((await getDoc(routineRef(db))).exists(), false);
  assert.equal((await getDoc(proposalRef(db))).data().state, "awaitingConfirmation");
});

test("expiration at the current boundary refuses confirmation", async () => {
  const db = dbFor();
  const boundary = Timestamp.now();
  const value = proposal({
    createdAt: past(2),
    updatedAt: past(2),
    expiresAt: boundary,
  });
  await seedProposal(value);
  await assertFails(commit(db, value));
  assert.equal((await getDoc(routineRef(db))).exists(), false);
  assert.equal((await getDoc(proposalRef(db))).data().state, "awaitingConfirmation");
});

for (const state of ["declined", "cancelled"]) {
  test(`${state} proposal cannot create a routine`, async () => {
    const db = dbFor();
    const value = proposal({state});
    await seedProposal(value);
    await assertFails(setDoc(routineRef(db), routine(value)));
  });
}

test("routine without proposal is refused", async () => {
  await assertFails(setDoc(routineRef(dbFor()), routine()));
});

test("committed proposal without coherent routine is refused", async () => {
  const db = dbFor();
  await seedProposal(proposal());
  await assertFails(
    updateDoc(proposalRef(db), {
      state: "committed",
      updatedAt: Timestamp.now(),
    }),
  );
});

test("mismatched routine payload makes the entire transaction fail", async () => {
  const db = dbFor();
  const value = proposal();
  await setDoc(proposalRef(db), value);
  await assertFails(
    runTransaction(db, async (transaction) => {
      await transaction.get(proposalRef(db));
      await transaction.get(routineRef(db));
      transaction.set(routineRef(db), routine(value, {durationMinutes: 61}));
      transaction.update(proposalRef(db), {
        state: "committed",
        updatedAt: Timestamp.now(),
      });
    }),
  );
  assert.equal((await getDoc(routineRef(db))).exists(), false);
  assert.equal((await getDoc(proposalRef(db))).data().state, "awaitingConfirmation");
});

for (const [name, proposalChanges, routineChanges] of [
  ["id/proposalId", {}, {id: "b".repeat(64), proposalId: "b".repeat(64)}],
  ["accountScopeId", {}, {accountScopeId: otherId}],
  ["logicalRequestId", {}, {logicalRequestId: "other-request"}],
  ["title", {}, {title: "autre-activite-synthetique"}],
  ["humanPersonId", {}, {humanPersonId: "person-synthetic"}],
  ["recurrence", {}, {recurrenceType: "weekdays", days: []}],
  ["days", {}, {days: [3]}],
  ["startTime", {}, {startTime: "10:00"}],
  ["durationMinutes", {}, {durationMinutes: 61}],
  ["anchorDateIso", {recurrenceType: "biweekly", anchorDateIso: "2026-07-27"}, {anchorDateIso: "2026-08-03"}],
  ["weekOfMonth", {recurrenceType: "monthlyNthWeekday", weekOfMonth: 2}, {weekOfMonth: -1}],
  ["travelGoMinutes", {}, {travelGoMinutes: 11}],
  ["travelBackMinutes", {}, {travelBackMinutes: 21}],
  ["marginMinutes", {}, {marginMinutes: 6}],
  ["locationEntityId", {}, {locationEntityId: "place-synthetic"}],
  ["status", {}, {status: "cancelled"}],
  ["schemaVersion", {}, {schemaVersion: 2}],
]) {
  test(`canonical routine mismatch is refused atomically: ${name}`, async () => {
    const db = dbFor();
    const value = proposal(proposalChanges);
    await setDoc(proposalRef(db), value);
    await assertFails(
      runTransaction(db, async (transaction) => {
        await transaction.get(proposalRef(db));
        await transaction.get(routineRef(db));
        transaction.set(routineRef(db), routine(value, routineChanges));
        transaction.update(proposalRef(db), {
          state: "committed",
          updatedAt: Timestamp.now(),
        });
      }),
    );
    assert.equal((await getDoc(routineRef(db))).exists(), false);
    assert.equal(
      (await getDoc(proposalRef(db))).data().state,
      "awaitingConfirmation",
    );
  });
}

test("routine and proposal cannot be modified or deleted after commit", async () => {
  const db = dbFor();
  const value = proposal();
  await setDoc(proposalRef(db), value);
  await commit(db, value);
  await assertFails(updateDoc(routineRef(db), {durationMinutes: 61}));
  await assertFails(deleteDoc(routineRef(db)));
  await assertFails(deleteDoc(proposalRef(db)));
});

test("owner creates and revises one occurrence override", async () => {
  const db = dbFor();
  const value = proposal();
  await setDoc(proposalRef(db), value);
  await commit(db, value);
  const original = occurrenceOverride();
  await assertSucceeds(setDoc(overrideRef(db), original));
  await assertSucceeds(getDoc(overrideRef(db)));
  await assertSucceeds(
    setDoc(overrideRef(db), {
      ...original,
      type: "moved",
      replacementDateIso: "2026-08-06",
      replacementStartTime: "18:30",
      overrideRevision: 2,
      lastMutationId: "mutation-b",
      updatedAt: Timestamp.now(),
    }),
  );
});

test("occurrence override is owner-only and requires an existing routine", async () => {
  const db = dbFor();
  await assertFails(setDoc(overrideRef(db), occurrenceOverride()));
  await assertFails(
    setDoc(
      overrideRef(dbFor(otherId), otherId),
      occurrenceOverride({accountScopeId: ownerId}),
    ),
  );
});

for (const [name, changes] of [
  ["foreign account", {accountScopeId: otherId}],
  ["invalid source date", {sourceDateIso: "2026-02-31"}],
  ["non-leap February 29", {sourceDateIso: "2025-02-29"}],
  ["unknown type", {type: "skipped"}],
  ["first revision already tombstoned", {tombstone: true}],
  ["cancelled with destination", {
    replacementDateIso: "2026-08-06",
    replacementStartTime: "18:30",
  }],
  ["moved without destination", {type: "moved"}],
]) {
  test(`invalid occurrence override is refused: ${name}`, async () => {
    const db = dbFor();
    const value = proposal();
    await setDoc(proposalRef(db), value);
    await commit(db, value);
    await assertFails(
      setDoc(overrideRef(db), occurrenceOverride(changes)),
    );
  });
}

test("occurrence override refuses stale revisions, identity changes and delete", async () => {
  const db = dbFor();
  const value = proposal();
  await setDoc(proposalRef(db), value);
  await commit(db, value);
  const original = occurrenceOverride();
  await setDoc(overrideRef(db), original);
  await assertFails(
    setDoc(overrideRef(db), {
      ...original,
      type: "replaced",
      replacementEntityId: "event-a",
      lastMutationId: "mutation-b",
      updatedAt: Timestamp.now(),
    }),
  );
  await assertFails(
    setDoc(overrideRef(db), {
      ...original,
      routineId: "b".repeat(64),
      overrideRevision: 2,
      lastMutationId: "mutation-b",
      updatedAt: Timestamp.now(),
    }),
  );
  await assertFails(deleteDoc(overrideRef(db)));
});
