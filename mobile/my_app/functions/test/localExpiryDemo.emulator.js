const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const path = require('node:path');
const { PROJECT, validate } = require('../scripts/localExpiryDemo');

test('running local worker expires a client job and owner reads notification while worker is denied', {
  skip: process.env.RUN_LOCAL_EXPIRY_DEMO_TESTS !== 'true', timeout: 45000,
}, async () => {
  validate(process.env);
  const clientRequire = createRequire(path.resolve(__dirname, '../../rules-tests/package.json'));
  const { initializeApp, deleteApp } = clientRequire('firebase/app');
  const { getAuth, connectAuthEmulator, signInWithEmailAndPassword } = clientRequire('firebase/auth');
  const { getFirestore, connectFirestoreEmulator, collection, addDoc, doc, getDoc, setDoc, Timestamp, serverTimestamp, terminate } = clientRequire('firebase/firestore');
  const app = initializeApp({ projectId: PROJECT, apiKey: 'demo-key', appId: 'demo-app' }, 'local-demo-smoke');
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  const db = getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  connectFirestoreEmulator(db, host, Number(port));
  try {
    await signInWithEmailAndPassword(auth, 'client-expiry@example.test', 'LocalTestOnly-Password123!');
    assert.equal((await getDoc(doc(db, 'users', auth.currentUser.uid))).data().role, 'client');
    const start = Timestamp.fromMillis(Date.now() + 3000);
    const request = await addDoc(collection(db, 'service_requests'), {
      clientId: auth.currentUser.uid, clientName: 'Expiry Demo client', title: 'Synthetic demo cleaning',
      category: 'Cleaning', budget: 200, description: 'Local test only', location: 'Online', modality: 'online',
      schedule: start, scheduleFrom: start, scheduleTo: start, status: 'pending', createdAt: serverTimestamp(),
    });
    const until = Date.now() + 25000;
    let original;
    do {
      original = await getDoc(request);
      if (original.data().status === 'expired') break;
      await new Promise(resolve => setTimeout(resolve, 500));
    } while (Date.now() < until);
    assert.equal(original.data().status, 'expired');
    const event = doc(db, 'notifications', `jobExpired_${request.id}`);
    const notification = await getDoc(event);
    assert.equal(notification.data().recipientId, 'expiry-demo-client');
    assert.equal(notification.data().requestId, request.id);
    assert.equal(notification.data().type, 'jobExpired');
    assert.match(notification.data().body, /PHT/);
    await signInWithEmailAndPassword(auth, 'worker-expiry@example.test', 'LocalTestOnly-Password123!');
    const workerId = auth.currentUser.uid;
    assert.equal((await getDoc(doc(db, 'users', workerId))).data().verificationStatus, 'verified');
    await assert.rejects(setDoc(doc(db, 'service_requests', request.id, 'applications', workerId), {
      requestId: request.id, clientId: 'expiry-demo-client', workerId, workerName: 'Expiry Demo worker',
      status: 'pending', appliedAt: serverTimestamp(),
    }), error => error.code === 'permission-denied');
    await assert.rejects(getDoc(event), error => error.code === 'permission-denied');
    console.info('PASS emulator Auth login, real client job write, running expiry loop, owner notification and unauthorized worker denials.');
  } finally {
    await terminate(db); await deleteApp(app);
  }
});
