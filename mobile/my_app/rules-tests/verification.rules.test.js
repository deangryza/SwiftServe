const assert = require('node:assert/strict');
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
  setDoc,
  updateDoc,
} = require('firebase/firestore');
const {
  getBytes,
  ref,
  uploadBytes,
} = require('firebase/storage');

const projectRoot = path.resolve(__dirname, '..');
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'swiftserve-rules-test',
    firestore: {
      rules: fs.readFileSync(path.join(projectRoot, 'firestore.rules'), 'utf8'),
    },
    storage: {
      rules: fs.readFileSync(path.join(projectRoot, 'storage.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users/worker-1'), {
      role: 'worker',
      verificationStatus: 'pending',
      fullName: 'Worker',
    });
    await setDoc(doc(context.firestore(), 'worker_verifications/worker-1'), {
      workerId: 'worker-1',
      status: 'pending',
      faceVerified: true,
      faceMatchConfidence: 95,
    });
    await uploadBytes(
      ref(context.storage(), 'worker_verifications/worker-1/submission/id.jpg'),
      new Uint8Array([0xff, 0xd8, 0xff]),
      { contentType: 'image/jpeg' },
    );
  });
});

after(async () => {
  await environment.cleanup();
});

test('owner can read their backend-created verification record', async () => {
  const worker = environment.authenticatedContext('worker-1');
  const snapshot = await assertSucceeds(
    getDoc(doc(worker.firestore(), 'worker_verifications/worker-1')),
  );
  assert.equal(snapshot.data().faceVerified, true);
});

test('worker cannot create or alter authoritative verification fields', async () => {
  const worker = environment.authenticatedContext('worker-1');
  await assertFails(setDoc(doc(worker.firestore(), 'worker_verifications/new-record'), {
    status: 'pending',
    faceVerified: true,
  }));
  await assertFails(updateDoc(doc(worker.firestore(), 'worker_verifications/worker-1'), {
    faceMatchConfidence: 100,
    faceVerified: true,
  }));
});

test('worker can still update their profile without changing protected fields', async () => {
  const worker = environment.authenticatedContext('worker-1');
  await assertSucceeds(updateDoc(doc(worker.firestore(), 'users/worker-1'), {
    fullName: 'Updated Worker',
  }));
});

test('owner can read but cannot upload verification objects', async () => {
  const worker = environment.authenticatedContext('worker-1');
  const existing = ref(worker.storage(), 'worker_verifications/worker-1/submission/id.jpg');
  await assertSucceeds(getBytes(existing));
  await assertFails(uploadBytes(
    ref(worker.storage(), 'worker_verifications/worker-1/new/id.jpg'),
    new Uint8Array([0xff, 0xd8, 0xff]),
    { contentType: 'image/jpeg' },
  ));
});

