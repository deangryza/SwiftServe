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
    await setDoc(doc(context.firestore(), 'public_profiles/worker-1'), {
      uid: 'worker-1',
      fullName: 'Worker One',
      role: 'worker',
      photoBase64: 'photo',
      createdAt: new Date('2026-10-19T00:00:00Z'),
      updatedAt: new Date('2026-10-19T00:00:00Z'),
    });
  });
});

after(async () => {
  await environment.cleanup();
});

test('signed-in users can read public profile photos without private details', async () => {
  const client = environment.authenticatedContext('client-1');
  await assertSucceeds(
    getDoc(doc(client.firestore(), 'public_profiles/worker-1')),
  );
  const guest = environment.unauthenticatedContext();
  await assertFails(
    getDoc(doc(guest.firestore(), 'public_profiles/worker-1')),
  );
});

test('a user can create and update only their own valid public profile', async () => {
  const client = environment.authenticatedContext('client-1');
  await assertSucceeds(
    setDoc(doc(client.firestore(), 'public_profiles/client-1'), {
      uid: 'client-1',
      fullName: 'Client One',
      role: 'client',
      photoBase64: 'photo',
      location: 'Malolos, Bulacan',
      description: 'Posts clear household service requests.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(client.firestore(), 'public_profiles/client-1'), {
      fullName: 'Client Updated',
      photoBase64: 'new-photo',
      location: 'Guiguinto, Bulacan',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(client.firestore(), 'public_profiles/worker-1'), {
      photoBase64: 'stolen',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('public profiles reject role changes and oversized photos', async () => {
  const worker = environment.authenticatedContext('worker-1');
  await assertFails(
    updateDoc(doc(worker.firestore(), 'public_profiles/worker-1'), {
      role: 'client',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(worker.firestore(), 'public_profiles/worker-1'), {
      photoBase64: 'A'.repeat(65537),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('public profiles accept safe professional fields and reject oversized data', async () => {
  const worker = environment.authenticatedContext('worker-1');
  await assertSucceeds(
    updateDoc(doc(worker.firestore(), 'public_profiles/worker-1'), {
      location: 'Malolos, Bulacan',
      description: 'Experienced home repair specialist.',
      category: 'Home Services',
      skills: ['Plumbing', 'Painting'],
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(worker.firestore(), 'public_profiles/worker-1'), {
      description: 'A'.repeat(1001),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(worker.firestore(), 'public_profiles/worker-1'), {
      skills: Array.from({ length: 31 }, (_, index) => 'Skill ' + index),
      updatedAt: serverTimestamp(),
    }),
  );
});
