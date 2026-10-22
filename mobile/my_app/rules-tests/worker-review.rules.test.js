const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, serverTimestamp, setDoc, Timestamp } = require('firebase/firestore');

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
    await setDoc(doc(db, 'users/client-1'), {
      fullName: 'Client One',
      role: 'client',
      verificationStatus: 'pending',
    });
    await setDoc(doc(db, 'users/client-2'), {
      fullName: 'Client Two',
      role: 'client',
      verificationStatus: 'pending',
    });
    await setDoc(doc(db, 'users/worker-1'), {
      fullName: 'Worker One',
      role: 'worker',
      verificationStatus: 'verified',
    });
    await setDoc(doc(db, 'service_requests/request-1'), {
      clientId: 'client-1',
      clientName: 'Client One',
      workerId: 'worker-1',
      workerName: 'Worker One',
      title: 'House cleaning',
      category: 'Cleaning',
      budget: 500,
      schedule: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
      location: 'Malolos',
      description: 'Clean the house.',
      status: 'completed',
      createdAt: Timestamp.fromDate(new Date('2026-10-10T00:00:00Z')),
    });
  });
});

after(async () => {
  await environment.cleanup();
});

function reviewData(clientId = 'client-1', clientName = 'Client One') {
  return {
    requestId: 'request-1',
    clientId,
    clientName,
    workerId: 'worker-1',
    workerName: 'Worker One',
    rating: 5,
    comment: 'Excellent work and communication.',
    createdAt: serverTimestamp(),
  };
}

test('booking client can rate the assigned worker after completion', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(
    setDoc(doc(client, 'reviews/request-1'), reviewData()),
  );
});

test('unrelated client cannot rate the assigned worker', async () => {
  const client = environment.authenticatedContext('client-2').firestore();
  await assertFails(
    setDoc(
      doc(client, 'reviews/request-1'),
      reviewData('client-2', 'Client Two'),
    ),
  );
});

test('client cannot spoof the reviewer name', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertFails(
    setDoc(
      doc(client, 'reviews/request-1'),
      reviewData('client-1', 'Fake Name'),
    ),
  );
});
