const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteDoc,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
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

function sendMessage(
  database,
  conversationId,
  senderId,
  recipientId,
  messageId = 'message-1',
  text = 'Hello',
) {
  const conversation = doc(database, `conversations/${conversationId}`);
  const message = doc(
    database,
    `conversations/${conversationId}/messages/${messageId}`,
  );
  const batch = writeBatch(database);
  batch.set(message, {
    senderId,
    text,
    createdAt: serverTimestamp(),
  });
  batch.update(conversation, {
    lastMessage: text,
    lastMessageId: messageId,
    lastSenderId: senderId,
    unreadFor: [recipientId],
    hiddenFor: [],
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

function resetConversation(database, requestId) {
  return setDoc(doc(database, 'conversations/client-1_worker-1'), {
    requestId,
    participantIds: ['client-1', 'worker-1'],
    clientId: 'client-1',
    clientName: 'Client One',
    workerId: 'worker-1',
    workerName: 'Worker One',
    lastMessage: 'Application accepted',
    updatedAt: serverTimestamp(),
  });
}

test('worker can send to the client in a pair conversation', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    sendMessage(worker, 'client-1_worker-1', 'worker-1', 'client-1'),
  );
});

test('the same sender can send consecutive messages without waiting for a reply', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    sendMessage(
      worker,
      'client-1_worker-1',
      'worker-1',
      'client-1',
      'message-1',
      'Hello',
    ),
  );
  await assertSucceeds(
    sendMessage(
      worker,
      'client-1_worker-1',
      'worker-1',
      'client-1',
      'message-2',
      'Hello',
    ),
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

test('the blocker also cannot send while the block is active', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'user_blocks/worker-1_client-1'), {
      blockerId: 'worker-1',
      blockedId: 'client-1',
      conversationId: 'client-1_worker-1',
      createdAt: new Date('2026-10-15T00:00:00Z'),
    });
  });
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(
    sendMessage(worker, 'client-1_worker-1', 'worker-1', 'client-1'),
  );
});

test('conversation metadata cannot claim a message that was not written', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(
    updateDoc(doc(worker, 'conversations/client-1_worker-1'), {
      lastMessage: 'Bypass attempt',
      lastMessageId: 'missing-message',
      lastSenderId: 'worker-1',
      unreadFor: ['client-1'],
      updatedAt: serverTimestamp(),
    }),
  );
});

test('only the blocker can remove their block', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  const worker = environment.authenticatedContext('worker-1').firestore();
  const blockPath = 'user_blocks/client-1_worker-1';

  await assertSucceeds(
    setDoc(doc(client, blockPath), {
      blockerId: 'client-1',
      blockedId: 'worker-1',
      conversationId: 'client-1_worker-1',
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(doc(worker, blockPath)));
  await assertSucceeds(deleteDoc(doc(client, blockPath)));
});

test('an accepted repeat booking can reset the pair conversation', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'service_requests/request-2'), {
      clientId: 'client-1',
      workerId: 'worker-1',
      status: 'accepted',
    });
  });
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(resetConversation(client, 'request-2'));
});

test('an active block prevents a repeat-booking conversation reset', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, 'service_requests/request-2'), {
      clientId: 'client-1',
      workerId: 'worker-1',
      status: 'accepted',
    });
    await setDoc(doc(database, 'user_blocks/client-1_worker-1'), {
      blockerId: 'client-1',
      blockedId: 'worker-1',
      conversationId: 'client-1_worker-1',
      createdAt: new Date('2026-10-15T00:00:00Z'),
    });
  });
  const client = environment.authenticatedContext('client-1').firestore();
  await assertFails(resetConversation(client, 'request-2'));
});
