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
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
  Timestamp,
} = require('firebase/firestore');

const projectRoot = path.resolve(__dirname, '..');
let environment;

const requestData = {
  clientId: 'client-1',
  clientName: 'Client One',
  title: 'Repair a kitchen sink',
  category: 'Repairs',
  budget: 500,
  schedule: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
  scheduleFrom: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
  scheduleTo: Timestamp.fromDate(new Date('2026-10-21T00:00:00Z')),
  location: 'Malolos',
  description: 'Fix the leaking pipe under the kitchen sink.',
  status: 'pending',
  createdAt: Timestamp.fromDate(new Date('2026-10-10T00:00:00Z')),
};

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
    await setDoc(doc(db, 'users/client-2'), {
      role: 'client',
      verificationStatus: 'pending',
    });
    await setDoc(doc(db, 'users/worker-1'), {
      role: 'worker',
      verificationStatus: 'verified',
    });
    await setDoc(doc(db, 'users/worker-2'), {
      role: 'worker',
      verificationStatus: 'pending',
    });
    await setDoc(doc(db, 'service_requests/request-1'), requestData);
  });
});

after(async () => {
  await environment.cleanup();
});

test('only a verified worker can create their own pending application', async () => {
  const verified = environment.authenticatedContext('worker-1').firestore();
  const unverified = environment.authenticatedContext('worker-2').firestore();

  await assertSucceeds(
    setDoc(
      doc(verified, 'service_requests/request-1/applications/worker-1'),
      {
        requestId: 'request-1',
        clientId: 'client-1',
        workerId: 'worker-1',
        workerName: 'Verified Worker',
        status: 'pending',
        appliedAt: serverTimestamp(),
      },
    ),
  );
  await assertFails(
    setDoc(
      doc(unverified, 'service_requests/request-1/applications/worker-2'),
      {
        requestId: 'request-1',
        clientId: 'client-1',
        workerId: 'worker-2',
        workerName: 'Unverified Worker',
        status: 'pending',
        appliedAt: serverTimestamp(),
      },
    ),
  );
});

test('worker cannot assign the request to themselves', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(
    updateDoc(doc(worker, 'service_requests/request-1'), {
      status: 'accepted',
      workerId: 'worker-1',
      workerName: 'Verified Worker',
      acceptedAt: serverTimestamp(),
    }),
  );
});

test('request owner can atomically select an existing applicant', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(
        context.firestore(),
        'service_requests/request-1/applications/worker-1',
      ),
      {
        requestId: 'request-1',
        clientId: 'client-1',
        workerId: 'worker-1',
        workerName: 'Verified Worker',
        status: 'pending',
        appliedAt: Timestamp.fromDate(new Date('2026-10-10T01:00:00Z')),
      },
    );
  });

  const client = environment.authenticatedContext('client-1').firestore();
  const batch = writeBatch(client);
  batch.update(doc(client, 'service_requests/request-1'), {
    status: 'accepted',
    workerId: 'worker-1',
    workerName: 'Verified Worker',
    acceptedAt: serverTimestamp(),
  });
  batch.update(
    doc(client, 'service_requests/request-1/applications/worker-1'),
    { status: 'accepted', reviewedAt: serverTimestamp() },
  );
  batch.set(doc(client, 'conversations/request-1'), {
    requestId: 'request-1',
    participantIds: ['client-1', 'worker-1'],
    clientId: 'client-1',
    clientName: 'Client One',
    workerId: 'worker-1',
    workerName: 'Verified Worker',
    lastMessage: 'Application accepted',
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(client, 'notifications/accept-notification'), {
    recipientId: 'worker-1',
    senderId: 'client-1',
    requestId: 'request-1',
    title: 'Application accepted',
    body: 'Client One selected you.',
    read: false,
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());

  const updated = await getDoc(doc(client, 'service_requests/request-1'));
  if (updated.data().workerId !== 'worker-1') {
    throw new Error('Selected worker was not stored.');
  }
});

test('another client cannot review applications or select a worker', async () => {
  const otherClient = environment.authenticatedContext('client-2').firestore();
  await assertFails(
    getDoc(
      doc(
        otherClient,
        'service_requests/request-1/applications/worker-1',
      ),
    ),
  );
  await assertFails(
    updateDoc(doc(otherClient, 'service_requests/request-1'), {
      status: 'accepted',
      workerId: 'worker-1',
      workerName: 'Verified Worker',
      acceptedAt: serverTimestamp(),
    }),
  );
});
