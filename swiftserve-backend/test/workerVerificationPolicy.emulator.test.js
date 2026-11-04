const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const path = require('node:path');
const fs = require('node:fs/promises');
const os = require('node:os');

test('worker verification policy: real Auth/Firestore emulator integration', {
  skip: process.env.RUN_WORKER_POLICY_EMULATOR_TESTS !== 'true', timeout: 120000,
}, async t => {
  const project = 'demo-swiftserve-cleanup';
  assert.equal(process.env.GCLOUD_PROJECT, project);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8187');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  if (process.env.FIREBASE_CONFIG) assert.equal(JSON.parse(process.env.FIREBASE_CONFIG).projectId, project);
  for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'K_SERVICE', 'NETLIFY', 'RENDER']) assert.ok(!process.env[key], `${key} must be absent`);
  assert.notEqual(process.env.NATIONAL_ID_MOCK_ENABLED, 'true');
  const { initializeApp, deleteApp } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');
  const { getFirestore } = require('firebase-admin/firestore');
  const instance = initializeApp({ projectId: project }, `worker-policy-${randomUUID()}`);
  const db = getFirestore(instance), auth = getAuth(instance);
  assert.equal(db.projectId, project); assert.equal(db.databaseId, '(default)');
  const config = require.resolve('../src/config/firebase');
  require.cache[config] = { id: config, filename: config, loaded: true, exports: { db, auth, storage: null } };
  const { newEvidence } = require('../src/services/workerVerificationPolicy');
  const { compareAndCreateSubmission } = require('../src/services/faceVerificationService');
  const express = require('express'), request = require('supertest');
  const app = express(); app.use(express.json());
  const uploads = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-policy-emulator-'));
  let band = 'strong';
  app.use('/api', require('../src/routes/verificationRoutes')({
    // This existing suite isolates worker policy; document fencing is exercised
    // separately in documentSuitability.emulator.test.js and the HTTP tests.
    checkDocument: async () => undefined,
    attemptLimiter: (_req, _res, next) => next(),
    compare: args => compareAndCreateSubmission({ ...args, uploadsDir: uploads, blobStorage: null,
      verify: async () => ({ match: band !== 'mismatch', band, distance: band === 'strong' ? 0.4 : band === 'borderline' ? 0.55 : 0.9,
        similarity: band === 'strong' ? 90 : band === 'borderline' ? 70 : 15, confidence: band === 'strong' ? 90 : 70 }) }),
  }));
  app.use('/review', require('../src/routes/adminVerificationRoutes'));
  const sdk = createRequire(path.resolve(__dirname, '../../mobile/my_app/rules-tests/package.json'));
  const appSdk = sdk('firebase/app'), authSdk = sdk('firebase/auth'), store = sdk('firebase/firestore');
  const clients = [];
  t.after(async () => {
    for (const client of clients) { await store.terminate(client.db); await appSdk.deleteApp(client.app); }
    await db.terminate(); await deleteApp(instance);
    // Only this invocation's generated synthetic files, never user images/backups.
    await fs.rm(uploads, { recursive: true, force: true });
  });
  async function person(role = 'worker', claims = {}) {
    const email = `policy-${randomUUID()}@example.test`, password = 'SyntheticPolicyOnly123!';
    const user = await auth.createUser({ email, password });
    if (Object.keys(claims).length) await auth.setCustomUserClaims(user.uid, claims);
    await db.collection('users').doc(user.uid).set({ uid: user.uid, role, fullName: 'Synthetic Policy User',
      dateOfBirth: '2000-01-01', verificationStatus: 'pending' });
    if (role === 'worker') await db.collection('worker_profiles').doc(user.uid).set({ workerId: user.uid, fullName: 'Synthetic Worker', verificationStatus: 'pending' });
    const clientApp = appSdk.initializeApp({ projectId: project, apiKey: 'synthetic-key', appId: 'synthetic' }, randomUUID());
    const clientAuth = authSdk.getAuth(clientApp); authSdk.connectAuthEmulator(clientAuth, 'http://127.0.0.1:9099', { disableWarnings: true });
    const signedIn = await authSdk.signInWithEmailAndPassword(clientAuth, email, password);
    const clientDb = store.getFirestore(clientApp); store.connectFirestoreEmulator(clientDb, '127.0.0.1', 8187);
    clients.push({ app: clientApp, db: clientDb });
    return { ...user, db: clientDb, token: await signedIn.user.getIdToken() };
  }
  const reviewer = await person('worker', { admin: true });
  const viewer = await person('worker', { staff: true });
  await db.collection('admin_accounts').doc(viewer.uid).set({ email: viewer.email, status: 'active', permissions: ['verification.view'] });
  const client = await person('client');
  const patch = (worker, actor = reviewer, body = { status: 'verified' }) => request(app).patch(`/review/${worker.uid}`).set('Authorization', `Bearer ${actor.token}`).send(body);
  const denied = operation => assert.rejects(operation, error => error.code === 'permission-denied');
  async function seedEvidence(worker, edit = () => {}) {
    const now = new Date(Date.now() - 1000), submissionId = randomUUID();
    const record = { ...newEvidence({ match: true, band: 'strong', distance: 0.4, similarity: 90 }, {
      workerId: worker.uid, submissionId, now, thresholds: { autoVerifyMin: 80, reviewMin: 60 },
    }), status: 'pending', storageBackend: 'local' };
    // Synthetic INTERNAL contract fixtures in a demo emulator. Not PSA responses.
    const proof = { validatedByBackend: true, environment: 'LIVE', userId: worker.uid, attemptId: submissionId,
      reference: 'synthetic-policy-fixture', validatedAt: now, expiresAt: new Date(Date.now() + 3600000) };
    record.government = { ...proof, provider: 'PSA', status: 'AUTHENTICATED' };
    record.liveness = { ...proof, provider: 'synthetic-test-provider', source: 'SERVER', status: 'PASSED' };
    record.documentBinding = { sessionId: 'synthetic-doc-session', attemptId: submissionId, sha256: 'ab'.repeat(32) };
    await db.collection('document_suitability').doc(worker.uid).set({ ownerId: worker.uid, ...record.documentBinding, status: 'DOCUMENT_ACCEPTED', expiresAt: new Date(Date.now() + 3600000) });
    edit(record); await db.collection('worker_verifications').doc(worker.uid).set(record);
    return record;
  }
  async function job() {
    const ref = db.collection('service_requests').doc();
    await ref.set({ clientId: client.uid, clientName: 'Synthetic Client', title: 'Synthetic job', category: 'Cleaning', budget: 200,
      schedule: new Date(Date.now() + 86400000), location: 'Synthetic general area', description: 'Synthetic fixture only',
      modality: 'online', status: 'pending', createdAt: new Date() });
    return ref;
  }
  const apply = (worker, jobRef) => store.setDoc(store.doc(worker.db, `service_requests/${jobRef.id}/applications/${worker.uid}`), {
    requestId: jobRef.id, clientId: client.uid, workerId: worker.uid, workerName: 'Synthetic Worker', status: 'pending', appliedAt: store.serverTimestamp(),
  });
  async function accept(worker, jobRef) {
    const batch = store.writeBatch(client.db);
    batch.update(store.doc(client.db, `service_requests/${jobRef.id}`), { status: 'accepted', workerId: worker.uid, workerName: 'Synthetic Worker', acceptedAt: store.serverTimestamp() });
    batch.update(store.doc(client.db, `service_requests/${jobRef.id}/applications/${worker.uid}`), { status: 'accepted', reviewedAt: store.serverTimestamp() });
    return batch.commit();
  }
  const discovered = async () => (await store.getDocs(store.query(store.collection(client.db, 'worker_profiles'), store.where('verificationStatus', '==', 'verified'), store.limit(30)))).docs.map(doc => doc.id);
  let approvedWorker;
  await t.test('strong/borderline/mismatch API submissions preserve scores but never grant eligibility', async () => {
    for (const outcome of ['strong', 'borderline', 'mismatch']) {
      band = outcome; const worker = await person();
      const { createCanvas } = require('canvas');
      const canvas = createCanvas(320, 320), ctx = canvas.getContext('2d'); ctx.fillStyle = '#eeeeee'; ctx.fillRect(0, 0, 320, 320);
      const bytes = canvas.toBuffer('image/png');
      const response = await request(app).post('/api/verify').set('Authorization', `Bearer ${worker.token}`)
        .field('idType', 'Synthetic document').field('idNumber', 'SYNTHETIC-NOT-AN-ID')
        .attach('document', bytes, 'synthetic.png').attach('selfie', bytes, 'synthetic-selfie.png');
      assert.equal(response.status, outcome === 'mismatch' ? 200 : 201);
      assert.equal(response.body.faceResult.status, outcome === 'strong' ? 'MATCH' : outcome === 'borderline' ? 'BORDERLINE' : 'NO_MATCH');
      assert.equal((await db.collection('users').doc(worker.uid).get()).data().verificationStatus, 'pending');
      if (outcome !== 'mismatch') {
        const record = (await db.collection('worker_verifications').doc(worker.uid).get()).data();
        assert.equal(record.workerDecision.eligible, false); assert.equal(record.status, 'pending');
      } else assert.equal((await db.collection('worker_verifications').doc(worker.uid).collection('face_attempts').get()).size, 1);
      await denied(apply(worker, await job()));
      assert.ok(!(await discovered()).includes(worker.uid));
    }
  });
  const cases = [
    ['missing government', r => { delete r.government; }],
    ['missing trusted liveness', r => { delete r.liveness; }],
    ['MOCK government', r => { r.government.provider = 'MOCK'; }],
    ['borderline face', r => { r.face.status = 'BORDERLINE'; r.face.band = 'borderline'; r.face.similarity = 70; }],
    ['failed face', r => { r.face.status = 'NO_MATCH'; r.face.band = 'mismatch'; }],
    ['expired evidence', r => { r.government.expiresAt = new Date(0); }],
    ['wrong attempt ID', r => { r.government.attemptId = 'other-attempt'; }],
    ['wrong evidence owner', r => { r.liveness.userId = 'other-user'; }],
    ['wrong record owner', r => { r.workerId = 'other-user'; }],
  ];
  for (const [name, edit] of cases) await t.test(`${name} blocks admin approval, profile writes and applications`, async () => {
    const worker = await person(); await seedEvidence(worker, edit);
    const before = (await db.collection('worker_verifications').doc(worker.uid).get()).data();
    const response = await patch(worker); assert.equal(response.status, 409);
    assert.deepEqual((await db.collection('worker_verifications').doc(worker.uid).get()).data(), before);
    assert.equal((await db.collection('users').doc(worker.uid).get()).data().verificationStatus, 'pending');
    await denied(apply(worker, await job()));
    assert.equal((await db.collection('notifications').where('recipientId', '==', worker.uid).get()).size, 0);
  });
  await t.test('complete evidence requires authorized review then enables application, acceptance and discovery', async () => {
    const worker = approvedWorker = await person(); await seedEvidence(worker);
    await patch(worker, viewer).expect(403); await patch(worker, worker).expect(403);
    await patch(worker, reviewer, { status: 'verified', government: { status: 'AUTHENTICATED' } }).expect(400);
    await patch(worker).expect(200);
    assert.equal((await db.collection('worker_verifications').doc(worker.uid).get()).data().workerDecision.eligible, true);
    assert.equal((await db.collection('users').doc(worker.uid).get()).data().verificationStatus, 'verified');
    assert.equal((await db.collection('worker_profiles').doc(worker.uid).get()).data().verificationStatus, 'verified');
    assert.equal((await db.collection('notifications').where('recipientId', '==', worker.uid).get()).size, 1);
    assert.equal((await db.collection('admin_audit_logs').where('targetId', '==', worker.uid).get()).size, 1);
    const ref = await job(); await apply(worker, ref); await accept(worker, ref);
    assert.equal((await ref.get()).data().status, 'accepted');
    assert.ok((await discovered()).includes(worker.uid));
  });
  await t.test('client writes cannot forge canonical status or evidence; private records remain owner-only', async () => {
    const worker = await person(); await seedEvidence(worker);
    for (const [target, data] of [[`users/${worker.uid}`, { verificationStatus: 'verified' }],
      [`worker_profiles/${worker.uid}`, { verificationStatus: 'verified' }],
      [`worker_verifications/${worker.uid}`, { status: 'verified', 'workerDecision.eligible': true }]]) {
      await denied(store.updateDoc(store.doc(worker.db, target), data));
    }
    await store.getDoc(store.doc(worker.db, `worker_verifications/${worker.uid}`));
    await denied(store.getDoc(store.doc(client.db, `worker_verifications/${worker.uid}`)));
    await denied(store.updateDoc(store.doc(reviewer.db, `users/${worker.uid}`), { verificationStatus: 'verified' }));
    await request(app).post('/api/verify').set('Authorization', `Bearer ${worker.token}`)
      .field('idType', 'Synthetic').field('verificationStatus', 'verified').expect(400);
    assert.equal((await db.collection('users').doc(worker.uid).get()).data().verificationStatus, 'pending');
  });
  await t.test('pending worker cannot be hired using a pre-existing application through an old client', async () => {
    const worker = await person(), ref = await job();
    await ref.collection('applications').doc(worker.uid).set({ requestId: ref.id, clientId: client.uid, workerId: worker.uid,
      workerName: 'Synthetic Worker', status: 'pending', appliedAt: new Date() });
    await denied(accept(worker, ref));
    assert.equal((await ref.get()).data().status, 'pending');
  });
  await t.test('suspended accountStatus blocks policy approval and new legacy applications/hiring', async () => {
    const worker = await person(); await seedEvidence(worker);
    await db.collection('users').doc(worker.uid).update({ accountStatus: 'suspended' });
    await patch(worker).expect(409);
    // Existing verified compatibility status is not sufficient while suspended.
    await db.collection('users').doc(worker.uid).update({ verificationStatus: 'verified' });
    await db.collection('worker_profiles').doc(worker.uid).update({ verificationStatus: 'verified' });
    // Current public discovery lacks the private accountStatus projection. This
    // is a display gap, not authority to apply/hire; record it for the UI phase.
    assert.ok((await discovered()).includes(worker.uid));
    const ref = await job(); await denied(apply(worker, ref));
    await ref.collection('applications').doc(worker.uid).set({ requestId: ref.id, clientId: client.uid, workerId: worker.uid,
      workerName: 'Synthetic Worker', status: 'pending', appliedAt: new Date() });
    await denied(accept(worker, ref));
    assert.equal((await ref.get()).data().status, 'pending');
  });
  await t.test('legacy verified workers remain eligible; already booked work can continue without reapproval', async () => {
    const legacy = await person();
    await db.collection('users').doc(legacy.uid).update({ verificationStatus: 'verified' });
    await db.collection('worker_profiles').doc(legacy.uid).update({ verificationStatus: 'verified' });
    await db.collection('worker_verifications').doc(legacy.uid).set({ status: 'verified', reviewedBy: 'auto_face_match' });
    const before = (await db.collection('worker_verifications').doc(legacy.uid).get()).data();
    const ref = await job(); await apply(legacy, ref); await accept(legacy, ref);
    await patch(legacy).expect(409);
    assert.deepEqual((await db.collection('worker_verifications').doc(legacy.uid).get()).data(), before);
    assert.ok((await discovered()).includes(legacy.uid));
    const booked = await job(); await booked.update({ status: 'accepted', workerId: approvedWorker.uid, workerName: 'Synthetic Worker', acceptedAt: new Date() });
    // Simulate a later pending state only on our synthetic fixture, not a migration.
    await db.collection('users').doc(approvedWorker.uid).update({ verificationStatus: 'pending' });
    await store.updateDoc(store.doc(approvedWorker.db, `service_requests/${booked.id}`), { status: 'ongoing', ongoingAt: store.serverTimestamp() });
    assert.equal((await booked.get()).data().status, 'ongoing');
  });
});
