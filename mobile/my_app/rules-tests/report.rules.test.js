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
      role: 'client',
      verificationStatus: 'pending',
    });
    await setDoc(doc(db, 'users/worker-1'), {
      role: 'worker',
      verificationStatus: 'verified',
    });
    await setDoc(doc(db, 'users/worker-2'), {
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
      status: 'accepted',
      createdAt: Timestamp.fromDate(new Date('2026-10-10T00:00:00Z')),
    });
  });
});

after(async () => {
  await environment.cleanup();
});

function reportData(reporterId, reportedUserId, reportedUserName) {
  return {
    requestId: 'request-1',
    reporterId,
    reportedUserId,
    reportedUserName,
    reason: 'Inappropriate behavior',
    details: 'Test report details.',
    status: 'open',
    createdAt: serverTimestamp(),
  };
}

test('booking client can report the assigned worker', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(
    setDoc(
      doc(client, 'reports/request-1_client-1'),
      reportData('client-1', 'worker-1', 'Worker One'),
    ),
  );
});

test('assigned worker can report the booking client', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    setDoc(
      doc(worker, 'reports/request-1_worker-1'),
      reportData('worker-1', 'client-1', 'Client One'),
    ),
  );
});

test('unrelated worker cannot report the booking client', async () => {
  const worker = environment.authenticatedContext('worker-2').firestore();
  await assertFails(
    setDoc(
      doc(worker, 'reports/request-1_worker-2'),
      reportData('worker-2', 'client-1', 'Client One'),
    ),
  );
});
