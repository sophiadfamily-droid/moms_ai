import fs from 'node:fs';
import process from 'node:process';
import {fileURLToPath} from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (!emulatorHost) throw new Error('FIRESTORE_EMULATOR_HOST is required');
if (!projectId || !projectId.startsWith('zelia-y1-test-')) {
  throw new Error('GCLOUD_PROJECT must be a dedicated Y.1 test project');
}
const [host, portValue] = emulatorHost.split(':');
const environment = await initializeTestEnvironment({
  projectId,
  firestore: {
    host,
    port: Number(portValue),
    rules: fs.readFileSync(
      fileURLToPath(new URL('../../firestore.rules', import.meta.url)),
      'utf8',
    ),
  },
});

const entity = (entityId, overrides = {}) => ({
  schemaVersion: 1,
  accountScopeId: 'account-a',
  entityId,
  payload: {title: 'bounded', createdAt: '2026-07-23T10:00:00.000Z'},
  revision: 1,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  lastMutationId: 'create',
  syncStatus: 'synced',
  isTombstone: false,
  ...overrides,
});

const profile = (overrides = {}) => ({
  schemaVersion: 1,
  accountScopeId: 'account-a',
  entityId: 'profile',
  payload: {planningStyle: 'bounded'},
  profileRevision: 1,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  lastMutationId: 'profile-create',
  syncStatus: 'synced',
  legacyExtensions: {},
  projectionProvenance: 'profileOwned',
  ...overrides,
});

let checks = 0;
const succeeds = async (operation) => {
  await assertSucceeds(operation);
  checks++;
};
const fails = async (operation) => {
  await assertFails(operation);
  checks++;
};

try {
  const owner = environment.authenticatedContext('account-a').firestore();
  const other = environment.authenticatedContext('account-b').firestore();
  const guest = environment.unauthenticatedContext().firestore();
  const task = doc(owner, 'users/account-a/tasks/task-a');
  const shopping = doc(owner, 'users/account-a/shopping_items/item-a');
  const profileRef = doc(owner, 'users/account-a/private/profile');

  await succeeds(setDoc(task, entity('task-a')));
  await succeeds(getDoc(task));
  await fails(setDoc(
    doc(other, 'users/account-a/tasks/task-b'),
    entity('task-b'),
  ));
  await fails(setDoc(
    doc(guest, 'users/account-a/tasks/task-c'),
    entity('task-c'),
  ));
  await succeeds(updateDoc(task, {
    payload: {title: 'updated'},
    revision: 2,
    updatedAt: serverTimestamp(),
    lastMutationId: 'task-update',
  }));
  await fails(updateDoc(task, {
    revision: 4,
    updatedAt: serverTimestamp(),
    lastMutationId: 'task-stale',
  }));
  await fails(updateDoc(task, {
    revision: 3,
    updatedAt: serverTimestamp(),
    lastMutationId: 'task-update',
  }));
  await succeeds(updateDoc(task, {
    revision: 3,
    isTombstone: true,
    updatedAt: serverTimestamp(),
    lastMutationId: 'task-delete',
  }));
  await fails(updateDoc(task, {
    revision: 4,
    isTombstone: false,
    updatedAt: serverTimestamp(),
    lastMutationId: 'task-resurrect',
  }));

  await succeeds(setDoc(shopping, entity('item-a', {clearGeneration: 0})));
  await fails(setDoc(
    doc(other, 'users/account-a/shopping_items/item-b'),
    entity('item-b', {clearGeneration: 0}),
  ));
  await succeeds(updateDoc(shopping, {
    revision: 2,
    isTombstone: true,
    clearGeneration: 1,
    updatedAt: serverTimestamp(),
    lastMutationId: 'shopping-remove',
  }));
  await fails(updateDoc(shopping, {
    revision: 3,
    isTombstone: false,
    updatedAt: serverTimestamp(),
    lastMutationId: 'shopping-resurrect',
  }));

  await succeeds(setDoc(profileRef, profile()));
  await fails(setDoc(
    doc(other, 'users/account-a/private/profile'),
    profile(),
  ));
  await succeeds(updateDoc(profileRef, {
    payload: {planningStyle: 'strict'},
    profileRevision: 2,
    updatedAt: serverTimestamp(),
    lastMutationId: 'profile-update',
  }));
  await fails(updateDoc(profileRef, {
    profileRevision: 4,
    updatedAt: serverTimestamp(),
    lastMutationId: 'profile-stale',
  }));
  await fails(updateDoc(profileRef, {
    payload: {firstName: 'must-stay-in-human-model'},
    profileRevision: 3,
    updatedAt: serverTimestamp(),
    lastMutationId: 'profile-human-overwrite',
  }));

  // Two clients read revision 1; only the first exact transaction succeeds.
  const first = doc(owner, 'users/account-a/tasks/concurrent');
  await succeeds(setDoc(first, entity('concurrent')));
  const firstWrite = runTransaction(owner, async (transaction) => {
    const snapshot = await transaction.get(first);
    transaction.update(first, {
      revision: snapshot.data().revision + 1,
      updatedAt: serverTimestamp(),
      lastMutationId: 'client-one',
    });
  });
  const secondWrite = runTransaction(owner, async (transaction) => {
    const snapshot = await transaction.get(first);
    transaction.update(first, {
      revision: snapshot.data().revision + 1,
      updatedAt: serverTimestamp(),
      lastMutationId: 'client-two',
    });
  });
  const concurrentResults = await Promise.allSettled([firstWrite, secondWrite]);
  const fulfilled = concurrentResults.filter(
    (result) => result.status === 'fulfilled',
  ).length;
  const rejected = concurrentResults.filter(
    (result) => result.status === 'rejected',
  ).length;
  if (fulfilled !== 1 || rejected !== 1) {
    throw new Error('exactly one concurrent revision must succeed');
  }
  checks += 2;

  console.log(`Y1_RULES_CHECKS=${checks}`);
} finally {
  await environment.cleanup();
}
