const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validate, runtimeEnv, seed, startLoop, main } = require('../scripts/localExpiryDemo');
const env = { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8187', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' };
test('local demo rejects cloud projects, remote endpoints, credentials and named databases', () => {
  validate(env);
  for (const patch of [{ FIREBASE_PROJECT_ID: 'swiftserve-production' }, { GOOGLE_CLOUD_PROJECT: 'swiftserve-staging-2026' },
    { FIRESTORE_EMULATOR_HOST: 'example.com:8187' }, { FIREBASE_AUTH_EMULATOR_HOST: '' },
    { FIRESTORE_EMULATOR_HOST: '127.0.0.1:99999' }, { GOOGLE_APPLICATION_CREDENTIALS: 'key.json' },
    { FIREBASE_CONFIG: '{}' }, { SWIFTSERVE_SUPER_ADMIN_UIDS: 'real-account' }, { FIRESTORE_DATABASE_ID: 'other' }]) {
    assert.throws(() => validate({ ...env, ...patch }));
  }
  const runtime = runtimeEnv(env);
  assert.equal(runtime.EXPIRY_EXPECTED_PROJECT, 'demo-swiftserve-cleanup');
  assert.equal(runtime.EXPIRY_PUSH_ENABLED, 'false');
  assert.equal(runtime.ACTIVITY_PUSH_ENABLED, 'false');
});
test('without explicit write-demo flag, no Firebase initialization or emulator access occurs', async () => {
  await main({ args: [], env: {} });
  await assert.rejects(main({ args: ['--write-demo'], env: {} }));
  await assert.rejects(main({ args: ['--write-demo'], env }), /PROCESS_ENVIRONMENT_REQUIRED/);
});
test('loop waits for active work, drains on shutdown, and never rearms after stop', async () => {
  let finish; let called = 0; let scheduled = 0;
  const stop = startLoop({ sweep: () => { called++; return new Promise(resolve => { finish = resolve; }); },
    schedule: () => { scheduled++; }, cancel() {}, onResult() {}, onError() {} });
  assert.equal(called, 1); assert.equal(scheduled, 0);
  let drained = false;
  const stopping = stop().then(() => { drained = true; });
  await Promise.resolve(); assert.equal(drained, false);
  finish({ status: 'interrupted' }); await stopping;
  assert.equal(scheduled, 0); assert.equal(drained, true);
});
test('loop retries failed scans without overlapping or calling a sender', async () => {
  let callback; let failures = 0;
  const stop = startLoop({ sweep: async () => { throw new Error('synthetic'); },
    schedule: fn => { callback = fn; }, cancel() {}, onResult() {}, onError() { failures++; } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(failures, 1); assert.equal(typeof callback, 'function');
  callback(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(failures, 2); await stop();
});
test('seeding preserves existing synthetic accounts and profiles', async () => {
  let writes = 0;
  const auth = { getUser: async uid => ({ email: `${uid.endsWith('client') ? 'client' : 'worker'}-expiry@example.test` }),
    createUser() { writes++; } };
  const db = { collection: name => ({ doc: uid => ({ get: async () => ({ exists: true,
    data: () => name === 'service_categories' ? { name: 'Cleaning', status: 'active' }
      : ({ role: uid.endsWith('client') ? 'client' : 'worker', email: `${uid.endsWith('client') ? 'client' : 'worker'}-expiry@example.test` }) }),
    create() { writes++; } }) }) };
  await seed(auth, db, {}); assert.equal(writes, 0);
});
test('seeding creates the required demo category without overwriting mismatched data', async () => {
  let created;
  const db = { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }),
    create: async data => { created = data; } }) }) };
  const auth = { getUser: async () => { throw new Error('stop after category'); } };
  await assert.rejects(seed(auth, db, 'demo-time'));
  assert.deepEqual(created, { name: 'Cleaning', status: 'active', createdAt: 'demo-time' });
  const mismatch = { collection: () => ({ doc: () => ({ get: async () => ({ exists: true,
    data: () => ({ name: 'Different', status: 'active' }) }), create() { throw new Error('must not overwrite'); } }) }) };
  await assert.rejects(seed(auth, mismatch, {}), /CATEGORY_MISMATCH/);
});
