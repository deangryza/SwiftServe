const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { createCanvas } = require('canvas');
const { IdentityService, COLLECTION } = require('../src/identity/service');
const { MockPSAProvider, IdentityProvider } = require('../src/identity/provider');
const { CONSENT_VERSION, localTarget, validateImages, tensorflowFace } = require('../src/identity/policy');
const { createIdentityRouters } = require('../src/routes/nationalIdRoutes');
function fixture(overrides = {}) {
  const env = { NATIONAL_ID_MOCK_ENABLED: 'true', GCLOUD_PROJECT: 'demo-swiftserve-identity', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8187', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' };
  const data = new Map(), clock = { now: Date.parse('2026-11-03T04:00:00Z') };
  data.set('users/client', { role: 'client', dateOfBirth: '2000-01-01', verificationStatus: 'not_required' });
  data.set('users/worker', { role: 'worker', dateOfBirth: '2000-01-01', verificationStatus: 'pending' });
  let tail = Promise.resolve();
  const doc = path => ({ path, get: async () => ({ data: () => data.get(path) }) });
  const db = { projectId: env.GCLOUD_PROJECT, databaseId: '(default)',
    collection: name => ({
      doc: id => doc(`${name}/${id}`),
      where: (field, _op, value) => {
        let cursor = '', maximum = 25;
        const query = {
          orderBy: () => query,
          startAfter: value => { cursor = value; return query; },
          limit: size => { maximum = size; return query; },
          get: async () => ({ docs: [...data].filter(([path, item]) => path.startsWith(`${name}/`) && item[field] === value && path.split('/')[1] > cursor)
            .sort(([a], [b]) => a.localeCompare(b)).slice(0, maximum).map(([, item]) => ({ data: () => item })) }),
        };
        return query;
      },
    }),
    runTransaction(callback) {
      const promise = tail.then(async () => {
        const pending = [];
        const result = await callback({ get: ref => ref.get(), set: (ref, value) => pending.push([ref.path, value]) });
        for (const [key, value] of pending) data.set(key, value);
        return result;
      });
      tail = promise.catch(() => {}); return promise;
    },
  };
  const service = new IdentityService({ db, env, clock: () => clock.now, provider: new MockPSAProvider('success'),
    face: async () => ({ outcome: 'PASSED' }), liveness: async () => ({ outcome: 'PASSED' }), ...overrides });
  return { db, data, clock, env, service };
}
const image = () => {
  const canvas = createCanvas(320, 320), c = canvas.getContext('2d');
  c.fillStyle = '#eeeeee'; c.fillRect(0, 0, 320, 320);
  c.fillStyle = '#222222'; c.fillRect(0, 0, 160, 320);
  return { mimetype: 'image/png', buffer: canvas.toBuffer('image/png') };
};
async function ready(service, uid = 'client', key = 'synthetic-request-0001') {
  const session = await service.create(uid, key);
  await service.consent(uid, session.verificationReference, CONSENT_VERSION);
  return session.verificationReference;
}
const submit = (s, id, uid = 'client') => s.submit(uid, id, image(), image(), 'physical_image');
test('mock interface contains no PSA endpoint and refuses unimplemented real provider', async () => {
  await assert.rejects(new IdentityProvider().authenticate());
  assert.throws(() => new MockPSAProvider('invented'));
});
test('disabled, production, unknown project, remote emulator and cloud environments fail closed', () => {
  const f = fixture(); localTarget(f.db, f.env);
  for (const patch of [{ NATIONAL_ID_MOCK_ENABLED: 'false' }, { GCLOUD_PROJECT: 'swiftserve-production' }, { FIRESTORE_EMULATOR_HOST: 'remote:8187' }, { FIREBASE_AUTH_EMULATOR_HOST: '' }, { GOOGLE_APPLICATION_CREDENTIALS: 'key.json' }, { NETLIFY: 'true' }]) {
    assert.throws(() => localTarget(f.db, { ...f.env, ...patch }));
  }
  assert.throws(() => localTarget({ ...f.db, projectId: 'swiftserve-staging-2026' }, f.env));
});
test('both roles require server-owned adult birthday and consent before processing', async () => {
  const f = fixture();
  for (const uid of ['client', 'worker']) {
    f.data.set(`users/${uid}`, { role: uid, dateOfBirth: '2010-01-01' });
    await assert.rejects(f.service.create(uid, 'synthetic-request-0001'), { code: 'UNDERAGE_REGISTRATION' });
    f.data.set(`users/${uid}`, { role: uid, dateOfBirth: '2008-11-03' });
    const item = await f.service.create(uid, 'synthetic-request-0001');
    await assert.rejects(submit(f.service, item.verificationReference, uid), { code: 'CONSENT_REQUIRED' });
    await assert.rejects(f.service.consent(uid, item.verificationReference, 'old-notice'), { code: 'CONSENT_VERSION_REQUIRED' });
  }
});
for (const [scenario, expected] of [['success', 'VERIFIED'], ['failed', 'REJECTED'], ['expired', 'EXPIRED'], ['manual_review', 'MANUAL_REVIEW'], ['unavailable', 'FAILED']]) {
  test(`synthetic ${scenario} outcome is always MOCK and never changes profile trust`, async () => {
    const f = fixture({ provider: new MockPSAProvider(scenario) });
    const before = { ...f.data.get('users/client') }, id = await ready(f.service);
    const result = await submit(f.service, id);
    assert.equal(result.verificationStatus, expected);
    assert.equal(result.providerType, 'MOCK'); assert.equal(result.officiallyVerified, false);
    assert.match(result.label, /NOT OFFICIALLY VERIFIED/);
    assert.deepEqual(f.data.get('users/client'), before);
    const record = f.data.get(`${COLLECTION}/${id}`);
    for (const key of ['document', 'selfie', 'idNumber', 'fullName', 'dateOfBirth', 'descriptor']) assert.equal(record[key], undefined);
  });
}
test('face mismatch, liveness failure and unsupported checks cannot verify', async () => {
  for (const [face, liveness, expected] of [['FAILED', 'PASSED', 'REJECTED'], ['PASSED', 'FAILED', 'REJECTED'], ['UNAVAILABLE', 'UNSUPPORTED', 'MANUAL_REVIEW']]) {
    const f = fixture({ face: async () => ({ outcome: face }), liveness: async () => ({ outcome: liveness }) });
    assert.equal((await submit(f.service, await ready(f.service))).verificationStatus, expected);
  }
  assert.equal((await tensorflowFace(image(), image(), {})).outcome, 'UNAVAILABLE');
});

test('TensorFlow adapter uses only the read-only comparator and maps its result bands', async () => {
  const modulePath = require.resolve('../src/services/faceVerificationService');
  const previous = require.cache[modulePath];
  let verdict, calls = 0;
  require.cache[modulePath] = { id: modulePath, filename: modulePath, loaded: true, exports: {
    verifyFaces: async (document, selfie) => {
      assert.ok(Buffer.isBuffer(document)); assert.ok(Buffer.isBuffer(selfie));
      calls++; return verdict;
    },
    compareAndCreateSubmission: () => { throw new Error('Trust writer must never be called'); },
  } };
  try {
    for (const [band, expected] of [['strong', 'PASSED'], ['borderline', 'MANUAL_REVIEW'], ['mismatch', 'FAILED']]) {
      verdict = { band, match: band !== 'mismatch' };
      assert.equal((await tensorflowFace(image(), image(), { NATIONAL_ID_FACE_COMPARISON_ENABLED: 'true' })).outcome, expected);
    }
    assert.equal(calls, 3);
  } finally {
    if (previous) require.cache[modulePath] = previous;
    else delete require.cache[modulePath];
  }
});
test('duplicate creation, unavailable retries and terminal resubmission are idempotent', async () => {
  const f = fixture({ provider: new MockPSAProvider('unavailable') });
  const id = await ready(f.service);
  assert.equal((await f.service.create('client', 'synthetic-request-0001')).verificationReference, id);
  assert.equal((await submit(f.service, id)).retryable, true);
  f.service.provider = new MockPSAProvider('success');
  assert.equal((await submit(f.service, id)).verificationStatus, 'VERIFIED');
  assert.equal((await submit(f.service, id)).attempts, 2);
  assert.equal([...f.data.keys()].filter(key => key.startsWith(`${COLLECTION}/`)).length, 1);
});
test('expired consent/session cannot proceed and session ownership is enforced', async () => {
  const f = fixture(), id = await ready(f.service);
  await assert.rejects(f.service.get('worker', id), { code: 'SESSION_NOT_FOUND' });
  f.clock.now += 11 * 60 * 1000;
  assert.equal((await f.service.get('client', id)).verificationStatus, 'EXPIRED');
  await assert.rejects(f.service.consent('client', id, CONSENT_VERSION), { code: 'SESSION_EXPIRED' });
});
test('interrupted processing is recoverable on refresh and repeated unavailable calls are bounded', async () => {
  const f = fixture({ provider: new MockPSAProvider('unavailable') }), id = await ready(f.service);
  for (let attempt = 1; attempt <= 3; attempt++) {
    const result = await submit(f.service, id);
    assert.equal(result.attempts, attempt); assert.equal(result.retryable, attempt < 3);
  }
  await assert.rejects(submit(f.service, id), { code: 'RETRY_LIMIT' });
  const other = fixture(), oid = await ready(other.service);
  const key = `${COLLECTION}/${oid}`;
  const { Timestamp } = require('firebase-admin/firestore');
  other.data.set(key, { ...other.data.get(key), verificationStatus: 'PROCESSING', attempts: 1,
    fence: 1, leaseOwner: 'old-worker', leaseUntil: Timestamp.fromMillis(other.clock.now - 1) });
  assert.equal((await other.service.get('client', oid)).retryable, true);
  assert.equal((await submit(other.service, oid)).verificationStatus, 'VERIFIED');
});
test('concurrent execution and stale takeover cannot overwrite newer results', async () => {
  let release, started; const entered = new Promise(resolve => { started = resolve; });
  let calls = 0;
  const f = fixture({ face: async () => {
    if (++calls === 1) { started(); await new Promise(resolve => { release = resolve; }); }
    return { outcome: 'PASSED' };
  } });
  const id = await ready(f.service), first = submit(f.service, id);
  await entered;
  await assert.rejects(submit(f.service, id), { code: 'PROCESSING' });
  f.clock.now += 121000;
  assert.equal((await submit(f.service, id)).verificationStatus, 'VERIFIED');
  release(); await assert.rejects(first, { code: 'LEASE_LOST' });
  assert.equal((await f.service.get('client', id)).attempts, 2);
});
test('manual review requires complete checks, forbids self-review and appends protected audit', async () => {
  const f = fixture({ provider: new MockPSAProvider('manual_review') }), id = await ready(f.service);
  await submit(f.service, id);
  assert.equal((await f.service.list()).items.length, 1);
  await assert.rejects(f.service.review(id, 'client', 'approve', 'CHECKS_REVIEWED'), { code: 'SELF_REVIEW_FORBIDDEN' });
  assert.equal((await f.service.review(id, 'reviewer', 'approve', 'CHECKS_REVIEWED')).verificationStatus, 'VERIFIED');
  assert.equal([...f.data.keys()].filter(key => key.startsWith('_identityVerificationAudit/')).length, 1);
  await assert.rejects(f.service.review(id, 'reviewer', 'reject', 'INCONSISTENT_EVIDENCE'), { code: 'REVIEW_UNAVAILABLE' });
  const other = fixture({ liveness: async () => ({ outcome: 'UNSUPPORTED' }) }), oid = await ready(other.service);
  await submit(other.service, oid);
  await assert.rejects(other.service.review(oid, 'reviewer', 'approve', 'CHECKS_REVIEWED'), { code: 'REQUIRED_CHECKS_MISSING' });
  assert.equal((await other.service.review(oid, 'reviewer', 'reject', 'UNSUPPORTED_CHECKS')).verificationStatus, 'REJECTED');
});
test('expired review pages cannot starve later valid sessions', async () => {
  const f = fixture(), id = await ready(f.service), template = f.data.get(`${COLLECTION}/${id}`);
  const { Timestamp } = require('firebase-admin/firestore');
  for (let i = 1; i <= 27; i++) {
    const reference = `mock-v1-${i.toString(16).padStart(64, '0')}`;
    f.data.set(`${COLLECTION}/${reference}`, { ...template, verificationReference: reference,
      verificationStatus: 'MANUAL_REVIEW', expiresAt: Timestamp.fromMillis(f.clock.now + (i <= 25 ? -1 : 60000)) });
  }
  const first = await f.service.list(); assert.equal(first.items.length, 0); assert.ok(first.nextCursor);
  const next = await f.service.list(first.nextCursor); assert.equal(next.items.length, 2); assert.equal(next.nextCursor, null);
  await assert.rejects(f.service.list('../users'), { code: 'INVALID_CURSOR' });
});
test('image headers, full decoding, dimensions and low contrast are independently checked', async () => {
  await validateImages(image(), image());
  const blank = { mimetype: 'image/png', buffer: createCanvas(320, 320).toBuffer('image/png') };
  await assert.rejects(validateImages(blank, image()), { code: 'IMAGE_QUALITY' });
  await assert.rejects(validateImages({ mimetype: 'image/png', buffer: Buffer.alloc(2_000_000) }, image()));
  await assert.rejects(validateImages({ mimetype: 'image/jpeg', buffer: image().buffer }, image()));
});
test('HTTP enforces token revocation, field allowlists, upload ownership and review permissions', async () => {
  const f = fixture(), app = express(); app.use(express.json());
  const auth = { verifyIdToken: async (token, revoked) => { assert.equal(revoked, true); if (['revoked', 'disabled'].includes(token)) throw new Error('invalid'); return { uid: token }; } };
  const admin = async (req, res, next) => {
    if (req.headers.authorization !== 'Bearer reviewer') return res.sendStatus(403);
    req.user = { uid: 'reviewer' }; next();
  };
  admin.permission = permission => (req, res, next) => req.headers['x-test-permission'] === permission ? next() : res.sendStatus(403);
  const routers = createIdentityRouters({ db: f.db, auth, admin, service: f.service, limiter: (_req, _res, next) => next() });
  app.use('/identity', routers.user); app.use('/review', routers.review);
  await request(app).post('/identity/sessions').send({ requestId: 'synthetic-request-0001' }).expect(401);
  for (const token of ['revoked', 'disabled']) await request(app).post('/identity/sessions').set('Authorization', `Bearer ${token}`).send({ requestId: 'synthetic-request-0001' }).expect(401);
  await request(app).post('/identity/sessions').set('Authorization', 'Bearer client').send({ requestId: 'synthetic-request-0001', verificationStatus: 'VERIFIED' }).expect(400);
  const response = await request(app).post('/identity/sessions').set('Authorization', 'Bearer client').send({ requestId: 'synthetic-request-0001' }).expect(201);
  const id = response.body.verificationReference;
  await request(app).get(`/identity/sessions/${id}`).set('Authorization', 'Bearer worker').expect(404);
  await request(app).post(`/identity/sessions/${id}/submit`).set('Authorization', 'Bearer client').expect(403);
  await request(app).post(`/identity/sessions/${id}/consent`).set('Authorization', 'Bearer client').send({ consent: true, consentVersion: CONSENT_VERSION }).expect(200);
  const uploaded = await request(app).post(`/identity/sessions/${id}/submit`).set('Authorization', 'Bearer client')
    .field('documentFormat', 'digital_image').attach('document', image().buffer, { filename: 'synthetic.png', contentType: 'image/png' })
    .attach('selfie', image().buffer, { filename: 'synthetic-selfie.png', contentType: 'image/png' }).expect(200);
  assert.equal(uploaded.body.verificationStatus, 'VERIFIED');
  await request(app).get('/review/sessions').set('Authorization', 'Bearer client').expect(403);
  await request(app).get('/review/sessions').set('Authorization', 'Bearer reviewer').expect(403);
  await request(app).get('/review/sessions').set('Authorization', 'Bearer reviewer').set('x-test-permission', 'verification.view').expect(200);
  f.env.NATIONAL_ID_MOCK_ENABLED = 'false';
  await request(app).post('/identity/sessions').send({}).expect(503);
});
module.exports = { fixture, ready, image };
