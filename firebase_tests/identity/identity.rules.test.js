import fs from 'node:fs';
import process from 'node:process';
import {fileURLToPath} from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  limit,
} from 'firebase/firestore';

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (!emulatorHost) throw new Error('FIRESTORE_EMULATOR_HOST is required');
if (!projectId || !projectId.startsWith('zelia-identity-test-')) {
  throw new Error('GCLOUD_PROJECT must be a dedicated Identity test project');
}
if (projectId === 'zelia-ai-app') {
  throw new Error('Production Firebase project is forbidden');
}

const [host, portValue] = emulatorHost.split(':');
const port = Number(portValue);
if (!host || !Number.isInteger(port)) {
  throw new Error('FIRESTORE_EMULATOR_HOST must contain host:port');
}

const environment = await initializeTestEnvironment({
  projectId,
  firestore: {
    host,
    port,
    rules: fs.readFileSync(
      fileURLToPath(new URL('../../firestore.rules', import.meta.url)),
      'utf8',
    ),
  },
});
const identity = {
  id: 'entity-1',
  type: 'person',
  canonicalLabel: 'Person A',
  normalizedLabel: 'person a',
  aliasComparisonKeys: ['person a'],
  aliases: [],
  status: 'active',
  source: {type: 'user'},
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
  metadata: {},
  schemaVersion: 1,
};

try {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users/account-a/identities/entity-1'),
      identity,
    );
  });
  const owner = environment.authenticatedContext('account-a').firestore();
  const other = environment.authenticatedContext('account-b').firestore();
  const guest = environment.unauthenticatedContext().firestore();
  const identityPath = 'users/account-a/identities/entity-1';

  await assertSucceeds(getDoc(doc(owner, identityPath)));
  await assertSucceeds(
    getDocs(query(
      collection(owner, 'users/account-a/identities'),
      where('normalizedLabel', '==', 'person a'),
      where('type', '==', 'person'),
      where('status', '==', 'active'),
      limit(21),
    )),
  );
  await assertSucceeds(
    getDocs(query(
      collection(owner, 'users/account-a/identities'),
      where('aliasComparisonKeys', 'array-contains', 'person a'),
      where('type', '==', 'person'),
      where('status', '==', 'active'),
      limit(21),
    )),
  );
  await assertFails(getDoc(doc(other, identityPath)));
  await assertFails(getDoc(doc(guest, identityPath)));
  await assertFails(
    setDoc(doc(owner, 'users/account-a/identities/new'), identity),
  );
  await assertFails(updateDoc(doc(owner, identityPath), {status: 'inactive'}));
  await assertFails(deleteDoc(doc(owner, identityPath)));
  await assertSucceeds(
    setDoc(doc(owner, 'users/account-a/events/event-1'), {title: 'Activity A'}),
  );
  await assertFails(
    setDoc(doc(other, 'users/account-a/events/event-2'), {title: 'Activity B'}),
  );
  process.stdout.write('10 Identity Firestore rules checks passed\n');
} finally {
  await environment.cleanup();
}
