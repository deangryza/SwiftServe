const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { newEvidence } = require('../src/services/workerVerificationPolicy');
let records, writes;
const db = {
  projectId: 'demo-swiftserve-cleanup', databaseId: '(default)',
  collection: name => ({ doc: (id = 'synthetic-notice') => ({ name, id,
    get: async () => ({ exists: records.has(`${name}/${id}`), data: () => records.get(`${name}/${id}`) }),
  }) }),
  async runTransaction(callback) {
    const staged = [];
    const result = await callback({ get: ref => ref.get(),
      set: (ref, data, options) => staged.push({ ref, data, options }),
      update: (ref, data) => staged.push({ ref, data, options: { merge: true } }),
    });
    for (const write of staged) {
      const key = `${write.ref.name}/${write.ref.id}`;
      records.set(key, write.options?.merge ? { ...records.get(key), ...write.data } : write.data);
    }
    writes.push(...staged); return result;
  },
};
const config = require.resolve('../src/config/firebase');
require.cache[config] = { id: config, filename: config, loaded: true, exports: { db, storage: null,
  auth: {
    verifyIdToken: async token => {
      if (!['reviewer', 'worker', 'viewer', 'self'].includes(token)) throw new Error('Invalid synthetic token');
      return { uid: token === 'self' ? 'worker' : token, admin: ['reviewer', 'self'].includes(token), staff: token === 'viewer' };
    },
    getUser: async uid => ({ uid, disabled: false, email: `${uid}@example.test`,
      customClaims: { admin: uid === 'reviewer' || uid === 'worker', staff: uid === 'viewer' } }),
  },
} };
const app = express(); app.use(express.json());
app.use('/review', require('../src/routes/adminVerificationRoutes'));
beforeEach(() => {
  writes = []; records = new Map();
  records.set('users/worker', { role: 'worker', verificationStatus: 'pending' });
  records.set('admin_accounts/viewer', { status: 'active', email: 'viewer@example.test', permissions: ['verification.view'] });
  const now = new Date();
  const evidence = newEvidence({ match: true, band: 'strong', similarity: 90, distance: 0.4 }, {
    workerId: 'worker', submissionId: 'synthetic-attempt', now, thresholds: { autoVerifyMin: 80, reviewMin: 60 },
  });
  records.set('worker_verifications/worker', { ...evidence, status: 'pending', storageBackend: 'local' });
});
const review = (token = 'reviewer', data = { status: 'verified' }) => request(app).patch('/review/worker').set('Authorization', `Bearer ${token}`).send(data);
test('unauthenticated, ordinary users, view-only reviewers and self-review cannot grant eligibility', async () => {
  await request(app).patch('/review/worker').send({ status: 'verified' }).expect(401);
  await review('worker').expect(403); await review('viewer').expect(403); await review('self').expect(403);
  assert.equal(writes.length, 0);
});
test('authorized admin cannot approve a face-only record or inject missing check results', async () => {
  const details = await request(app).get('/review/worker').set('Authorization', 'Bearer reviewer').expect(200);
  assert.equal(details.body.item.approvalReady, false);
  assert.equal(details.body.item.reviewable, true);
  assert.ok(details.body.item.policyReasons.includes('OFFICIAL_GOVERNMENT_AUTHENTICATION_REQUIRED'));
  const before = structuredClone([...records]);
  const response = await review().expect(409);
  assert.equal(response.body.code, 'VERIFICATION_REQUIREMENTS_NOT_MET');
  await review('reviewer', { status: 'verified', government: { status: 'AUTHENTICATED' } }).expect(400);
  assert.equal(writes.length, 0); assert.deepEqual([...records], before);
});
test('complete synthetic policy fixture commits review, eligibility and audit together', async () => {
  const record = records.get('worker_verifications/worker'), now = new Date();
  // Internal proof fixtures only; no official API integration is implemented.
  const proof = { userId: 'worker', attemptId: record.submissionId, environment: 'LIVE', validatedByBackend: true,
    reference: 'synthetic-test-reference', validatedAt: now, expiresAt: new Date(now.getTime() + 60000) };
  record.government = { ...proof, provider: 'PSA', status: 'AUTHENTICATED' };
  record.liveness = { ...proof, provider: 'synthetic-test-provider', source: 'SERVER', status: 'PASSED' };
  const missingDocument = await review().expect(409);
  assert.equal(missingDocument.body.code, 'DOCUMENT_REVIEW_REQUIRED');
  assert.equal(writes.length, 0);
  Object.assign(process.env, { GCLOUD_PROJECT: 'demo-swiftserve-cleanup', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8187', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' });
  record.documentBinding = { sessionId: 'synthetic-document-session', attemptId: 'synthetic-document-attempt', sha256: 'ab'.repeat(32) };
  records.set('document_suitability/worker', { ownerId: 'worker', ...record.documentBinding, status: 'DOCUMENT_ACCEPTED', expiresAt: new Date(now.getTime() + 60000) });
  const details = await request(app).get('/review/worker').set('Authorization', 'Bearer reviewer').expect(200);
  assert.equal(details.body.item.approvalReady, true);
  await review().expect(200);
  assert.equal(records.get('users/worker').verificationStatus, 'verified');
  assert.equal(records.get('worker_profiles/worker').verificationStatus, 'verified');
  assert.equal(records.get('worker_verifications/worker').workerDecision.eligible, true);
  assert.ok(writes.some(write => write.ref.name === 'admin_audit_logs'));
});
test('all legacy records and already verified accounts are preserved without writes', async () => {
  for (const legacy of [true, false]) {
    const record = records.get('worker_verifications/worker');
    if (legacy) delete record.schemaVersion;
    else { record.schemaVersion = 2; records.get('users/worker').verificationStatus = 'verified'; }
    const before = structuredClone([...records]);
    const response = await review('reviewer', { status: 'rejected' }).expect(409);
    assert.equal(response.body.code, 'LEGACY_VERIFICATION_PROTECTED');
    assert.deepEqual([...records], before); assert.equal(writes.length, 0);
  }
});
