const fs = require('node:fs');
const path = require('node:path');
const { before, beforeEach, after, test } = require('node:test');
const { assertFails, assertSucceeds, initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc, serverTimestamp } = require('firebase/firestore');
let environment;
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'swiftserve-rules-test',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'users/dual'), { role: 'client', roles: ['client', 'worker'], verificationStatus: 'verified' });
    await setDoc(doc(db, 'users/other'), { role: 'worker', verificationStatus: 'verified' });
    await setDoc(doc(db, 'service_requests/job'), { clientId: 'other', workerId: 'dual', status: 'pending' });
    await setDoc(doc(db, 'service_requests/assigned'), { clientId: 'other', workerId: 'dual', status: 'accepted' });
  });
});
after(async () => { await environment.cleanup(); });

const application = () => ({ requestId: 'job', clientId: 'other', workerId: 'dual',
  workerName: 'Dual User', status: 'pending', appliedAt: serverTimestamp() });
const notification = role => ({ recipientId: 'dual', senderId: 'other', requestId: 'assigned',
  recipientRole: role, type: 'applicationAccepted', title: 'Application accepted', body: 'Your application was selected.',
  read: false, createdAt: serverTimestamp() });

test('verified client identity is reusable after switching to the worker role', async () => {
  const dual = environment.authenticatedContext('dual').firestore();
  await assertFails(setDoc(doc(dual, 'service_requests/job/applications/dual'), application()));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'users/dual'), { role: 'worker' });
    // No duplicate worker verification submission/profile approval is required.
    await setDoc(doc(context.firestore(), 'worker_profiles/dual'), { verificationStatus: 'pending' });
  });
  await assertSucceeds(setDoc(doc(dual, 'service_requests/job/applications/dual'), application()));
});

test('pending rejected expired and revoked identity cannot be bypassed by a verified submission document', async () => {
  const dual = environment.authenticatedContext('dual').firestore();
  for (const status of ['pending', 'rejected', 'expired', 'revoked']) {
    await environment.withSecurityRulesDisabled(async context => {
      await updateDoc(doc(context.firestore(), 'users/dual'), { role: 'worker', verificationStatus: status });
      await setDoc(doc(context.firestore(), 'worker_verifications/dual'), { status: 'verified' });
    });
    await assertFails(setDoc(doc(dual, 'service_requests/job/applications/dual'), application()));
  }
});

test('new notification audiences match the recipient job relationship and stay immutable', async () => {
  const sender = environment.authenticatedContext('other').firestore();
  const recipient = environment.authenticatedContext('dual').firestore();
  await assertSucceeds(setDoc(doc(sender, 'notifications/correct'), notification('worker')));
  await assertFails(setDoc(doc(sender, 'notifications/wrong-role'), notification('client')));
  await assertFails(setDoc(doc(sender, 'notifications/forged-account'), notification('account')));
  await assertSucceeds(getDoc(doc(recipient, 'notifications/correct')));
  await assertSucceeds(updateDoc(doc(recipient, 'notifications/correct'), { read: true }));
  await assertFails(updateDoc(doc(recipient, 'notifications/correct'), { recipientRole: 'client' }));
  const stranger = environment.authenticatedContext('stranger').firestore();
  await assertFails(getDoc(doc(stranger, 'notifications/correct')));
});
