import fs from 'node:fs';
import process from 'node:process';
import {fileURLToPath} from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
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
if (!projectId || !projectId.startsWith('zelia-a2-test-')) {
  throw new Error('GCLOUD_PROJECT must be a dedicated A.2 test project');
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

const entry = (id, overrides = {}) => ({
  schemaVersion: 1,
  ledgerEntryId: id,
  accountScopeId: 'account-a',
  actionType: 'createTask',
  actionDomain: 'task',
  actionOrigin: 'explicitUserRequest',
  riskLevel: 'reversibleLowRisk',
  policyModeObserved: 'normal',
  policyVersionObserved: 1,
  mutationId: `mutation-${id}`,
  targetReference: {
    schemaVersion: 1,
    domain: 'task',
    entityType: 'task',
    entityId: 'task-a',
    operationType: 'createTask',
    revisionBefore: 0,
    revisionAfter: 1,
    tombstoneBefore: false,
    tombstoneAfter: false,
    patchType: 'taskCreate',
    undoStrategy: 'undoCreateTask',
  },
  expectedRevision: 0,
  status: 'authorized',
  outcome: 'unknownResult',
  createdAt: serverTimestamp(),
  authorizedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  undoCapability: {
    type: 'conditionallyReversible',
    strategy: 'undoCreateTask',
    reasonCode: 'undo_revision_required',
    confirmationRequired: true,
    currentRevisionRequired: true,
    domain: 'task',
    riskLevel: 'destructive',
  },
  correlationId: `correlation-${id}`,
  provenance: 'revisioned_sync',
  ledgerRevision: 1,
  lastMutationId: `mutation-${id}`,
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
  const reference = doc(owner, 'users/account-a/actionLedger/ledger-a');

  await succeeds(setDoc(reference, entry('ledger-a')));
  await succeeds(getDoc(reference));
  await fails(setDoc(
    doc(other, 'users/account-a/actionLedger/ledger-other'),
    entry('ledger-other'),
  ));
  await fails(setDoc(
    doc(guest, 'users/account-a/actionLedger/ledger-guest'),
    entry('ledger-guest'),
  ));
  await fails(setDoc(
    doc(owner, 'users/account-a/actionLedger/ledger-scope'),
    entry('ledger-scope', {accountScopeId: 'account-b'}),
  ));
  await fails(setDoc(
    doc(owner, 'users/account-a/actionLedger/ledger-revision'),
    entry('ledger-revision', {ledgerRevision: 2}),
  ));
  await succeeds(updateDoc(reference, {
    status: 'dispatching',
    ledgerRevision: 2,
    lastMutationId: 'ledger-dispatch',
    updatedAt: serverTimestamp(),
  }));
  await fails(updateDoc(reference, {
    status: 'succeeded',
    ledgerRevision: 4,
    lastMutationId: 'ledger-skip',
    updatedAt: serverTimestamp(),
  }));
  await fails(updateDoc(reference, {
    status: 'authorized',
    ledgerRevision: 3,
    lastMutationId: 'ledger-backward',
    updatedAt: serverTimestamp(),
  }));
  await fails(updateDoc(reference, {
    actionType: 'deleteTask',
    status: 'succeeded',
    outcome: 'completed',
    resultRevision: 1,
    ledgerRevision: 3,
    lastMutationId: 'ledger-identity-change',
    updatedAt: serverTimestamp(),
  }));
  await fails(deleteDoc(reference));

  const concurrent = doc(
    owner,
    'users/account-a/actionLedger/ledger-concurrent',
  );
  await succeeds(setDoc(concurrent, entry('ledger-concurrent')));
  const advance = (mutation) => runTransaction(owner, async (transaction) => {
    const snapshot = await transaction.get(concurrent);
    transaction.update(concurrent, {
      status: 'dispatching',
      ledgerRevision: snapshot.data().ledgerRevision + 1,
      lastMutationId: mutation,
      updatedAt: serverTimestamp(),
    });
  });
  const results = await Promise.allSettled([
    advance('client-one'),
    advance('client-two'),
  ]);
  const fulfilled = results.filter((result) => result.status === 'fulfilled');
  const rejected = results.filter((result) => result.status === 'rejected');
  if (fulfilled.length !== 1 || rejected.length !== 1) {
    throw new Error('exactly one concurrent ledger revision must succeed');
  }
  checks += 2;

  console.log(`A2_RULES_CHECKS=${checks}`);
} finally {
  await environment.cleanup();
}
