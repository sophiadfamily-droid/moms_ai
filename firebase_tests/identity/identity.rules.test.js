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
  deleteField,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  runTransaction,
  setDoc,
  updateDoc,
  writeBatch,
  where,
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

const identity = (id, overrides = {}) => ({
  id,
  type: 'person',
  canonicalLabel: 'Person A',
  normalizedLabel: 'person a',
  aliasComparisonKeys: [],
  aliases: [],
  status: 'active',
  source: {type: 'user'},
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
  metadata: {},
  schemaVersion: 1,
  revision: 1,
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
  const identities = 'users/account-a/identities';

  await succeeds(setDoc(doc(owner, identities, 'valid'), identity('valid')));
  await succeeds(getDoc(doc(owner, identities, 'valid')));
  await succeeds(getDocs(query(
    collection(owner, identities),
    where('normalizedLabel', '==', 'person a'),
    limit(20),
  )));
  await succeeds(getDocs(query(
    collection(owner, identities),
    where('aliasComparisonKeys', 'array-contains', 'person alias'),
    limit(20),
  )));

  await succeeds(setDoc(
    doc(owner, 'users/account-a/events/event-a'),
    {title: 'Unrelated collection remains available', eventRevision: 1},
  ));
  await fails(setDoc(
    doc(other, 'users/account-a/events/event-b'),
    {title: 'Cross-account write remains denied', eventRevision: 1},
  ));
  const participantIdentity = {
    entityId: 'valid',
    entityType: 'person',
    schemaVersion: 1,
    role: 'participant',
    accountScopeId: 'account-a',
  };
  await succeeds(setDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {title: 'Event', eventRevision: 1, participantIdentity, participantIdentityRevision: 1},
  ));
  await succeeds(getDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
  ));
  await succeeds(updateDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {title: 'Updated event', eventRevision: 2},
  ));
  await fails(updateDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {participantIdentity: {...participantIdentity, role: 'owner'}, eventRevision: 3},
  ));
  await fails(updateDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {participantIdentity: deleteField(), eventRevision: 3},
  ));
  await succeeds(updateDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {
      participantIdentity: deleteField(),
      participantIdentityRevision: 2,
      eventRevision: 3,
    },
  ));
  await succeeds(updateDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {title: 'Updated after explicit removal', eventRevision: 4},
  ));
  await fails(updateDoc(
    doc(owner, 'users/account-a/events/event-with-identity'),
    {participantIdentityRevision: deleteField(), eventRevision: 5},
  ));
  await succeeds(setDoc(
    doc(owner, 'users/account-a/events/event-replacement'),
    {title: 'Event', eventRevision: 1, participantIdentity, participantIdentityRevision: 1},
  ));
  await succeeds(updateDoc(
    doc(owner, 'users/account-a/events/event-replacement'),
    {
      participantIdentity: {...participantIdentity, entityId: 'replacement'},
      participantIdentityRevision: 2,
      eventRevision: 2,
    },
  ));
  await fails(updateDoc(
    doc(owner, 'users/account-a/events/event-replacement'),
    {
      participantIdentity: {
        ...participantIdentity,
        entityId: 'foreign',
        accountScopeId: 'account-b',
      },
      participantIdentityRevision: 3,
      eventRevision: 3,
    },
  ));
  await fails(setDoc(
    doc(owner, 'users/account-a/events/event-invalid-role'),
    {title: 'Event', eventRevision: 1, participantIdentity: {...participantIdentity, role: 'owner'}},
  ));
  await fails(setDoc(
    doc(owner, 'users/account-a/events/event-extra-link-field'),
    {title: 'Event', eventRevision: 1, participantIdentity: {...participantIdentity, label: 'Private'}},
  ));
  await fails(setDoc(
    doc(owner, 'users/account-a/events/event-empty-identity'),
    {title: 'Event', eventRevision: 1, participantIdentity: {...participantIdentity, entityId: ''}},
  ));
  await fails(setDoc(
    doc(owner, 'users/account-a/events/event-long-identity'),
    {title: 'Event', eventRevision: 1, participantIdentity: {...participantIdentity, entityId: 'a'.repeat(201)}},
  ));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users/account-b/identities/foreign'),
      identity('foreign'),
    );
  });
  await fails(setDoc(
    doc(owner, 'users/account-a/events/event-foreign-identity'),
    {
      title: 'Event',
      eventRevision: 1,
      participantIdentity: {
        ...participantIdentity,
        entityId: 'foreign',
        accountScopeId: 'account-b',
      },
    },
  ));
  await fails(setDoc(
    doc(guest, 'users/account-a/events/event-guest'),
    {title: 'Event', eventRevision: 1, participantIdentity},
  ));
  await succeeds(updateDoc(
    doc(owner, 'users/account-a/events/event-a'),
    {title: 'Updated modern event', eventRevision: 2},
  ));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users/account-a/events/event-historical'),
      {title: 'Historical event'},
    );
  });
  await succeeds(updateDoc(
    doc(owner, 'users/account-a/events/event-historical'),
    {title: 'Historical event remains editable', eventRevision: 1},
  ));
  await succeeds(setDoc(
    doc(owner, 'users/account-a/events/event-batch-1'),
    {title: 'Batch 1', eventRevision: 1, participantIdentity, participantIdentityRevision: 1},
  ));
  await succeeds(setDoc(
    doc(owner, 'users/account-a/events/event-batch-2'),
    {title: 'Batch 2', eventRevision: 1, participantIdentity, participantIdentityRevision: 1},
  ));
  const eventBatch = writeBatch(owner);
  eventBatch.update(
    doc(owner, 'users/account-a/events/event-batch-1'),
    {title: 'Batch 1 updated', eventRevision: 2},
  );
  eventBatch.update(
    doc(owner, 'users/account-a/events/event-batch-2'),
    {title: 'Batch 2 updated', eventRevision: 2},
  );
  await succeeds(eventBatch.commit());
  await fails(setDoc(
    doc(owner, 'users/account-a/events/event-revision-zero'),
    {title: 'Invalid revision', eventRevision: 0},
  ));
  const revisionedEvent = doc(owner, 'users/account-a/events/event-revisioned');
  await succeeds(setDoc(revisionedEvent, {title: 'Revisioned', eventRevision: 1}));
  await fails(updateDoc(revisionedEvent, {title: 'Same', eventRevision: 1}));
  await fails(updateDoc(revisionedEvent, {title: 'Jump', eventRevision: 3}));
  await fails(updateDoc(revisionedEvent, {title: 'Missing', eventRevision: deleteField()}));
  await succeeds(updateDoc(revisionedEvent, {title: 'Next', eventRevision: 2}));
  const mutateEventAtRevisionOne = (title) => runTransaction(
    owner,
    async (transaction) => {
      const snapshot = await transaction.get(revisionedEvent);
      if (snapshot.data().eventRevision !== 2) {
        throw new Error('event_revision_conflict');
      }
      transaction.update(revisionedEvent, {title, eventRevision: 3});
    },
  );
  const eventConcurrentResults = await Promise.allSettled([
    mutateEventAtRevisionOne('Concurrent A'),
    mutateEventAtRevisionOne('Concurrent B'),
  ]);
  if (eventConcurrentResults.filter((result) => result.status === 'fulfilled').length !== 1 ||
      eventConcurrentResults.filter((result) => result.status === 'rejected').length !== 1) {
    throw new Error('Concurrent Event revision guard failed');
  }
  checks++;
  await succeeds(setDoc(
    doc(owner, 'users/account-a/events/event-delete'),
    {title: 'Delete', eventRevision: 1, participantIdentity, participantIdentityRevision: 1},
  ));
  await fails(deleteDoc(
    doc(other, 'users/account-a/events/event-delete'),
  ));
  await fails(deleteDoc(
    doc(guest, 'users/account-a/events/event-delete'),
  ));
  await succeeds(deleteDoc(
    doc(owner, 'users/account-a/events/event-delete'),
  ));
  await succeeds(getDoc(doc(owner, identities, 'valid')));

  await fails(setDoc(doc(guest, identities, 'guest'), identity('guest')));
  await fails(setDoc(doc(other, identities, 'other'), identity('other')));
  await fails(setDoc(doc(owner, identities, 'path-id'), identity('field-id')));
  await fails(setDoc(
    doc(owner, identities, 'revision-two'),
    identity('revision-two', {revision: 2}),
  ));
  await fails(setDoc(
    doc(owner, identities, 'merged'),
    identity('merged', {status: 'merged'}),
  ));
  await fails(setDoc(
    doc(owner, identities, 'deleted'),
    identity('deleted', {status: 'deleted'}),
  ));
  await fails(setDoc(
    doc(owner, identities, 'merge-target'),
    {...identity('merge-target'), mergedIntoEntityId: 'target'},
  ));
  await fails(setDoc(
    doc(owner, identities, 'unknown-field'),
    {...identity('unknown-field'), unexpected: true},
  ));
  await fails(setDoc(
    doc(owner, identities, 'unknown-type'),
    identity('unknown-type', {type: 'unknown'}),
  ));
  await fails(setDoc(
    doc(owner, identities, 'future-version'),
    identity('future-version', {schemaVersion: 2}),
  ));
  await fails(setDoc(
    doc(owner, identities, 'malformed'),
    {id: 'malformed', revision: 1},
  ));

  await succeeds(updateDoc(doc(owner, identities, 'valid'), {
    canonicalLabel: 'Person B',
    normalizedLabel: 'person b',
    updatedAt: '2026-01-01T00:01:00.000Z',
    revision: 2,
  }));
  await succeeds(updateDoc(doc(owner, identities, 'valid'), {
    aliases: [{value: 'Person Alias'}],
    aliasComparisonKeys: ['person alias'],
    updatedAt: '2026-01-01T00:02:00.000Z',
    revision: 3,
  }));

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), identities, 'update-checks'),
      identity('update-checks'),
    );
  });
  const updateChecks = doc(owner, identities, 'update-checks');
  await fails(updateDoc(updateChecks, {
    updatedAt: '2026-01-01T00:01:00.000Z', revision: 1,
  }));
  await fails(updateDoc(updateChecks, {
    updatedAt: '2026-01-01T00:01:00.000Z', revision: 3,
  }));
  await fails(updateDoc(updateChecks, {
    updatedAt: '2026-01-01T00:01:00.000Z', revision: 0,
  }));
  await fails(updateDoc(updateChecks, {
    id: 'changed', updatedAt: '2026-01-01T00:01:00.000Z', revision: 2,
  }));
  await fails(updateDoc(updateChecks, {
    createdAt: '2025-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:01:00.000Z',
    revision: 2,
  }));
  await fails(updateDoc(updateChecks, {
    type: 'place', updatedAt: '2026-01-01T00:01:00.000Z', revision: 2,
  }));
  await fails(updateDoc(updateChecks, {
    schemaVersion: 2,
    updatedAt: '2026-01-01T00:01:00.000Z',
    revision: 2,
  }));
  await fails(updateDoc(updateChecks, {
    status: 'merged', updatedAt: '2026-01-01T00:01:00.000Z', revision: 2,
  }));
  await fails(updateDoc(updateChecks, {
    mergedIntoEntityId: 'target',
    updatedAt: '2026-01-01T00:01:00.000Z',
    revision: 2,
  }));
  await fails(updateDoc(doc(other, identities, 'update-checks'), {
    updatedAt: '2026-01-01T00:01:00.000Z', revision: 2,
  }));
  await fails(updateDoc(doc(guest, identities, 'update-checks'), {
    updatedAt: '2026-01-01T00:01:00.000Z', revision: 2,
  }));

  await succeeds(updateDoc(updateChecks, {
    status: 'deleted', updatedAt: '2026-01-01T00:03:00.000Z', revision: 2,
  }));
  await succeeds(getDoc(updateChecks));
  await fails(deleteDoc(updateChecks));
  await fails(deleteDoc(doc(other, identities, 'update-checks')));
  await fails(deleteDoc(doc(guest, identities, 'update-checks')));

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), identities, 'concurrent'),
      identity('concurrent'),
    );
  });
  const concurrent = doc(owner, identities, 'concurrent');
  const updateWithExpectedRevision = (label) => runTransaction(
    owner,
    async (transaction) => {
      const expectedRevision = 1;
      const nextRevision = 2;
      const updatedAt = '2026-01-01T00:04:00.000Z';
      const normalizedLabel = label.toLowerCase();
      const snapshot = await transaction.get(concurrent);
      if (snapshot.data().revision !== expectedRevision) {
        throw new Error('revision_conflict');
      }
      transaction.update(concurrent, {
        canonicalLabel: label,
        normalizedLabel,
        updatedAt,
        revision: nextRevision,
      });
    },
  );
  const concurrentResults = await Promise.allSettled([
    updateWithExpectedRevision('Person C'),
    updateWithExpectedRevision('Person D'),
  ]);
  if (concurrentResults.filter((result) => result.status === 'fulfilled').length !== 1 ||
      concurrentResults.filter((result) => result.status === 'rejected').length !== 1) {
    throw new Error('Concurrent revision guard failed');
  }
  checks++;

  process.stdout.write(`${checks} Identity Firestore checks passed\n`);
} finally {
  await environment.cleanup();
}
