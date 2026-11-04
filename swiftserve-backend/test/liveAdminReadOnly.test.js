const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validate, readOnly, APPROVED_ADMIN_UID } = require('../src/config/liveAdminReadOnly');
const env = () => ({ SWIFTSERVE_LIVE_READ_ONLY: 'true', FIREBASE_PROJECT_ID: 'swiftserve-production', FIRESTORE_DATABASE_ID: '(default)',
  SWIFTSERVE_NETLIFY_PILOT: 'false', SWIFTSERVE_STAGING: 'false', EXPIRED_JOB_CLEANUP_ENABLED: 'false', PUSH_DELIVERY_ENABLED: 'false',
  ACTIVITY_PUSH_ENABLED: 'false', EXPIRY_PUSH_ENABLED: 'false', EXPIRED_JOB_CLEANUP_DRY_RUN: 'true' });
test('live viewer pins exact project/default database and keeps gates disabled', () => {
  validate(env());
  for (const patch of [{ FIREBASE_PROJECT_ID: 'swiftserver-production' }, { FIRESTORE_DATABASE_ID: 'other' },
    { PUSH_DELIVERY_ENABLED: 'true' }, { EXPIRED_JOB_CLEANUP_DRY_RUN: 'false' }, { SWIFTSERVE_SUPER_ADMIN_UIDS: 'someone' },
    { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8288' }, { NODE_TLS_REJECT_UNAUTHORIZED: '0' }]) {
    assert.throws(() => validate({ ...env(), ...patch }));
  }
});
test('live viewer blocks every mutation method before route handling', () => {
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']) {
    let code; let next = false;
    const res = { setHeader() {}, status(value) { code = value; return this; }, json() {} };
    readOnly({ method }, res, () => { next = true; });
    assert.equal(code, 403); assert.equal(next, false);
  }
  let next = false;
  readOnly({ method: 'GET' }, { setHeader() {} }, () => { next = true; });
  assert.equal(next, true);
});
test('only the approved existing UID can be allowlisted in the live viewer', () => {
  validate({ ...env(), SWIFTSERVE_SUPER_ADMIN_UIDS: APPROVED_ADMIN_UID });
  for (const value of ['other', APPROVED_ADMIN_UID + ',other', APPROVED_ADMIN_UID + ',']) {
    assert.throws(() => validate({ ...env(), SWIFTSERVE_SUPER_ADMIN_UIDS: value }));
  }
});
test('creation activation requires the approved Super Admin and rejects malformed gates', () => {
  assert.throws(() => validate({ ...env(), SWIFTSERVE_LIVE_ADMIN_CREATION: 'true' }));
  assert.throws(() => validate({ ...env(), SWIFTSERVE_LIVE_ADMIN_CREATION: 'yes' }));
  validate({ ...env(), SWIFTSERVE_SUPER_ADMIN_UIDS: APPROVED_ADMIN_UID, SWIFTSERVE_LIVE_ADMIN_CREATION: 'true' });
});
test('creation boundary allows only exact create/recovery routes and preserves all other write blocks', () => {
  const enabled = { ...env(), SWIFTSERVE_SUPER_ADMIN_UIDS: APPROVED_ADMIN_UID, SWIFTSERVE_LIVE_ADMIN_CREATION: 'true' };
  const check = (method, path, settings = enabled) => {
    let next = false;
    readOnly({ method, path }, { setHeader() {}, status() { return this; }, json() {} }, () => { next = true; }, settings);
    return next;
  };
  for (const path of ['/api/admin/administrators', '/api/admin/administrators/', '/api/admin/administrators/generatedUid/complete-setup']) {
    assert.equal(check('POST', path), true);
    assert.equal(check('POST', path, env()), false);
    for (const method of ['PATCH', 'PUT', 'DELETE']) assert.equal(check(method, path), false);
  }
  for (const path of ['/api/admin/profile', '/api/admin/administrators/audit', '/api/admin/users',
    '/api/admin/administrators/id', '/api/admin/administrators/id/complete-setup/extra',
    '/api/admin/administrators/../complete-setup', '/api/admin/administrators/%2F/complete-setup']) {
    assert.equal(check('POST', path), false);
  }
});
test('current authenticated account is recognized as Super Admin without changing claims', async () => {
  const previous = process.env.SWIFTSERVE_SUPER_ADMIN_UIDS;
  const configPath = require.resolve('../src/config/firebase');
  const cached = require.cache[configPath];
  let uid = APPROVED_ADMIN_UID;
  let disabled = false;
  let admin = true;
  let checkedRevocation = false;
  require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: {
    db: {}, auth: {
      async verifyIdToken(_token, revoked) { checkedRevocation ||= revoked === true; return { uid, admin: true }; },
      async getUser() { return { uid, disabled, customClaims: { admin } }; },
    },
  } };
  try {
    process.env.SWIFTSERVE_SUPER_ADMIN_UIDS = APPROVED_ADMIN_UID;
    const middleware = require('../src/middleware/adminMiddleware');
    const run = async () => {
      const req = { headers: { authorization: 'Bearer synthetic-test-token' } };
      let code; let allowed = false;
      const res = { status(value) { code = value; return this; }, json() {}, sendStatus(value) { code = value; } };
      await middleware[0](req, res, async () => {});
      await middleware[1](req, res, () => {});
      middleware.superAdmin(req, res, () => { allowed = true; });
      return { req, code, allowed };
    };
    const approved = await run();
    assert.equal(approved.req.adminAccess.isSuperAdmin, true);
    assert.equal(approved.allowed, true);
    assert.equal(checkedRevocation, true);
    uid = 'different-legacy-admin';
    assert.equal((await run()).allowed, false);
    uid = APPROVED_ADMIN_UID; disabled = true;
    assert.equal((await run()).allowed, false);
    disabled = false; admin = false;
    assert.equal((await run()).allowed, false);
    admin = true;
    const express = require('express');
    const request = require('supertest');
    const app = express();
    const enabled = { ...env(), SWIFTSERVE_SUPER_ADMIN_UIDS: APPROVED_ADMIN_UID, SWIFTSERVE_LIVE_ADMIN_CREATION: 'true' };
    app.use((req, res, next) => readOnly(req, res, next, enabled));
    // Synthetic terminal handler: exercise the real authentication and authorization
    // middleware without creating any Firebase account or document.
    app.post('/api/admin/administrators', ...middleware, middleware.superAdmin, (_req, res) => res.status(201).json({ synthetic: true }));
    await request(app).post('/api/admin/administrators').expect(401);
    await request(app).post('/api/admin/administrators').set('Authorization', 'Bearer synthetic-test-token').expect(201);
    uid = 'another-admin';
    await request(app).post('/api/admin/administrators').set('Authorization', 'Bearer synthetic-test-token').expect(403);
    uid = APPROVED_ADMIN_UID; disabled = true;
    await request(app).post('/api/admin/administrators').set('Authorization', 'Bearer synthetic-test-token').expect(403);
    await request(app).patch('/api/admin/administrators/another-admin').expect(403);
  } finally {
    if (previous === undefined) delete process.env.SWIFTSERVE_SUPER_ADMIN_UIDS;
    else process.env.SWIFTSERVE_SUPER_ADMIN_UIDS = previous;
    if (cached) require.cache[configPath] = cached;
    else delete require.cache[configPath];
  }
});
