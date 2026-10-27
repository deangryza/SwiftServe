const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { before, beforeEach, after, test } = require('node:test');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { collection, doc, getDoc, getDocs, query, where, limit, startAfter, setDoc, serverTimestamp } = require('firebase/firestore');

let environment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'swiftserve-rules-test',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/client'), { address: 'Bulihan, Malolos, Bulacan', role: 'client' });
    await setDoc(doc(db, 'users/worker'), { address: 'Private worker address', role: 'worker' });
    for (let index = 0; index < 35; index++) {
      await setDoc(doc(db, `worker_profiles/worker-${String(index).padStart(2, '0')}`), {
        verificationStatus: 'verified', fullName: `Worker ${index}`, location: 'Malolos, Bulacan',
      });
    }
    await setDoc(doc(db, 'worker_profiles/unverified'), { verificationStatus: 'pending' });
    await setDoc(doc(db, 'conversations/client_worker'), {
      requestId: 'accepted-request', participantIds: ['client', 'worker'],
      clientId: 'client', clientName: 'Client', workerId: 'worker', workerName: 'Worker',
      lastMessage: 'Application accepted', updatedAt: new Date(),
    });
    await setDoc(doc(db, 'conversations/other_worker'), {
      participantIds: ['other', 'worker'], clientId: 'other', workerId: 'worker',
    });
  });
});
after(async () => environment.cleanup());

test('verified discovery query is bounded and supports document cursors', async () => {
  const db = environment.authenticatedContext('client').firestore();
  const base = query(collection(db, 'worker_profiles'), where('verificationStatus', '==', 'verified'), limit(30));
  const first = await assertSucceeds(getDocs(base));
  assert.equal(first.size, 30);
  const second = await assertSucceeds(getDocs(query(base, startAfter(first.docs.at(-1)))));
  assert.equal(second.size, 5);
  const ids = [...first.docs, ...second.docs].map((document) => document.id);
  assert.equal(new Set(ids).size, 35);
  assert.equal(ids.includes('unverified'), false);
});

test('client can read their origin but cannot read private worker addresses', async () => {
  const db = environment.authenticatedContext('client').firestore();
  await assertSucceeds(getDoc(doc(db, 'users/client')));
  await assertFails(getDoc(doc(db, 'users/worker')));
});

test('discovery messaging reuses participant-scoped inbox reads', async () => {
  const db = environment.authenticatedContext('client').firestore();
  const conversations = await assertSucceeds(getDocs(query(
    collection(db, 'conversations'), where('participantIds', 'array-contains', 'client'),
  )));
  assert.deepEqual(conversations.docs.map((document) => document.id), ['client_worker']);
  await assertFails(getDocs(collection(db, 'conversations')));
});

test('new direct chats without an accepted job remain prohibited', async () => {
  const db = environment.authenticatedContext('client').firestore();
  await assertFails(setDoc(doc(db, 'conversations/client_worker-2'), {
    requestId: 'nonexistent-request', participantIds: ['client', 'worker-2'],
    clientId: 'client', clientName: 'Client', workerId: 'worker-2', workerName: 'Worker Two',
    lastMessage: '', updatedAt: serverTimestamp(),
  }));
});

test('unauthenticated worker discovery is rejected', async () => {
  const db = environment.unauthenticatedContext().firestore();
  await assertFails(getDocs(query(collection(db, 'worker_profiles'),
    where('verificationStatus', '==', 'verified'), limit(30))));
});
