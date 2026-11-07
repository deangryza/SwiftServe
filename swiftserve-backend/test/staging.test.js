const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { validateStagingEnvironment, diagnostic, PROJECT, ANDROID_APP } = require('../src/config/stagingFirebase');
const { appCheckMiddleware } = require('../src/middleware/stagingDiagnostics');

test('staging accepts only exact project, port, default database and disabled gates', () => {
  assert.doesNotThrow(() => validateStagingEnvironment({}));
  assert.doesNotThrow(() => validateStagingEnvironment({ PORT: '5002', GOOGLE_CLOUD_PROJECT: PROJECT, FIRESTORE_DATABASE_ID: '(default)' }));
  for (const key of ['GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT', 'FIREBASE_PROJECT_ID']) {
    assert.throws(() => validateStagingEnvironment({ [key]: 'swiftserve-production' }));
  }
  for (const [key, value] of Object.entries({ PORT: '5000', FIRESTORE_DATABASE_ID: 'other',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080', FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099',
    GOOGLE_APPLICATION_CREDENTIALS: 'private.json', FIREBASE_CONFIG: '{}', FIREBASE_STORAGE_BUCKET: 'production',
    STORAGE_EMULATOR_HOST: 'localhost', FIREBASE_STORAGE_EMULATOR_HOST: 'localhost',
    EXPIRED_JOB_CLEANUP_ENABLED: 'true', EXPIRED_JOB_CLEANUP_DRY_RUN: 'false', PUSH_DELIVERY_ENABLED: 'true',
    ACTIVITY_PUSH_ENABLED: 'true', EXPIRY_PUSH_ENABLED: 'true', ENABLE_PUSH_NOTIFICATIONS: 'true' })) {
    assert.throws(() => validateStagingEnvironment({ [key]: value }), key);
  }
});

test('staging diagnostics never include error messages, tokens or paths', () => {
  const previous = console.error, output = [];
  console.error = line => output.push(line);
  try {
    diagnostic('authentication', { code: 'auth/invalid-id-token', message: 'secret-token private-address' });
    diagnostic('firestore', { code: 'secret token value' });
  } finally { console.error = previous; }
  assert.equal(output.length, 2);
  assert.ok(!output.join('').includes('secret'));
  assert.ok(!output.join('').includes('private-address'));
});

test('App Check rejects missing, invalid and wrong-app tokens, accepting only staging Android', async () => {
  const app = express();
  let calls = 0;
  app.use(appCheckMiddleware(async token => {
    calls++;
    if (token === 'valid') return { appId: ANDROID_APP };
    if (token === 'wrong') return { appId: 'production-app' };
    throw Object.assign(new Error('must-not-leak'), { code: 'app-check/invalid-token' });
  }));
  app.get('/', (_req, res) => res.json({ ok: true }));
  await request(app).get('/').expect(401);
  assert.equal(calls, 0);
  await request(app).get('/').set('X-Firebase-AppCheck', 'invalid').expect(401);
  await request(app).get('/').set('X-Firebase-AppCheck', 'wrong').expect(401);
  await request(app).get('/').set('X-Firebase-AppCheck', 'valid').expect(200, { ok: true });
});
