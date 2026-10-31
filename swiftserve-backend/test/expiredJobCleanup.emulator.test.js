const { describe, test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { runExpiredJobCleanup } = require('../src/services/expiredJobCleanupService');

const host = process.env.FIRESTORE_EMULATOR_HOST;
if (host && !/^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(host)) {
  throw new Error('Cleanup integration tests require a loopback Firestore emulator.');
}
describe('expired-job cleanup with real Firestore transactions and existing security rules', { skip: !host }, () => {
  const rulesRequire = createRequire(path.resolve(__dirname, '../../mobile/my_app/rules-tests/package.json'));
  const { initializeTestEnvironment } = rulesRequire('@firebase/rules-unit-testing');
  const client = rulesRequire('firebase/firestore');
  const { initializeApp, deleteApp } = require('firebase-admin/app');
  const { getFirestore, Timestamp } = require('firebase-admin/firestore');
  const projectId = 'demo-swiftserve-cleanup';
  const now = new Date('2026-10-29T04:00:00Z');
  const expired = overrides => {
    const schedule = Timestamp.fromDate(new Date('2026-10-29T01:00:00Z'));
    return { clientId: 'client', clientName: 'Client', title: 'Job', category: 'Other', budget: 100,
      description: 'Task', location: 'Online', modality: 'online', status: 'pending',
      schedule, scheduleFrom: schedule, scheduleTo: schedule, createdAt: schedule, ...overrides };
  };
  const logger = { info() {}, warn() {}, error() {} };
  let environment, app, db;
  const cleanup = (database = db, asOf = now) => runExpiredJobCleanup({ db: database, dryRun: false, now: () => asOf, logger });
  // Apply under the real emulator request.time before the start, then advance
  // only the cleanup test clock. This models valid historical applications.
  const futureSchedule = () => Timestamp.fromMillis(Date.now() + 86400000);
  const scheduled = start => expired({ schedule: start, scheduleFrom: start, scheduleTo: start });
  const ref = id => db.collection('service_requests').doc(id);
  async function apply(id, afterRead = async () => {}) {
    const worker = environment.authenticatedContext('worker').firestore();
    const request = client.doc(worker, 'service_requests', id);
    const application = client.doc(worker, 'service_requests', id, 'applications', 'worker');
    const notification = client.doc(worker, 'notifications', `application-${id}`);
    return client.runTransaction(worker, async transaction => {
      const latest = await transaction.get(request);
      if (!latest.exists() || latest.data().status !== 'pending') throw new Error('JOB_UNAVAILABLE');
      await afterRead();
      const existing = await transaction.get(application);
      if (existing.exists()) throw new Error('ALREADY_APPLIED');
      transaction.set(application, { requestId: id, clientId: 'client', workerId: 'worker',
        workerName: 'Worker', status: 'pending', appliedAt: client.serverTimestamp() });
      transaction.set(notification, { recipientId: 'client', senderId: 'worker', requestId: id,
        type: 'workerApplication', title: 'New worker application', body: 'Worker applied',
        read: false, createdAt: client.serverTimestamp() });
    });
  }
  before(async () => {
    environment = await initializeTestEnvironment({ projectId, firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../mobile/my_app/firestore.rules'), 'utf8'),
    } });
    app = initializeApp({ projectId }, 'cleanup-emulator-tests');
    db = getFirestore(app);
  });
  beforeEach(async () => {
    await environment.clearFirestore();
    await db.collection('users').doc('client').set({ role: 'client', verificationStatus: 'pending' });
    await db.collection('users').doc('worker').set({ role: 'worker', verificationStatus: 'verified' });
  });
  after(async () => {
    await environment?.cleanup();
    await db?.terminate();
    if (app) await deleteApp(app);
  });
  test('expires an eligible root, preserves history, notifies once, and updates discovery', async () => {
    await ref('old').set(expired());
    await ref('old').collection('private').doc('location').set({ address: 'retained' });
    await db.collection('notifications').doc('old').set({ requestId: 'old' });
    assert.equal((await cleanup()).expired, 1);
    assert.equal((await ref('old').get()).data().status, 'expired');
    assert.ok((await ref('old').get()).data().expiredAt instanceof Timestamp);
    assert.equal((await ref('old').collection('private').doc('location').get()).exists, true);
    assert.equal((await db.collection('notifications').doc('old').get()).exists, true);
    const viewer = environment.authenticatedContext('client').firestore();
    for (const [field, value] of [['clientId', 'client'], ['status', 'pending']]) {
      assert.equal((await client.getDocs(client.query(client.collection(viewer, 'service_requests'), client.where(field, '==', value)))).size, field === 'clientId' ? 1 : 0);
    }
    const notification = client.doc(viewer, 'notifications', 'jobExpired_old');
    const event = await client.getDoc(notification);
    assert.equal(event.data().recipientId, 'client');
    assert.equal(event.data().requestId, 'old');
    await client.updateDoc(notification, { read: true });
    assert.equal((await cleanup()).expired, 0);
    assert.equal((await client.getDoc(notification)).data().read, true);
    await assert.rejects(apply('old'), /JOB_UNAVAILABLE/);
    const worker = environment.authenticatedContext('worker').firestore();
    await assert.rejects(client.setDoc(client.doc(worker, 'service_requests/old/applications/worker'), {
      requestId: 'old', clientId: 'client', workerId: 'worker', workerName: 'Worker',
      status: 'pending', appliedAt: client.serverTimestamp(),
    }), error => error.code === 'permission-denied');
    await assert.rejects(client.updateDoc(client.doc(viewer, 'service_requests/old'), {
      status: 'pending',
    }), error => error.code === 'permission-denied');
  });
  test('retains future, malformed, legacy and every non-pending status', async () => {
    const future = Timestamp.fromDate(new Date('2026-10-30T01:00:00Z'));
    const midnight = Timestamp.fromDate(new Date('2026-10-28T16:00:00Z'));
    const values = [expired({ schedule: future, scheduleFrom: future, scheduleTo: future }),
      expired({ scheduleFrom: 'invalid' }), expired({ schedule: midnight, scheduleFrom: midnight, scheduleTo: midnight }),
      ...['accepted', 'ongoing', 'completed', 'cancelled'].map(status => expired({ status, workerId: 'worker' }))];
    for (let i = 0; i < values.length; i++) await ref(`keep-${i}`).set(values[i]);
    assert.equal((await cleanup()).expired, 0);
    assert.equal((await db.collection('service_requests').get()).size, values.length);
  });
  test('real authorized application and notification prevent expiration cleanup', async () => {
    const start = futureSchedule();
    await ref('applied').set(scheduled(start));
    await apply('applied');
    assert.equal((await cleanup(db, new Date(start.toMillis() + 1))).skipped.has_applications, 1);
    assert.equal((await ref('applied').collection('applications').doc('worker').get()).exists, true);
    assert.equal((await db.collection('notifications').doc('application-applied').get()).exists, true);
  });
  test('an application committed between candidate scan and transactional recheck is retained', async () => {
    const start = futureSchedule();
    await ref('race').set(scheduled(start));
    let first = true;
    const wrapped = { collection: name => db.collection(name), runTransaction: async callback => {
      if (first) { first = false; await apply('race'); }
      return db.runTransaction(callback);
    } };
    const result = await cleanup(wrapped, new Date(start.toMillis() + 1));
    assert.equal(result.expired, 0);
    assert.equal(result.skipped.has_applications, 1);
    assert.equal((await ref('race').get()).exists, true);
  });
  test('overdue pending application is denied before cleanup and leaves no side effects', async () => {
    await ref('overdue').set(expired());
    await assert.rejects(apply('overdue'), error => error.code === 'permission-denied');
    assert.equal((await ref('overdue').collection('applications').get()).size, 0);
    assert.equal((await db.doc('notifications/application-overdue').get()).exists, false);
    assert.equal((await ref('overdue').get()).data().status, 'pending');
    assert.equal((await cleanup()).expired, 1);
    assert.equal((await ref('overdue').get()).data().status, 'expired');
    const notification = await db.doc('notifications/jobExpired_overdue').get();
    assert.equal(notification.data().recipientId, 'client');
    assert.equal(notification.data().requestId, 'overdue');
    assert.equal((await cleanup()).expired, 0);
    assert.equal((await db.collection('notifications').get()).size, 1);
  });
  test('cleanup winning after a worker reads the old root cannot leave an orphan application', { timeout: 60000 }, async () => {
    await ref('late').set(expired());
    let signalRead, allowCommit;
    const didRead = new Promise(resolve => { signalRead = resolve; });
    const resume = new Promise(resolve => { allowCommit = resolve; });
    const application = apply('late', async () => { signalRead(); await resume; });
    // Attach a rejection handler before any commits are allowed.
    const settled = application.then(() => 'committed', () => 'rejected');
    await didRead;
    let result;
    try { result = await cleanup(); } finally { allowCommit(); }
    const outcome = await settled;
    const root = await ref('late').get();
    const child = await ref('late').collection('applications').doc('worker').get();
    assert.ok(!child.exists || root.data().status === 'pending', 'A committed application must keep the job available');
    if (result.expired === 1) {
      assert.equal(outcome, 'rejected');
      assert.equal(child.exists, false);
      assert.equal((await db.collection('notifications').doc('application-late').get()).exists, false);
    } else {
      assert.equal(root.exists, true);
    }
  });
  test('linked conversation or live tracking retains a pending job', async () => {
    await ref('chat').set(expired());
    await db.collection('conversations').doc('conversation').set({ requestId: 'chat' });
    await ref('tracking').set(expired());
    await ref('tracking').collection('private').doc('rider_location').set({ marker: true });
    const result = await cleanup();
    assert.equal(result.expired, 0);
    assert.equal(result.skipped.linked_conversations, 1);
    assert.equal(result.skipped.tracking_record, 1);
  });
  test('concurrent cleanup processes are idempotent', async () => {
    await ref('only').set(expired());
    const runs = await Promise.all([cleanup(), cleanup()]);
    assert.equal(runs.reduce((total, run) => total + run.expired, 0), 1);
    assert.equal((await ref('only').get()).data().status, 'expired');
    assert.equal((await db.collection('notifications').where('type', '==', 'jobExpired').get()).size, 1);
  });
  test('owner can read expired details and create a normal new post; clients cannot forge expiration', async () => {
    await ref('original').set(expired());
    await cleanup();
    const viewer = environment.authenticatedContext('client').firestore();
    const original = client.doc(viewer, 'service_requests/original');
    assert.equal((await client.getDoc(original)).data().status, 'expired');
    const future = client.Timestamp.fromDate(new Date(Date.now() + 86400000));
    const newPost = { ...expired(), schedule: future, scheduleFrom: future, scheduleTo: future,
      createdAt: client.serverTimestamp() };
    await client.setDoc(client.doc(viewer, 'service_requests/reposted'), newPost);
    assert.equal((await ref('reposted').get()).data().status, 'pending');
    assert.equal((await ref('original').get()).data().status, 'expired');
    assert.equal((await ref('reposted').collection('applications').get()).size, 0);
    await assert.rejects(client.updateDoc(client.doc(viewer, 'service_requests/reposted'), {
      status: 'expired', expiredAt: client.serverTimestamp(),
    }), error => error.code === 'permission-denied');
    await assert.rejects(client.setDoc(client.doc(viewer, 'notifications/forged'), {
      recipientId: 'client', recipientRole: 'client', senderId: 'system', requestId: 'reposted',
      type: 'jobExpired', title: 'Job Post Expired', body: 'Forged', read: false,
      createdAt: client.serverTimestamp(),
    }), error => error.code === 'permission-denied');
  });

});
