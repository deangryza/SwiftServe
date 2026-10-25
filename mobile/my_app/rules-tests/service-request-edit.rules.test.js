const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteField,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
  Timestamp,
  GeoPoint,
} = require('firebase/firestore');

const projectRoot = path.resolve(__dirname, '..');
let environment;

const requestPath = 'service_requests/job-1';
const locationPath = `${requestPath}/private/location`;

const onsiteRequest = {
  clientId: 'client-1',
  clientName: 'Client One',
  title: 'Fix the sink',
  category: 'Repairs',
  budget: 500,
  schedule: Timestamp.fromDate(new Date('2026-11-01T00:00:00Z')),
  scheduleFrom: Timestamp.fromDate(new Date('2026-11-01T00:00:00Z')),
  scheduleTo: Timestamp.fromDate(new Date('2026-11-02T00:00:00Z')),
  modality: 'onsite',
  location: 'Malolos',
  areaPosition: new GeoPoint(14.84, 120.81),
  description: 'The kitchen sink is leaking.',
  status: 'pending',
  createdAt: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
};

const exactLocation = {
  position: new GeoPoint(14.8441, 120.8119),
  address: '12 Example Street, Malolos',
  createdAt: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
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
});

after(async () => {
  await environment.cleanup();
});

async function seed(fields = {}) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, requestPath), { ...onsiteRequest, ...fields });
    await setDoc(doc(db, locationPath), exactLocation);
  });
}

function clientDb(uid = 'client-1') {
  return environment.authenticatedContext(uid).firestore();
}

function editText(db, fields = {}) {
  return updateDoc(doc(db, requestPath), {
    title: 'Fix the sink and faucet',
    budget: 750,
    description: 'The kitchen sink and faucet are leaking.',
    updatedAt: serverTimestamp(),
    ...fields,
  });
}

test('client edits their open post and moves the pin', async () => {
  await seed();
  const db = clientDb();
  await assertSucceeds(editText(db));

  const batch = writeBatch(db);
  batch.update(doc(db, requestPath), {
    location: 'Bulakan',
    areaPosition: new GeoPoint(14.79, 120.88),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, locationPath), {
    position: new GeoPoint(14.7912, 120.8811),
    address: '45 Example Street, Bulakan',
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
});

test('client switches an onsite post to online and drops the pin', async () => {
  await seed();
  const db = clientDb();
  const batch = writeBatch(db);
  batch.update(doc(db, requestPath), {
    modality: 'online',
    location: 'Online',
    areaPosition: deleteField(),
    updatedAt: serverTimestamp(),
  });
  batch.delete(doc(db, locationPath));
  await assertSucceeds(batch.commit());
});

test('switching to online must remove the private pin', async () => {
  await seed();
  await assertFails(
    updateDoc(doc(clientDb(), requestPath), {
      modality: 'online',
      location: 'Online',
      areaPosition: deleteField(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('switching to an errand needs a drop-off', async () => {
  await seed();
  await assertFails(
    updateDoc(doc(clientDb(), requestPath), {
      modality: 'errand',
      errandItems: '2 kg rice',
      distanceKm: 5,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('edits must stamp updatedAt', async () => {
  await seed();
  await assertFails(
    updateDoc(doc(clientDb(), requestPath), { title: 'No timestamp' }),
  );
});

test('posts cannot be edited after a worker is hired', async () => {
  await seed({
    status: 'accepted',
    workerId: 'worker-1',
    workerName: 'Worker One',
    acceptedAt: Timestamp.fromDate(new Date('2026-10-21T00:00:00Z')),
  });
  const db = clientDb();
  await assertFails(editText(db));
  await assertFails(
    setDoc(doc(db, locationPath), {
      position: new GeoPoint(14.7912, 120.8811),
      address: '45 Example Street, Bulakan',
      createdAt: serverTimestamp(),
    }),
  );
});

test('only the owner can edit the post', async () => {
  await seed();
  await assertFails(editText(clientDb('client-2')));
});

test('an edit cannot change status, owner or worker', async () => {
  await seed();
  const db = clientDb();
  await assertFails(editText(db, { status: 'completed' }));
  await assertFails(editText(db, { clientId: 'client-2' }));
  await assertFails(
    editText(db, { workerId: 'worker-1', workerName: 'Worker One' }),
  );
});
