const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');

describe('Admin Management with isolated Auth and Firestore emulators', { skip: process.env.RUN_ADMIN_EMULATOR_TESTS !== 'true' }, () => {
  const project = 'demo-swiftserve-admin-management';
  let sdk, db, auth, app, superToken, legacyToken, regularToken, normalToken, regularId, superId, environment;
  const password = 'LocalTestOnly-Password123!';
  const body = { fullName: 'Test Reviewer', email: 'reviewer@example.test', role: 'Reviewer',
    password, permissions: ['reports.manage'] };
  async function signIn(email) {
    const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
    const data = await response.json(); assert.equal(response.status, 200); return data.idToken;
  }
  const get = (url, token) => request(app).get(url).set('Authorization', `Bearer ${token}`);
  const patch = (url, token, data) => request(app).patch(url).set('Authorization', `Bearer ${token}`).send(data);
  async function edit(overrides) {
    const data = (await db.collection('admin_accounts').doc(regularId).get()).data();
    return { fullName: data.fullName, email: data.email, role: data.role, permissions: data.permissions,
      status: data.status, version: data.version, ...overrides };
  }
  before(async () => {
    for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) if (!/^127\.0\.0\.1:\d+$/.test(process.env[key] || '')) throw new Error('Loopback demo emulators required');
    const { initializeApp } = require('firebase-admin/app');
    sdk = initializeApp({ projectId: project }, 'admin-management-test');
    db = require('firebase-admin/firestore').getFirestore(sdk);
    auth = require('firebase-admin/auth').getAuth(sdk);
    const config = require.resolve('../src/config/firebase');
    require.cache[config] = { id: config, filename: config, loaded: true, exports: { db, auth } };
    const rulesRequire = createRequire(path.resolve(__dirname, '../../mobile/my_app/rules-tests/package.json'));
    environment = await rulesRequire('@firebase/rules-unit-testing').initializeTestEnvironment({ projectId: project,
      firestore: { rules: fs.readFileSync(path.resolve(__dirname, '../../mobile/my_app/firestore.rules'), 'utf8') } });
    for (const [email, claims] of [['super@example.test', { admin: true, superAdmin: true }], ['legacy@example.test', { admin: true }], ['normal@example.test', {}]]) {
      const user = await auth.createUser({ email, password }); await auth.setCustomUserClaims(user.uid, claims);
      if (claims.superAdmin) { superId = user.uid; superToken = await signIn(email); }
      else if (claims.admin) legacyToken = await signIn(email);
      else normalToken = await signIn(email);
    }
    app = express(); app.use(express.json());
    app.use('/api/admin/administrators', require('../src/routes/adminManagementRoutes'));
    app.use('/api/admin', require('../src/routes/adminDataRoutes'));
    app.use((error, _req, res, _next) => res.status(error.status || 500).json({ message: 'Test API error' }));
  });
  after(async () => { await environment?.cleanup(); if (sdk) await require('firebase-admin/app').deleteApp(sdk); });

  test('normal user cannot enter admin API; legacy admin retains modules but is not promoted', async () => {
    await get('/api/admin/session', normalToken).expect(403);
    const legacy = await get('/api/admin/session', legacyToken).expect(200);
    assert.equal(legacy.body.access.fullAccess, true); assert.equal(legacy.body.access.isSuperAdmin, false);
    await get('/api/admin/administrators', legacyToken).expect(403);
    await get('/api/admin/administrators', superToken).expect(200);
    const { isSuperAdmin } = require('../src/services/adminAccessService');
    assert.equal(isSuperAdmin({ uid: 'trusted', admin: true }, { SWIFTSERVE_SUPER_ADMIN_UIDS: 'trusted' }), true);
    assert.equal(isSuperAdmin({ uid: 'trusted', staff: true }, { SWIFTSERVE_SUPER_ADMIN_UIDS: 'trusted' }), false);
  });
  test('Super Admin creates an Auth-backed regular admin without broad claim or plaintext storage', async () => {
    const created = await request(app).post('/api/admin/administrators').set('Authorization', `Bearer ${superToken}`).send(body).expect(201);
    regularId = created.body.item.id;
    const user = await auth.getUser(regularId);
    assert.deepEqual(user.customClaims, { staff: true }); assert.equal(user.disabled, false);
    const record = (await db.collection('admin_accounts').doc(regularId).get()).data();
    assert.deepEqual(record.permissions, ['reports.manage', 'reports.view']);
    assert.equal(record.password, undefined);
    const logs = await db.collection('admin_audit_logs').get();
    assert.ok(logs.size >= 2); assert.ok(!JSON.stringify(logs.docs.map(doc => doc.data())).includes(password));
    regularToken = await signIn(body.email);
    await get('/api/admin/reports', regularToken).expect(200);
    await get('/api/admin/users', regularToken).expect(403);
    await get('/api/admin/bookings', regularToken).expect(403);
    await get('/api/admin/administrators', regularToken).expect(403);
    await request(app).post('/api/admin/administrators').set('Authorization', `Bearer ${regularToken}`).send(body).expect(403);
  });
  test('cannot reuse existing users, promote staff, change self or deactivate Super Admin', async () => {
    await request(app).post('/api/admin/administrators').set('Authorization', `Bearer ${superToken}`).send({ ...body, email: 'normal@example.test' }).expect(409);
    await patch(`/api/admin/administrators/${regularId}`, regularToken, await edit({ permissions: ['users.manage'] })).expect(403);
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ permissions: ['admin.manage'] })).expect(400);
    await patch(`/api/admin/administrators/${superId}`, superToken, await edit({ status: 'inactive' })).expect(400);
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ role: 'Super Admin' })).expect(400);
  });
  test('permissions refresh immediately and worker-only discovery excludes client-only records', async () => {
    await db.collection('users').doc('worker').set({ fullName: 'Worker fixture', role: 'worker' });
    await db.collection('users').doc('client').set({ fullName: 'Private client fixture', role: 'client' });
    const stale = await edit({ permissions: ['workers.view'] });
    await patch(`/api/admin/administrators/${regularId}`, superToken, stale).expect(200);
    await patch(`/api/admin/administrators/${regularId}`, superToken, stale).expect(409);
    await get('/api/admin/reports', regularToken).expect(403);
    const users = await get('/api/admin/users', regularToken).expect(200);
    assert.deepEqual(users.body.items.map(item => item.id), ['worker']);
    await patch('/api/admin/users/client', regularToken, { status: 'Suspended' }).expect(403);
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ permissions: ['dashboard.view'] })).expect(200);
    const dashboard = await get('/api/admin/overview', regularToken).expect(200);
    assert.ok(!JSON.stringify(dashboard.body).includes('Private client fixture'));
  });
  test('suspension blocks existing sessions, restoration permits a fresh login and audit history remains append-only', async () => {
    await new Promise(resolve => setTimeout(resolve, 1100));
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ status: 'suspended' })).expect(200);
    assert.equal((await auth.getUser(regularId)).disabled, true);
    await get('/api/admin/session', regularToken).expect(401);
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ status: 'active' })).expect(200);
    await get('/api/admin/session', regularToken).expect(401);
    regularToken = await signIn(body.email);
    await get('/api/admin/session', regularToken).expect(200);
    const rulesRequire = createRequire(path.resolve(__dirname, '../../mobile/my_app/rules-tests/package.json'));
    const { doc, setDoc, deleteDoc, getDoc } = rulesRequire('firebase/firestore');
    const { assertFails } = rulesRequire('@firebase/rules-unit-testing');
    const staff = environment.authenticatedContext(regularId, { staff: true }).firestore();
    await assertFails(setDoc(doc(staff, 'admin_accounts', regularId), { status: 'active', permissions: ['admin.manage'] }));
    await assertFails(getDoc(doc(staff, 'admin_accounts', regularId)));
    const log = (await db.collection('admin_audit_logs').get()).docs[0];
    await assertFails(deleteDoc(doc(staff, 'admin_audit_logs', log.id)));
    await assertFails(setDoc(doc(staff, 'admin_audit_logs', 'forged'), { actorId: regularId }));
    const audit = await get('/api/admin/administrators/audit', superToken).expect(200);
    assert.ok(audit.body.items.some(item => item.action === 'admin.status_changed'));
  });
  test('regular report actions are audited with the actor and transaction target', async () => {
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ permissions: ['reports.manage'] })).expect(200);
    await db.collection('reports').doc('report').set({ status: 'pending' });
    await patch('/api/admin/reports/report', regularToken, { status: 'Under Review', adminNotes: 'Reviewed fixture', resolution: '' }).expect(200);
    const logs = await db.collection('admin_audit_logs').where('actorId', '==', regularId).get();
    assert.ok(logs.docs.some(doc => doc.data().action === 'reports.updated' && doc.data().targetId === 'report'));
  });
  test('failed provisioning remains disabled and can be safely retried without converting an existing user', async () => {
    const original = auth.setCustomUserClaims.bind(auth);
    auth.setCustomUserClaims = async () => { throw new Error('Injected claim failure'); };
    try {
      await request(app).post('/api/admin/administrators').set('Authorization', `Bearer ${superToken}`).send({ ...body, email: 'incomplete@example.test' }).expect(500);
    } finally { auth.setCustomUserClaims = original; }
    const user = await auth.getUserByEmail('incomplete@example.test');
    assert.equal(user.disabled, true);
    assert.equal((await db.collection('admin_accounts').doc(user.uid).get()).data().status, 'provisioning');
    await request(app).post(`/api/admin/administrators/${user.uid}/complete-setup`).set('Authorization', `Bearer ${superToken}`).expect(200);
    assert.equal((await auth.getUser(user.uid)).disabled, false);
    const normal = await auth.getUserByEmail('normal@example.test');
    await request(app).post(`/api/admin/administrators/${normal.uid}/complete-setup`).set('Authorization', `Bearer ${superToken}`).expect(400);
  });
  test('failed Auth synchronization blocks access, and concurrent editors cannot overwrite a newer version', async () => {
    const original = auth.updateUser.bind(auth);
    auth.updateUser = async () => { throw new Error('Injected Auth failure'); };
    try {
      await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ role: 'Support' })).expect(503);
    } finally { auth.updateUser = original; }
    assert.equal((await db.collection('admin_accounts').doc(regularId).get()).data().status, 'inactive');
    await get('/api/admin/session', regularToken).expect(403);
    await patch(`/api/admin/administrators/${regularId}`, superToken, await edit({ status: 'active' })).expect(200);
    const version = await edit({ role: 'First editor' });
    const results = await Promise.all([
      patch(`/api/admin/administrators/${regularId}`, superToken, version),
      patch(`/api/admin/administrators/${regularId}`, superToken, { ...version, role: 'Second editor' }),
    ]);
    assert.deepEqual(results.map(result => result.status).sort(), [200, 409]);
  });
  test('own profile edits synchronize the managed directory name and invalidate stale editor versions', async () => {
    const prior = await edit();
    await patch('/api/admin/profile', regularToken, { firstName: 'Updated', lastName: 'Reviewer', phone: '+12025550110', email: body.email }).expect(200);
    const record = (await db.collection('admin_accounts').doc(regularId).get()).data();
    assert.equal(record.fullName, 'Updated Reviewer');
    assert.equal(record.version, prior.version + 1);
    const profile = await get('/api/admin/profile', regularToken).expect(200);
    assert.equal(profile.body.item.firstName, 'Updated');
    assert.equal(profile.body.item.lastName, 'Reviewer');
    await patch(`/api/admin/administrators/${regularId}`, superToken, prior).expect(409);
  });
  test('removing a trusted claim blocks Super Admin management even with a previously issued token', async () => {
    await auth.setCustomUserClaims(superId, { admin: true });
    await get('/api/admin/administrators', superToken).expect(403);
    await auth.setCustomUserClaims(superId, { admin: true, superAdmin: true });
  });
  test('removing the managed-admin claim blocks an otherwise active record and previously issued token', async () => {
    await auth.setCustomUserClaims(regularId, {});
    await get('/api/admin/session', regularToken).expect(403);
  });
});
