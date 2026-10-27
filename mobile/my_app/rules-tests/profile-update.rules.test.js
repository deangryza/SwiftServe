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
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
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
    const db = context.firestore();
    // Written by the current backend sign-up.
    await setDoc(doc(db, 'users/client-1'), {
      uid: 'client-1',
      fullName: 'Client One',
      email: 'client@example.com',
      phoneNumber: '+639171111111',
      address: 'Manila',
      role: 'client',
      category: '',
      skills: [],
      verificationStatus: 'not_required',
      createdAt: new Date('2026-10-01T00:00:00Z'),
      updatedAt: new Date('2026-10-01T00:00:00Z'),
    });
    await setDoc(doc(db, 'public_profiles/client-1'), {
      uid: 'client-1',
      fullName: 'Client One',
      role: 'client',
      photoBase64: '',
      createdAt: new Date('2026-10-01T00:00:00Z'),
      updatedAt: new Date('2026-10-01T00:00:00Z'),
    });
    // Accounts created before the backend wrote verificationStatus have no
    // such field, and no public profile.
    await setDoc(doc(db, 'users/legacy-client'), {
      uid: 'legacy-client',
      fullName: 'Legacy Client',
      email: 'legacy@example.com',
      phoneNumber: '09103611214',
      address: 'Malolos',
      role: 'client',
    });
    await setDoc(doc(db, 'users/worker-1'), {
      uid: 'worker-1',
      fullName: 'Worker One',
      phoneNumber: '+639172222222',
      role: 'worker',
      verificationStatus: 'pending',
    });
  });
});

after(async () => {
  await environment.cleanup();
});

// Mirrors _EditProfileScreenState._save in client_profile_screen.dart.
function saveProfile(db, uid, role, { fullName, address, photoBase64 = '' }) {
  const batch = writeBatch(db);
  batch.update(doc(db, `users/${uid}`), {
    fullName,
    address,
    updatedAt: serverTimestamp(),
  });
  batch.set(
    doc(db, `public_profiles/${uid}`),
    { uid, fullName, role, photoBase64, updatedAt: serverTimestamp() },
    { merge: true },
  );
  return batch.commit();
}

// Mirrors _EditProfileScreenState._changePhoto in client_profile_screen.dart.
function savePhoto(db, uid, role, fullName, photoBase64) {
  const batch = writeBatch(db);
  batch.update(doc(db, `users/${uid}`), {
    photoBase64,
    updatedAt: serverTimestamp(),
  });
  batch.set(
    doc(db, `public_profiles/${uid}`),
    { uid, fullName, role, photoBase64, updatedAt: serverTimestamp() },
    { merge: true },
  );
  return batch.commit();
}

test('a client can save name and address from Edit Profile', async () => {
  const db = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(
    saveProfile(db, 'client-1', 'client', {
      fullName: 'Client Renamed',
      address: 'Malolos Bulacan',
    }),
  );
});

for (const [uid, role, originalAddress] of [
  ['client-1', 'client', 'Manila'],
  ['worker-1', 'worker', undefined],
]) {
  test(`${role}: a public location write rejects the entire profile batch`, async () => {
    if (role === 'worker') {
      await environment.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `public_profiles/${uid}`), {
          uid, role, fullName: 'Worker One', photoBase64: '',
          updatedAt: new Date('2026-10-01T00:00:00Z'),
        });
      });
    }
    const db = environment.authenticatedContext(uid).firestore();
    const batch = writeBatch(db);
    batch.update(doc(db, `users/${uid}`), {
      address: 'Bulihan, Malolos, Bulacan', updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, `public_profiles/${uid}`), {
      location: 'Bulihan, Malolos, Bulacan', updatedAt: serverTimestamp(),
    }, { merge: true });
    await assertFails(batch.commit());
    assert.equal((await getDoc(doc(db, `users/${uid}`))).data().address, originalAddress);
  });

  test(`${role}: structured address is saved privately without publishing it`, async () => {
    const db = environment.authenticatedContext(uid).firestore();
    const address = '123 Example Street, Bulihan, Malolos, Bulacan';
    await assertSucceeds(saveProfile(db, uid, role, {
      fullName: 'Updated Name', address,
    }));
    assert.equal((await getDoc(doc(db, `users/${uid}`))).data().address, address);
    const publicProfile = (await getDoc(doc(db, `public_profiles/${uid}`))).data();
    assert.equal(publicProfile.fullName, 'Updated Name');
    assert.equal('address' in publicProfile, false);
    assert.equal('location' in publicProfile, false);
  });
}

test('an account without verificationStatus can still edit its profile', async () => {
  const db = environment.authenticatedContext('legacy-client').firestore();
  await assertSucceeds(
    saveProfile(db, 'legacy-client', 'client', {
      fullName: 'Legacy Client',
      address: 'Malolos Bulacan',
    }),
  );
});

test('a user can change their profile photo', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  await assertSucceeds(
    savePhoto(client, 'client-1', 'client', 'Client One', 'photo'),
  );
  const legacy = environment.authenticatedContext('legacy-client').firestore();
  await assertSucceeds(
    savePhoto(legacy, 'legacy-client', 'client', 'Legacy Client', 'photo'),
  );
});

test('a worker can edit their profile', async () => {
  const db = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    saveProfile(db, 'worker-1', 'worker', {
      fullName: 'Worker Renamed',
      address: 'Quezon City',
    }),
  );
});

test('a profile whose public profile has extra older fields can be edited', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'public_profiles/worker-1'), {
      uid: 'worker-1',
      role: 'worker',
      fullName: 'Worker One',
      photoBase64: '',
      location: 'Malolos Bulacan',
      createdAt: new Date('2026-10-01T00:00:00Z'),
      updatedAt: new Date('2026-10-01T00:00:00Z'),
    });
  });
  const db = environment.authenticatedContext('worker-1').firestore();
  await assertSucceeds(
    saveProfile(db, 'worker-1', 'worker', {
      fullName: 'Worker One',
      address: 'Malolos Bulacan',
    }),
  );
  await assertSucceeds(
    savePhoto(db, 'worker-1', 'worker', 'Worker One', 'photo'),
  );
  // Older fields are tolerated, not editable, and nothing new can be added.
  for (const change of [{ location: 'Elsewhere' }, { email: 'a@b.c' }]) {
    await assertFails(
      updateDoc(doc(db, 'public_profiles/worker-1'), {
        ...change,
        updatedAt: serverTimestamp(),
      }),
    );
  }
});

test('users cannot change protected profile fields', async () => {
  const client = environment.authenticatedContext('client-1').firestore();
  for (const change of [
    { role: 'worker' },
    { verificationStatus: 'verified' },
    { phoneNumber: '+639179999999' },
    { email: 'other@example.com' },
    { uid: 'someone-else' },
  ]) {
    await assertFails(updateDoc(doc(client, 'users/client-1'), change));
  }
  // A missing status must not be fillable by the user.
  const legacy = environment.authenticatedContext('legacy-client').firestore();
  await assertFails(
    updateDoc(doc(legacy, 'users/legacy-client'), {
      verificationStatus: 'verified',
    }),
  );
  const worker = environment.authenticatedContext('worker-1').firestore();
  await assertFails(
    updateDoc(doc(worker, 'users/worker-1'), { verificationStatus: 'verified' }),
  );
});

test('profile edits are validated', async () => {
  const db = environment.authenticatedContext('client-1').firestore();
  await assertFails(
    updateDoc(doc(db, 'users/client-1'), { fullName: '' }),
  );
  await assertFails(
    updateDoc(doc(db, 'users/client-1'), { address: 'A'.repeat(301) }),
  );
  await assertFails(
    updateDoc(doc(db, 'users/client-1'), { photoBase64: 'A'.repeat(65537) }),
  );
  await assertFails(
    updateDoc(doc(db, 'users/client-1'), {
      updatedAt: new Date('2020-01-01T00:00:00Z'),
    }),
  );
});

test('users cannot edit someone else\'s profile', async () => {
  const db = environment.authenticatedContext('client-1').firestore();
  await assertFails(
    updateDoc(doc(db, 'users/worker-1'), { address: 'Hacked' }),
  );
});
