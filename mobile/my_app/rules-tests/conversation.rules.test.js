const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  serverTimestamp,
  setDoc,
  writeBatch,
} = require('firebase/firestore');

const projectRoot = path.resolve(__dirname, '..');
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'swiftserve-rules-test',
    firestore: {
      rules: fs.readFileSync(path.join(projectRoot, 'firestore.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, 'service_requests/request-1'), {
      clientId: 'client-1',
      workerId: 'worker-1',
      status: 'accepted',
    });
    await setDoc(doc(database, 'conversations/client-1_worker-1'), {
      requestId: 'request-1',
      participantIds: ['client-1', 'worker-1'],
      clientId: 'client-1',
      clientName: 'Client One',
      workerId: 'worker-1',
      workerName: 'Worker One',
      lastMessage: 'Application accepted',
      updatedAt: new Date('2026-10-15T00:00:00Z'),
    });
    await setDoc(doc(database, 'conversations/request-1'), {
      requestId: 'request-1',
      participantIds: ['client-1', 'worker-1'],
      clientId: 'client-1',
      clientName: 'Client One',
      workerId: 'worker-1',
      workerName: 'Worker One',
      lastMessage: 'Request accepted',
      updatedAt: new Date('2026-10-15T00:00:00Z'),
    });
  });
});

after(async () => {
  await environment.cleanup();
});

function sendMessage(database, conversationId, senderId, recipientId) {
  const conversation = doc(database, `conversations/${conversationId}`);
  const message = doc(
    database,
    `conversations/${conversationId}/messages/message-1`,
  );
  const batch = writeBatch(database);
  batch.set(message, {
    senderId,
    text: 'Hello',
    createdAt: serverTimestamp(),
  });
  batch.update(conversation, {
    lastMessage: 'Hello',
    lastSenderId: senderId,
    unreadFor: [recipientId],
    hiddenFor: [],
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

test('worker can send to the client in a pair conversation', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    sendMessage(worker, 'client-1_worker-1', 'worker-1', 'client-1'),
  );
});

test('worker can send in an existing legacy booking conversation', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    sendMessage(worker, 'request-1', 'worker-1', 'client-1'),
  );
});

test('an outsider cannot send to a conversation', async () => {
  const outsider = environment.authenticatedContext('outsider').firestore();
  await assertFails(
    sendMessage(outsider, 'client-1_worker-1', 'outsider', 'client-1'),
  );
});

test('a blocked participant cannot send a message', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'user_blocks/client-1_worker-1'), {
      blockerId: 'client-1',
      blockedId: 'worker-1',
      conversationId: 'client-1_worker-1',
      createdAt: new Date('2026-10-15T00:00:00Z'),
    });
  });
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(
    sendMessage(worker, 'client-1_worker-1', 'worker-1', 'client-1'),
  );
});
