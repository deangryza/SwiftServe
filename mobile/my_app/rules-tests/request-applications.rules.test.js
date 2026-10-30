const fs = require('node:fs');
const assert = require('node:assert/strict');
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
  getDocs,
  collection,
  query,
  where,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
  runTransaction,
  Timestamp,
  GeoPoint,
} = require('firebase/firestore');

const projectRoot = path.resolve(__dirname, '..');
let environment;

const requestData = {
  clientId: 'client-1',
  clientName: 'Client One',
  title: 'Repair a kitchen sink',
  category: 'Repairs',
  budget: 500,
  // Authorization tests need a future start: an overdue fixture now correctly
  // fails independently of the role/ownership condition under test.
  schedule: Timestamp.fromMillis(Date.now() + 86400000),
  scheduleFrom: Timestamp.fromMillis(Date.now() + 86400000),
  scheduleTo: Timestamp.fromMillis(Date.now() + 172800000),
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

test('deadline: overdue pending job rejects atomic application and notification', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const past = Timestamp.fromMillis(Date.now() - 60000);
    await updateDoc(doc(context.firestore(), 'service_requests/request-1'), {
      schedule: past, scheduleFrom: past, scheduleTo: past,
    });
  });
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(applyWithNotification(worker, 'worker-1'));
  await environment.withSecurityRulesDisabled(async context => {
    for (const path of ['service_requests/request-1/applications/worker-1', 'notifications/application-notification']) {
      assert.equal((await getDoc(doc(context.firestore(), path))).exists(), false);
    }
    assert.equal((await getDoc(doc(context.firestore(), 'service_requests/request-1'))).data().status, 'pending');
  });
});

test('deadline: bypassing the UI cannot apply at/past the server-clock boundary', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'service_requests/request-1'), {
      scheduleFrom: Timestamp.now(),
    });
  });
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(setDoc(doc(worker, 'service_requests/request-1/applications/worker-1'), {
    requestId: 'request-1', clientId: 'client-1', workerId: 'worker-1', workerName: 'Worker',
    status: 'pending', appliedAt: serverTimestamp(),
  }));
});

test('deadline: Philippine midnight and legacy schedule fallback reject late applications', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  const wall = new Date(Date.now() + 8 * 3600000);
  const midnight = Timestamp.fromMillis(Date.UTC(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate()) - 8 * 3600000);
  for (const overrides of [
    { scheduleFrom: midnight },
    { scheduleFrom: null, schedule: midnight },
    { scheduleFrom: 'invalid' },
  ]) {
    await environment.withSecurityRulesDisabled(async context => {
      await updateDoc(doc(context.firestore(), 'service_requests/request-1'), overrides);
    });
    await assertFails(applyWithNotification(worker, 'worker-1'));
  }
});

test('creator cannot apply after repeated role switches, including atomic notification writes', async () => {
  const owner = environment.authenticatedContext('client-1').firestore();
  for (const role of ['client', 'worker', 'client', 'worker']) {
    await environment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'users/client-1'), {
        role, roles: ['client', 'worker'], verificationStatus: 'verified',
      });
    });
    await assertFails(applyWithNotification(owner, 'client-1'));
    const job = await assertSucceeds(getDoc(doc(owner, 'service_requests/request-1')));
    if (job.data().clientId !== 'client-1') throw new Error('Role switching changed ownership.');
    const history = await assertSucceeds(getDocs(query(
      collection(owner, 'service_requests'), where('clientId', '==', 'client-1'),
    )));
    if (history.size !== 1) throw new Error('Client history must retain the original job.');
  }
  await environment.withSecurityRulesDisabled(async (context) => {
    for (const path of ['service_requests/request-1/applications/client-1', 'notifications/application-notification']) {
      if ((await getDoc(doc(context.firestore(), path))).exists()) {
        throw new Error('Self-application must not leave an application or notification.');
      }
    }
  });
});

test('creator cannot bypass self-application restriction with a standalone or forged application', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'users/client-1'), {
      role: 'worker', verificationStatus: 'verified',
    });
  });
  const owner = environment.authenticatedContext('client-1').firestore();
  for (const clientId of ['client-1', 'client-2']) {
    await assertFails(setDoc(doc(owner, 'service_requests/request-1/applications/client-1'), {
      requestId: 'request-1', clientId, workerId: 'client-1', workerName: 'Owner',
      status: 'pending', appliedAt: serverTimestamp(),
    }));
  }
});

test('applications fail closed for missing or malformed legacy creator UIDs', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  for (const clientId of [undefined, '', '   ', 42, false, {}, 'x'.repeat(129)]) {
    await environment.withSecurityRulesDisabled(async (context) => {
      const data = { ...requestData, clientId };
      if (clientId === undefined) delete data.clientId;
      await setDoc(doc(context.firestore(), 'service_requests/request-1'), data);
    });
    await assertFails(setDoc(doc(worker, 'service_requests/request-1/applications/worker-1'), {
      requestId: 'request-1', clientId: clientId ?? 'forged-client', workerId: 'worker-1',
      workerName: 'Verified Worker', status: 'pending', appliedAt: serverTimestamp(),
    }));
  }
});

test('creator cannot accept a legacy self-application or transfer job ownership', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'service_requests/request-1/applications/client-1'), {
      requestId: 'request-1', clientId: 'client-1', workerId: 'client-1',
      workerName: 'Owner', status: 'pending', appliedAt: Timestamp.now(),
    });
  });
  const owner = environment.authenticatedContext('client-1').firestore();
  const batch = writeBatch(owner);
  batch.update(doc(owner, 'service_requests/request-1'), {
    status: 'accepted', workerId: 'client-1', workerName: 'Owner', acceptedAt: serverTimestamp(),
  });
  batch.update(doc(owner, 'service_requests/request-1/applications/client-1'), {
    status: 'accepted', reviewedAt: serverTimestamp(),
  });
  await assertFails(batch.commit());
  await assertFails(updateDoc(doc(owner, 'service_requests/request-1'), {
    clientId: 'client-2', updatedAt: serverTimestamp(),
  }));
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

test('worker can read their missing application before applying', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  const missing = await assertSucceeds(
    getDoc(doc(worker, 'service_requests/request-1/applications/worker-1')),
  );
  if (missing.exists()) throw new Error('Expected no existing application.');
});

async function applyWithNotification(worker, workerId) {
  const requestRef = doc(worker, 'service_requests/request-1');
  const applicationRef = doc(
    worker, `service_requests/request-1/applications/${workerId}`,
  );
  await runTransaction(worker, async (transaction) => {
    const request = await transaction.get(requestRef);
    const existing = await transaction.get(applicationRef);
    if (request.data().status !== 'pending' || existing.exists()) {
      throw new Error('Request is not available for a new application.');
    }
    transaction.set(applicationRef, {
      requestId: 'request-1',
      clientId: request.data().clientId,
      workerId,
      workerName: 'Verified Worker',
      status: 'pending',
      appliedAt: serverTimestamp(),
    });
    transaction.set(doc(worker, 'notifications/application-notification'), {
      recipientId: request.data().clientId,
      senderId: workerId,
      requestId: 'request-1',
      type: 'workerApplication',
      title: 'New worker application',
      body: 'Verified Worker applied for Repair a kitchen sink.',
      read: false,
      createdAt: serverTimestamp(),
    });
  });
}

test('verified worker applies with the client notification in one transaction', async () => {
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(applyWithNotification(worker, 'worker-1'));
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(getDoc(doc(client, 'notifications/application-notification')));
  const application = await getDoc(
    doc(worker, 'service_requests/request-1/applications/worker-1'),
  );
  if (application.data().status !== 'pending') {
    throw new Error('Application was not saved.');
  }
});

test('unverified server profile cannot apply even with a verified auth claim', async () => {
  const worker = environment.authenticatedContext('worker-2', {
    verificationStatus: 'verified',
  }).firestore();
  await assertFails(applyWithNotification(worker, 'worker-2'));
  await environment.withSecurityRulesDisabled(async (context) => {
    const notification = await getDoc(
      doc(context.firestore(), 'notifications/application-notification'),
    );
    if (notification.exists()) {
      throw new Error('A rejected transaction must not save its notification.');
    }
  });
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
  batch.set(doc(client, 'conversations/client-1_worker-1'), {
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

test('client atomically creates a request with public and private locations', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  const batch = writeBatch(client);
  batch.set(doc(client, 'service_requests/new-request'), {
    ...requestData,
    areaPosition: new GeoPoint(14.84, 120.81),
    createdAt: serverTimestamp(),
  });
  batch.set(doc(client, 'service_requests/new-request/private/location'), {
    position: new GeoPoint(14.8441, 120.8119),
    address: '123 Example Street, Malolos, Bulacan',
    createdAt: serverTimestamp(),
  });

  await assertSucceeds(batch.commit());
});

test('new requests require both a public coordinate and private location', async () => {
  const client = environment.authenticatedContext('client-1').firestore();

  await assertFails(
    setDoc(doc(client, 'service_requests/no-private-location'), {
      ...requestData,
      areaPosition: new GeoPoint(14.84, 120.81),
      createdAt: serverTimestamp(),
    }),
  );

  const batch = writeBatch(client);
  batch.set(doc(client, 'service_requests/no-public-location'), {
    ...requestData,
    createdAt: serverTimestamp(),
  });
  batch.set(
    doc(client, 'service_requests/no-public-location/private/location'),
    {
      position: new GeoPoint(14.8441, 120.8119),
      address: '123 Example Street, Malolos, Bulacan',
      createdAt: serverTimestamp(),
    },
  );
  await assertFails(batch.commit());
});

test('online requests are created without any map location', async () => {
  const client = environment.authenticatedContext('client-1').firestore();

  await assertSucceeds(
    setDoc(doc(client, 'service_requests/online-request'), {
      ...requestData,
      modality: 'online',
      location: 'Online',
      createdAt: serverTimestamp(),
    }),
  );

  // An online job must not carry a public pin.
  await assertFails(
    setDoc(doc(client, 'service_requests/online-with-pin'), {
      ...requestData,
      modality: 'online',
      location: 'Online',
      areaPosition: new GeoPoint(14.84, 120.81),
      createdAt: serverTimestamp(),
    }),
  );
});

test('on-site and hybrid requests still need both locations', async () => {
  const client = environment.authenticatedContext('client-1').firestore();

  for (const modality of ['onsite', 'hybrid']) {
    await assertFails(
      setDoc(doc(client, `service_requests/${modality}-no-pin`), {
        ...requestData,
        modality,
        createdAt: serverTimestamp(),
      }),
    );

    const batch = writeBatch(client);
    batch.set(doc(client, `service_requests/${modality}-pinned`), {
      ...requestData,
      modality,
      areaPosition: new GeoPoint(14.84, 120.81),
      createdAt: serverTimestamp(),
    });
    batch.set(
      doc(client, `service_requests/${modality}-pinned/private/location`),
      {
        position: new GeoPoint(14.8441, 120.8119),
        address: '123 Example Street, Malolos, Bulacan',
        createdAt: serverTimestamp(),
      },
    );
    await assertSucceeds(batch.commit());
  }
});

test('unknown work types are rejected', async () => {
  const client = environment.authenticatedContext('client-1').firestore();

  await assertFails(
    setDoc(doc(client, 'service_requests/remote-request'), {
      ...requestData,
      modality: 'remote',
      createdAt: serverTimestamp(),
    }),
  );
});

test('exact location is private until a worker is selected', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(
        context.firestore(),
        'service_requests/request-1/private/location',
      ),
      {
        position: new GeoPoint(14.8441, 120.8119),
        address: '123 Example Street, Malolos, Bulacan',
        createdAt: Timestamp.fromDate(new Date('2026-10-10T00:00:00Z')),
      },
    );
  });

  const client = environment.authenticatedContext('client-1').firestore();
  const worker = environment.authenticatedContext('worker-1').firestore();
  const privatePath = 'service_requests/request-1/private/location';

  await assertSucceeds(getDoc(doc(client, privatePath)));
  await assertFails(getDoc(doc(worker, privatePath)));

  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'service_requests/request-1'), {
      status: 'accepted',
      workerId: 'worker-1',
      workerName: 'Verified Worker',
      acceptedAt: Timestamp.fromDate(new Date('2026-10-11T00:00:00Z')),
    });
  });

  await assertSucceeds(getDoc(doc(worker, privatePath)));
  const otherWorker = environment
    .authenticatedContext('worker-2')
    .firestore();
  await assertFails(getDoc(doc(otherWorker, privatePath)));
});
