const fs = require('node:fs');
const path = require('node:path');
const { before, beforeEach, after, test } = require('node:test');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, query, collection, where, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');
let environment;
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'swiftserve-rules-test',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/account'), { fullName: 'Account', role: 'client', roles: ['client', 'worker'], verificationStatus: 'pending' });
    await setDoc(doc(db, 'users/reviewer'), { fullName: 'Reviewer', role: 'client' });
    await setDoc(doc(db, 'service_requests/worker-job'), { clientId: 'reviewer', workerId: 'account', status: 'completed' });
    await setDoc(doc(db, 'service_requests/client-job'), { clientId: 'account', workerId: 'reviewer', status: 'completed' });
  });
});
after(async () => { await environment.cleanup(); });

const workerReview = () => ({ requestId: 'worker-job', clientId: 'reviewer', clientName: 'Reviewer',
  workerId: 'account', workerName: 'Account', rating: 5, comment: 'Completed the task.', createdAt: serverTimestamp() });
const clientReview = () => ({ requestId: 'client-job', clientId: 'account', clientName: 'Account',
  workerId: 'reviewer', workerName: 'Reviewer', rating: 3, comment: 'Clear instructions.', createdAt: serverTimestamp() });

test('both review contexts stay readable by another user after repeated recipient role changes', async () => {
  const author = environment.authenticatedContext('reviewer').firestore();
  await assertSucceeds(setDoc(doc(author, 'reviews/worker-job'), workerReview()));
  await assertSucceeds(setDoc(doc(author, 'client_reviews/client-job'), clientReview()));
  const viewer = environment.authenticatedContext('viewer').firestore();
  for (const role of ['client', 'worker', 'client']) {
    await environment.withSecurityRulesDisabled(async context => {
      await updateDoc(doc(context.firestore(), 'users/account'), { role });
    });
    const workers = await assertSucceeds(getDocs(query(collection(viewer, 'reviews'), where('workerId', '==', 'account'))));
    const clients = await assertSucceeds(getDocs(query(collection(viewer, 'client_reviews'), where('clientId', '==', 'account'))));
    if (workers.size !== 1 || clients.size !== 1) throw new Error('Role change lost or duplicated review history.');
    if (workers.docs[0].data().requestId !== 'worker-job' || clients.docs[0].data().requestId !== 'client-job') {
      throw new Error('Review transaction context changed.');
    }
  }
  let account;
  await environment.withSecurityRulesDisabled(async context => {
    account = await getDoc(doc(context.firestore(), 'users/account'));
  });
  if (account.data().verificationStatus !== 'pending') throw new Error('Rating must not grant identity verification.');
});

test('role switching does not permit duplicate edits deletes or reviews from unrelated users', async () => {
  const author = environment.authenticatedContext('reviewer').firestore();
  await assertSucceeds(setDoc(doc(author, 'reviews/worker-job'), workerReview()));
  await assertFails(setDoc(doc(author, 'reviews/worker-job'), workerReview()));
  const other = environment.authenticatedContext('other').firestore();
  await assertFails(updateDoc(doc(other, 'reviews/worker-job'), { rating: 1 }));
  await assertFails(deleteDoc(doc(other, 'reviews/worker-job')));
  await assertFails(setDoc(doc(other, 'client_reviews/client-job'), clientReview()));
  const guest = environment.unauthenticatedContext().firestore();
  await assertFails(getDocs(query(collection(guest, 'reviews'), where('workerId', '==', 'account'))));
});

test('completed transaction and original reviewer identity are still required', async () => {
  const author = environment.authenticatedContext('reviewer').firestore();
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'service_requests/worker-job'), { status: 'ongoing' });
  });
  await assertFails(setDoc(doc(author, 'reviews/worker-job'), workerReview()));
  await assertFails(setDoc(doc(author, 'client_reviews/client-job'), { ...clientReview(), workerName: 'Impersonated' }));
});
