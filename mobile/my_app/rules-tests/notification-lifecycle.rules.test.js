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
    const db = context.firestore();
    // Accepted directly by worker-1 (no application document).
    await setDoc(doc(db, 'service_requests/direct'), {
      clientId: 'client-1', workerId: 'worker-1', status: 'ongoing',
    });
    // Accepted from applications: worker-1 chosen, worker-2 not selected.
    await setDoc(doc(db, 'service_requests/applied'), {
      clientId: 'client-1', workerId: 'worker-1', status: 'accepted',
    });
    await setDoc(doc(db, 'service_requests/applied/applications/worker-1'), {
      workerId: 'worker-1', status: 'accepted',
    });
    await setDoc(doc(db, 'service_requests/applied/applications/worker-2'), {
      workerId: 'worker-2', status: 'rejected',
    });
  });
});

after(async () => {
  await environment.cleanup();
});

function notify(uid, recipientId, requestId, type, id = 'n1') {
  const db = environment.authenticatedContext(uid).firestore();
  return setDoc(doc(db, `notifications/${id}`), {
    recipientId,
    senderId: uid,
    requestId,
    type,
    title: 'Update',
    body: 'Something changed.',
    read: false,
    createdAt: serverTimestamp(),
  });
}

for (const type of ['jobStarted', 'jobCompleted', 'errandStageUpdated']) {
  test(`assigned worker notifies the client: ${type}`, async () => {
    await assertSucceeds(notify('worker-1', 'client-1', 'direct', type));
    await assertSucceeds(notify('worker-1', 'client-1', 'applied', type, 'n2'));
  });
}

test('client notifies the assigned worker of a cancellation', async () => {
  await assertSucceeds(notify('client-1', 'worker-1', 'direct', 'bookingCancelled'));
});

test('client notifies an applicant who was not selected', async () => {
  await assertSucceeds(notify('client-1', 'worker-2', 'applied', 'applicationRejected'));
});

test('client cannot notify someone who never applied', async () => {
  await assertFails(notify('client-1', 'stranger', 'applied', 'applicationRejected'));
});

test('a worker who is not assigned cannot notify the client', async () => {
  await assertFails(notify('worker-2', 'client-1', 'direct', 'jobStarted'));
});

test('a stranger cannot send lifecycle notifications', async () => {
  await assertFails(notify('stranger', 'client-1', 'direct', 'jobCompleted'));
  await assertFails(notify('stranger', 'worker-1', 'direct', 'bookingCancelled', 'n2'));
});

test('unknown notification types are rejected', async () => {
  await assertFails(notify('worker-1', 'client-1', 'direct', 'somethingElse'));
});
