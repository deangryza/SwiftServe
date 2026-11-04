const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const path = require('node:path');

test('real emulator tokens, metadata transactions, review permissions and denied client writes', { skip: process.env.RUN_NATIONAL_ID_EMULATOR_TESTS !== 'true' }, async () => {
  const project = 'demo-swiftserve-cleanup';
  const { localTarget, CONSENT_VERSION } = require('../src/identity/policy');
  const env = { ...process.env, NATIONAL_ID_MOCK_ENABLED: 'true', GCLOUD_PROJECT: project };
  // emulators:exec supplies an SDK hint; validate it, then remove that hint from
  // the service's strict local launcher contract. The process SDK stays demo-only.
  if (env.FIREBASE_CONFIG) {
    assert.equal(JSON.parse(env.FIREBASE_CONFIG).projectId, project);
    delete env.FIREBASE_CONFIG;
  }
  localTarget({ projectId: project, databaseId: '(default)' }, env);
  const { initializeApp: adminApp } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  const { getAuth } = require('firebase-admin/auth');
  const admin = adminApp({ projectId: project }, `identity-${randomUUID()}`), db = getFirestore(admin), auth = getAuth(admin);
  const suffix = randomUUID(), password = 'SyntheticIdentityOnly123!';
  async function person(role, claims = {}) {
    const user = await auth.createUser({ email: `${role}-${suffix}@example.test`, password });
    if (Object.keys(claims).length) await auth.setCustomUserClaims(user.uid, claims);
    await db.collection('users').doc(user.uid).set({ fullName: 'Synthetic Identity Test', role: role === 'worker' ? 'worker' : 'client', dateOfBirth: '2000-01-01', verificationStatus: 'pending' });
    const response = await fetch(`http://${env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=synthetic-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: user.email, password, returnSecureToken: true }),
    });
    assert.equal(response.status, 200);
    return { ...user, token: (await response.json()).idToken };
  }
  const user = await person('worker'), reviewer = await person('reviewer', { admin: true }), staff = await person('staff', { staff: true });
  await db.collection('admin_accounts').doc(staff.uid).set({ status: 'active', email: staff.email, fullName: 'Synthetic Viewer', role: 'Reviewer', permissions: ['verification.view'] });
  const config = require.resolve('../src/config/firebase');
  require.cache[config] = { id: config, filename: config, loaded: true, exports: { db, auth } };
  const { IdentityService } = require('../src/identity/service');
  const { MockPSAProvider } = require('../src/identity/provider');
  const service = new IdentityService({ db, env, provider: new MockPSAProvider('manual_review'),
    face: async () => ({ outcome: 'PASSED' }), liveness: async () => ({ outcome: 'PASSED' }) });
  const express = require('express'), request = require('supertest');
  const app = express(); app.use(express.json());
  const routers = require('../src/routes/nationalIdRoutes').createIdentityRouters({ db, auth, admin: require('../src/middleware/adminMiddleware'), service });
  app.use('/identity', routers.user); app.use('/review', routers.review);
  const create = await request(app).post('/identity/sessions').set('Authorization', `Bearer ${user.token}`).send({ requestId: `synthetic-${suffix}` }).expect(201);
  const id = create.body.verificationReference;
  const duplicate = await service.create(user.uid, `synthetic-${suffix}`);
  assert.equal(duplicate.verificationReference, id);
  await request(app).post(`/identity/sessions/${id}/consent`).set('Authorization', `Bearer ${user.token}`).send({ consent: true, consentVersion: CONSENT_VERSION }).expect(200);
  const { createCanvas } = require('canvas');
  const canvas = createCanvas(320, 320), ctx = canvas.getContext('2d'); ctx.fillStyle = '#eeeeee'; ctx.fillRect(0, 0, 320, 320); ctx.fillStyle = '#222222'; ctx.fillRect(0, 0, 160, 320);
  const bytes = canvas.toBuffer('image/png');
  const uploaded = await request(app).post(`/identity/sessions/${id}/submit`).set('Authorization', `Bearer ${user.token}`)
    .field('documentFormat', 'physical_image').attach('document', bytes, 'synthetic.png').attach('selfie', bytes, 'synthetic-selfie.png').expect(200);
  assert.equal(uploaded.body.verificationStatus, 'MANUAL_REVIEW');
  await request(app).get('/review/sessions').set('Authorization', `Bearer ${staff.token}`).expect(200);
  await request(app).patch(`/review/sessions/${id}`).set('Authorization', `Bearer ${staff.token}`).send({ decision: 'approve', reasonCode: 'CHECKS_REVIEWED' }).expect(403);
  await request(app).patch(`/review/sessions/${id}`).set('Authorization', `Bearer ${reviewer.token}`).send({ decision: 'approve', reasonCode: 'CHECKS_REVIEWED' }).expect(200);
  assert.equal((await service.get(user.uid, id)).officiallyVerified, false);
  assert.equal((await db.collection('users').doc(user.uid).get()).data().verificationStatus, 'pending');

  // Real Firestore transaction fencing after an interrupted/stale execution.
  let time = Date.now(), release, started;
  const entered = new Promise(resolve => { started = resolve; });
  const firstWorker = new IdentityService({ db, env, clock: () => time, provider: new MockPSAProvider('success'),
    face: async () => { started(); await new Promise(resolve => { release = resolve; }); return { outcome: 'PASSED' }; },
    liveness: async () => ({ outcome: 'PASSED' }) });
  const otherWorker = new IdentityService({ db, env, clock: () => time, provider: new MockPSAProvider('success'),
    face: async () => ({ outcome: 'PASSED' }), liveness: async () => ({ outcome: 'PASSED' }) });
  const resumed = await firstWorker.create(user.uid, `takeover-${suffix}`), resumeId = resumed.verificationReference;
  await firstWorker.consent(user.uid, resumeId, CONSENT_VERSION);
  const file = () => ({ buffer: Buffer.from(bytes), mimetype: 'image/png' });
  const pending = firstWorker.submit(user.uid, resumeId, file(), file(), 'physical_image');
  await entered;
  await assert.rejects(otherWorker.submit(user.uid, resumeId, file(), file(), 'physical_image'), { code: 'PROCESSING' });
  time += 121000;
  assert.equal((await otherWorker.submit(user.uid, resumeId, file(), file(), 'physical_image')).verificationStatus, 'VERIFIED');
  release(); await assert.rejects(pending, { code: 'LEASE_LOST' });
  assert.equal((await otherWorker.get(user.uid, resumeId)).attempts, 2);

  // Load existing client SDK dependencies. These exercise unchanged emulator rules.
  const sdk = createRequire(path.resolve(__dirname, '../../mobile/my_app/rules-tests/package.json'));
  const clientApp = sdk('firebase/app').initializeApp({ projectId: project, apiKey: 'synthetic-key', appId: 'synthetic' }, `identity-client-${suffix}`);
  const authSdk = sdk('firebase/auth'), fsSdk = sdk('firebase/firestore');
  const clientAuth = authSdk.getAuth(clientApp); authSdk.connectAuthEmulator(clientAuth, `http://${env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  await authSdk.signInWithEmailAndPassword(clientAuth, user.email, password);
  const clientDb = fsSdk.getFirestore(clientApp), [host, port] = env.FIRESTORE_EMULATOR_HOST.split(':');
  fsSdk.connectFirestoreEmulator(clientDb, host, Number(port));
  for (const operation of [
    () => fsSdk.getDoc(fsSdk.doc(clientDb, `_identityVerificationSessions/${id}`)),
    () => fsSdk.setDoc(fsSdk.doc(clientDb, `_identityVerificationSessions/${id}`), { verificationStatus: 'VERIFIED' }),
    () => fsSdk.setDoc(fsSdk.doc(clientDb, `users/${user.uid}`), { verificationStatus: 'verified' }, { merge: true }),
    () => fsSdk.getDoc(fsSdk.doc(clientDb, `_identityVerificationAudit/${id}-1`)),
  ]) await assert.rejects(operation(), error => error.code === 'permission-denied');
  await auth.updateUser(user.uid, { disabled: true });
  await request(app).get(`/identity/sessions/${id}`).set('Authorization', `Bearer ${user.token}`).expect(401);
  await fsSdk.terminate(clientDb); await sdk('firebase/app').deleteApp(clientApp);
  await db.terminate(); await require('firebase-admin/app').deleteApp(admin);
});
