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
    await setDoc(doc(db, 'users/worker-1'), {
      fullName: 'Worker One',
      role: 'worker',
      verificationStatus: 'verified',
    });
    await setDoc(doc(db, 'users/worker-2'), {
      fullName: 'Worker Two',
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

function reviewData(workerId = 'worker-1', workerName = 'Worker One') {
  return {
    requestId: 'request-1',
    workerId,
    workerName,
    clientId: 'client-1',
    clientName: 'Client One',
    rating: 5,
    comment: 'Clear instructions and prompt communication.',
    createdAt: serverTimestamp(),
  };
}

test('assigned worker can rate the client after completion', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    setDoc(doc(worker, 'client_reviews/request-1'), reviewData()),
  );
});

test('booking client cannot rate themselves', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertFails(
    setDoc(doc(client, 'client_reviews/request-1'), reviewData('client-1', 'Client One')),
  );
});

test('unrelated worker cannot rate the client', async () => {
  const worker = environment.authenticatedContext('worker-2').firestore();
  await assertFails(
    setDoc(doc(worker, 'client_reviews/request-1'), reviewData('worker-2', 'Worker Two')),
  );
});
test('worker cannot spoof the reviewer name', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(
    setDoc(
      doc(worker, 'client_reviews/request-1'),
      reviewData('worker-1', 'Fake Name'),
    ),
  );
});

// Mirrors the quick star rating in client_request_details_screen.dart.
function workerReviewData(overrides = {}) {
  return {
    requestId: 'request-1',
    clientId: 'client-1',
    workerId: 'worker-1',
    workerName: 'Worker One',
    rating: 4,
    comment: '',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

test('booking client can rate the worker after completion', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(
    setDoc(doc(client, 'reviews/request-1'), workerReviewData()),
  );
});

test('worker reviews need the worker name and comment fields', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  const { workerName, comment, ...incomplete } = workerReviewData();
  await assertFails(setDoc(doc(client, 'reviews/request-1'), incomplete));
});
