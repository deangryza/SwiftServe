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
  GeoPoint,
} = require('firebase/firestore');

const projectRoot = path.resolve(__dirname, '..');
let environment;

const errandData = {
  clientId: 'client-1',
  clientName: 'Client One',
  title: 'Buy groceries',
  category: 'Errands',
  budget: 99,
  schedule: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
  scheduleFrom: Timestamp.fromDate(new Date('2026-10-20T00:00:00Z')),
  scheduleTo: Timestamp.fromDate(new Date('2026-10-21T00:00:00Z')),
  modality: 'errand',
  location: 'Malolos',
  areaPosition: new GeoPoint(14.84, 120.81),
  dropoffLocation: 'Bulakan',
  dropoffAreaPosition: new GeoPoint(14.79, 120.88),
  errandItems: '2 kg rice',
  distanceKm: 5.1,
  description: 'Pick up rice from the market and bring it home.',
  status: 'pending',
};

const exactLocation = {
  position: new GeoPoint(14.8441, 120.8119),
  address: 'Public Market, Malolos',
  dropoffPosition: new GeoPoint(14.7912, 120.8811),
  dropoffAddress: '45 Example Street, Bulakan',
};

const riderPath = 'service_requests/errand-1/private/rider_location';

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

async function seedErrand(fields) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'service_requests/errand-1'), {
      ...errandData,
      createdAt: Timestamp.fromDate(new Date('2026-10-10T00:00:00Z')),
      workerId: 'worker-1',
      workerName: 'Rider One',
      ...fields,
    });
  });
}

function createErrand(client, id, requestFields, privateFields) {
  const batch = writeBatch(client);
  batch.set(doc(client, `service_requests/${id}`), {
    ...errandData,
    createdAt: serverTimestamp(),
    ...requestFields,
  });
  batch.set(doc(client, `service_requests/${id}/private/location`), {
    ...exactLocation,
    createdAt: serverTimestamp(),
    ...privateFields,
  });
  return batch.commit();
}

test('client creates an errand with pickup and drop-off', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(createErrand(client, 'ok', {}, {}));
});

test('errands need a drop-off both publicly and privately', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  const { dropoffAreaPosition, ...noPublicDropoff } = errandData;
  const batch = writeBatch(client);
  batch.set(doc(client, 'service_requests/no-public'), {
    ...noPublicDropoff,
    createdAt: serverTimestamp(),
  });
  batch.set(doc(client, 'service_requests/no-public/private/location'), {
    ...exactLocation,
    createdAt: serverTimestamp(),
  });
  await assertFails(batch.commit());

  const { dropoffPosition, dropoffAddress, ...noPrivateDropoff } =
    exactLocation;
  const second = writeBatch(client);
  second.set(doc(client, 'service_requests/no-private'), {
    ...errandData,
    createdAt: serverTimestamp(),
  });
  second.set(doc(client, 'service_requests/no-private/private/location'), {
    ...noPrivateDropoff,
    createdAt: serverTimestamp(),
  });
  await assertFails(second.commit());
});

test('errands cannot be created already in progress', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertFails(
    createErrand(client, 'staged', { errandStage: 'pickedUp' }, {}),
  );
});

test('other work types cannot carry errand fields', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertFails(createErrand(client, 'onsite', { modality: 'onsite' }, {}));
});

test('starting an errand sets the rider heading to pickup', async () => {
  await seedErrand({ status: 'accepted' });
  const rider = environment.authenticatedContext('worker-1').firestore();
  const ref = doc(rider, 'service_requests/errand-1');

  await assertFails(
    updateDoc(ref, { status: 'ongoing', ongoingAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(ref, {
      status: 'ongoing',
      ongoingAt: serverTimestamp(),
      errandStage: 'headingToPickup',
    }),
  );
});

test('errand stages move forward one step and only for the rider', async () => {
  await seedErrand({ status: 'ongoing', errandStage: 'headingToPickup' });
  const rider = environment.authenticatedContext('worker-1').firestore();
  const client = environment.authenticatedContext('client-1').firestore();
  const ref = doc(rider, 'service_requests/errand-1');

  // No skipping ahead, and no delivering before being on the way.
  await assertFails(
    updateDoc(ref, { errandStage: 'delivering', deliveringAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(ref, { status: 'completed', completedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(doc(client, 'service_requests/errand-1'), {
      errandStage: 'pickedUp',
      pickedUpAt: serverTimestamp(),
    }),
  );

  await assertSucceeds(
    updateDoc(ref, { errandStage: 'pickedUp', pickedUpAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(ref, { errandStage: 'headingToPickup' }),
  );
  await assertSucceeds(
    updateDoc(ref, { errandStage: 'delivering', deliveringAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(ref, { status: 'completed', completedAt: serverTimestamp() }),
  );
});

test('only the assigned rider shares location, only while ongoing', async () => {
  await seedErrand({ status: 'accepted' });
  const rider = environment.authenticatedContext('worker-1').firestore();
  const otherRider = environment.authenticatedContext('worker-2').firestore();
  const position = {
    position: new GeoPoint(14.83, 120.82),
    heading: 90,
    speed: 4.2,
    updatedAt: serverTimestamp(),
  };

  await assertFails(setDoc(doc(rider, riderPath), position));

  await seedErrand({ status: 'ongoing', errandStage: 'headingToPickup' });
  await assertSucceeds(setDoc(doc(rider, riderPath), position));
  await assertSucceeds(setDoc(doc(rider, riderPath), position));
  await assertFails(setDoc(doc(otherRider, riderPath), position));
  await assertFails(
    setDoc(doc(rider, riderPath), { ...position, note: 'extra field' }),
  );

  await seedErrand({ status: 'completed', errandStage: 'delivering' });
  await assertFails(setDoc(doc(rider, riderPath), position));
});

test('rider location is visible only to the client and the rider', async () => {
  await seedErrand({ status: 'ongoing', errandStage: 'pickedUp' });
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), riderPath), {
      position: new GeoPoint(14.83, 120.82),
      updatedAt: Timestamp.now(),
    });
  });

  const client = environment.authenticatedContext('client-1').firestore();
  const rider = environment.authenticatedContext('worker-1').firestore();
  const outsider = environment.authenticatedContext('client-2').firestore();

  await assertSucceeds(getDoc(doc(client, riderPath)));
  await assertSucceeds(getDoc(doc(rider, riderPath)));
  await assertFails(getDoc(doc(outsider, riderPath)));
});
