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
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const hostValue = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (!hostValue) throw new Error('FIRESTORE_EMULATOR_HOST is required');
if (!projectId?.startsWith('zelia-s02-test-')) {
  throw new Error('GCLOUD_PROJECT must be a dedicated S0.2 test project');
}
const [host, portValue] = hostValue.split(':');
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

const message = (overrides = {}) => ({
  role: 'user',
  text: 'synthetic bounded content',
  createdAt: serverTimestamp(),
  ...overrides,
});
const conversation = (overrides = {}) => ({
  updatedAt: serverTimestamp(),
  lastMessage: 'synthetic bounded content',
  ...overrides,
});
const fingerprint = 'a'.repeat(64);
const replacementAction = (overrides = {}) => ({
  schemaVersion: 1,
  actionId: fingerprint,
  actionType: 'memoryReplacementConfirmation',
  accountScopeFingerprint: 'b'.repeat(64),
  existingMemoryId: 'existing-memory',
  proposedMemoryId: 'proposed-memory',
  canonicalKey: 'v1|synthetic',
  expectedExistingRevision: 1,
  expectedProposedRevision: 1,
  contradictionId: 'c'.repeat(64),
  reasonCode: 'directContradiction',
  state: 'pending',
  logicalRequestFingerprint: 'd'.repeat(64),
  createdAt: '2026-07-27T10:00:00.000Z',
  updatedAt: '2026-07-27T10:00:00.000Z',
  contradictionCandidate: {schemaVersion: 1},
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
  const userA = environment.authenticatedContext('user-a').firestore();
  const userB = environment.authenticatedContext('user-b').firestore();
  const guest = environment.unauthenticatedContext().firestore();
  const conversationA = doc(userA, 'users/user-a/conversations/conversation-a');
  const messageA = doc(
    userA,
    'users/user-a/conversations/conversation-a/messages/message-a',
  );

  await succeeds(setDoc(conversationA, conversation()));
  await succeeds(setDoc(messageA, message()));
  await succeeds(getDoc(conversationA));
  await succeeds(getDoc(messageA));
  await succeeds(getDocs(collection(
    userA,
    'users/user-a/conversations/conversation-a/messages',
  )));
  await fails(getDoc(doc(
    userB,
    'users/user-a/conversations/conversation-a',
  )));
  await fails(setDoc(
    doc(userB, 'users/user-a/conversations/foreign'),
    conversation(),
  ));
  await fails(getDoc(doc(
    guest,
    'users/user-a/conversations/conversation-a',
  )));
  await fails(setDoc(
    doc(guest, 'users/user-a/conversations/guest'),
    conversation(),
  ));
  await fails(setDoc(
    doc(userA, 'users/user-a/conversations/extra'),
    conversation({accountScopeId: 'user-b'}),
  ));
  await fails(setDoc(
    doc(
      userA,
      'users/user-a/conversations/conversation-a/messages/invalid-role',
    ),
    message({role: 'system'}),
  ));
  await fails(setDoc(
    doc(
      userA,
      'users/user-a/conversations/conversation-a/messages/oversized',
    ),
    message({text: 'x'.repeat(4001)}),
  ));
  await fails(updateDoc(messageA, {text: 'mutation refused'}));
  await fails(deleteDoc(messageA));
  await succeeds(deleteDoc(conversationA));

  const replacementRef = doc(
    userA,
    `users/user-a/memoryReplacementActions/${fingerprint}`,
  );
  await succeeds(setDoc(replacementRef, replacementAction()));
  await succeeds(getDoc(replacementRef));
  await succeeds(updateDoc(replacementRef, {
    state: 'declined',
    updatedAt: '2026-07-27T10:01:00.000Z',
  }));
  await fails(updateDoc(replacementRef, {
    existingMemoryId: 'hijacked-memory',
    updatedAt: '2026-07-27T10:02:00.000Z',
  }));
  await fails(setDoc(
    doc(userB, `users/user-a/memoryReplacementActions/${'e'.repeat(64)}`),
    replacementAction({actionId: 'e'.repeat(64)}),
  ));
  await fails(deleteDoc(replacementRef));

  for (const path of [
    'users/user-a/unknown/document',
    'users/user-a/unknown/document/nested/value',
    '__server_ai_chat_quota/user-a',
    'metrics/private',
  ]) {
    await fails(getDoc(doc(userA, path)));
    await fails(setDoc(doc(userA, path), {value: true}));
  }

  await fails(setDoc(doc(userA, 'users/user-a'), {admin: true}));
  await fails(setDoc(doc(userA, 'users/user-b'), {value: true}));

  console.log(`S02_RULES_CHECKS=${checks}`);
} finally {
  await environment.cleanup();
}
