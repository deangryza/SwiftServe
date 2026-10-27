const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { deleteDoc, doc, setDoc } = require('firebase/firestore');

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
    await setDoc(doc(context.firestore(), 'notifications/notification-1'), {
      recipientId: 'client-1',
      senderId: 'worker-1',
      requestId: 'request-1',
      title: 'Booking update',
      body: 'Your booking has changed.',
      read: false,
      createdAt: new Date('2026-10-22T00:00:00Z'),
    });
  });
});

after(async () => {
  await environment.cleanup();
});

test('notification recipient can delete their notification', async () => {
  const database = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(
    deleteDoc(doc(database, 'notifications/notification-1')),
  );
});

test('notification sender cannot delete the recipient notification', async () => {
  const database = environment.authenticatedContext('worker-1').firestore();
  await assertFails(deleteDoc(doc(database, 'notifications/notification-1')));
});

test('worker recipient can delete their own notification without being verified', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users/worker-1'), {
      role: 'worker',
      verificationStatus: 'pending',
    });
    await setDoc(doc(context.firestore(), 'notifications/worker-notification'), {
      recipientId: 'worker-1',
      senderId: 'client-1',
      requestId: 'request-1',
      title: 'Booking update',
      body: 'Your booking has changed.',
      read: false,
      createdAt: new Date('2026-10-22T00:00:00Z'),
    });
  });
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(deleteDoc(doc(worker, 'notifications/worker-notification')));
});

test('unrelated user cannot delete another user notification', async () => {
  const database = environment.authenticatedContext('other-user').firestore();
  await assertFails(deleteDoc(doc(database, 'notifications/notification-1')));
});
