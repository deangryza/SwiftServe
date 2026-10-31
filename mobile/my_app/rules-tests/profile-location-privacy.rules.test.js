const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { before, beforeEach, after, test } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, serverTimestamp } = require('firebase/firestore');
const { publicProfileLocation } = require('../../../swiftserve-backend/src/services/publicProfileLocation');
const host = process.env.FIRESTORE_EMULATOR_HOST || '';
if (!/^127\.0\.0\.1:\d+$/.test(host)) throw new Error('Loopback demo emulator required');
const exact = '123 Example Street, Brgy. Ligas, Malolos, Bulacan';
let environment;
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-swiftserve-privacy', firestore: {
    rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
  } });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/owner'), { address: exact, role: 'worker' });
    await setDoc(doc(db, 'public_profiles/owner'), { uid: 'owner', fullName: 'Owner', role: 'worker',
      photoBase64: '', ...publicProfileLocation(exact), updatedAt: serverTimestamp() });
    await setDoc(doc(db, 'worker_profiles/owner'), { workerId: 'owner', verificationStatus: 'verified',
      ...publicProfileLocation(exact) });
  });
});
after(async () => environment?.cleanup());

test('new general-area projections are readable without disclosing the private address', async () => {
  const viewer = environment.authenticatedContext('viewer').firestore();
  for (const collection of ['public_profiles', 'worker_profiles']) {
    const snapshot = await assertSucceeds(getDoc(doc(viewer, collection, 'owner')));
    assert.equal(snapshot.data().location, 'Brgy. Ligas, Malolos');
    assert.ok(!JSON.stringify(snapshot.data()).includes('123 Example Street'));
    assert.equal(snapshot.data().address, undefined);
  }
  await assertFails(getDoc(doc(viewer, 'users/owner')));
  const owner = environment.authenticatedContext('owner').firestore();
  assert.equal((await assertSucceeds(getDoc(doc(owner, 'users/owner')))).data().address, exact);
});

test('owner photo/name updates preserve backend-written locality components under existing rules', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  await assertSucceeds(updateDoc(doc(owner, 'public_profiles/owner'), {
    fullName: 'New Name', photoBase64: '', updatedAt: serverTimestamp(),
  }));
  const profile = (await getDoc(doc(owner, 'public_profiles/owner'))).data();
  assert.equal(profile.cityMunicipality, 'Malolos');
  assert.equal(profile.barangay, 'Ligas');
  const viewer = environment.authenticatedContext('viewer').firestore();
  await assertFails(updateDoc(doc(viewer, 'public_profiles/owner'), { location: '123 Other Street' }));
});

test('characterization: legacy public addresses remain API-readable until a separately approved backfill', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'public_profiles/legacy'), { location: exact });
  });
  const viewer = environment.authenticatedContext('viewer').firestore();
  const legacy = await assertSucceeds(getDoc(doc(viewer, 'public_profiles/legacy')));
  // This documents an unresolved storage exposure, NOT a claim of protection.
  assert.equal(legacy.data().location, exact);
  assert.equal(publicProfileLocation(legacy.data()).location, 'Brgy. Ligas, Malolos');
});
