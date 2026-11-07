const { test } = require('node:test');
const assert = require('node:assert/strict');
const { options, validateEnvironment, sweepOptions, setLocalGate, serverClock, SETTINGS } = require('../scripts/runLocalLiveExpiry');
test('default is read-only preview and live changes require the exact project acknowledgment', () => {
  assert.equal(options([]).mode, '--preview');
  for (const args of [['--run-live'], ['--stop-live'], ['--run-live', '--confirm-project=other'], ['--preview', '--run-live'], ['--unexpected']]) {
    assert.throws(() => options(args));
  }
  assert.equal(options(['--run-live', '--confirm-project=swiftserve-production']).mode, '--run-live');
});
test('rejects emulator, credential, project and global activation overrides before SDK initialization', () => {
  validateEnvironment({});
  for (const patch of [{ FIRESTORE_EMULATOR_HOST: '' }, { FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' },
    { GOOGLE_APPLICATION_CREDENTIALS: 'key.json' }, { GOOGLE_CLOUD_PROJECT: 'demo-test' },
    { SWIFTSERVE_SUPER_ADMIN_UIDS: 'account' }, { FIRESTORE_DATABASE_ID: 'other' },
    { NODE_TLS_REJECT_UNAUTHORIZED: '0' }, { EXPIRY_PUSH_ENABLED: 'true' }, { EXPIRED_JOB_CLEANUP_ENABLED: 'true' }]) {
    assert.throws(() => validateEnvironment(patch));
  }
});
test('runtime options enable only the local expiration switch and never a push sender', () => {
  const result = sweepOptions({});
  assert.equal(result.settingsDocument, 'localComputerSettings');
  assert.equal(result.env.EXPIRY_EXPECTED_PROJECT, 'swiftserve-production');
  assert.equal(result.env.EXPIRY_DATABASE, '(default)');
  assert.equal(result.env.EXPIRY_PUSH_ENABLED, 'false');
  assert.equal(result.env.ACTIVITY_PUSH_ENABLED, 'false');
  assert.equal(result.env.EXPIRY_TOKEN_REGISTRATION_ENABLED, 'false');
});
test('enable and emergency stop touch only the dedicated local settings document', async () => {
  const writes = [];
  const db = { doc: path => ({ set: async (data, options) => writes.push({ path, data, options }) }) };
  await setLocalGate(db, true); await setLocalGate(db, false);
  assert.deepEqual(writes.map(item => item.path), [SETTINGS, SETTINGS]);
  assert.deepEqual(writes.map(item => item.data.expirationEnabled), [true, false]);
  assert.ok(writes.every(item => item.options.merge === true));
});
test('live deadlines use Firestore read time advanced monotonically, not the computer wall clock', () => {
  let tick = 50;
  const now = serverClock({ readTime: { toMillis: () => 1000 } }, () => tick);
  assert.equal(now(), 1000);
  tick = 250; assert.equal(now(), 1200);
  for (const snapshot of [{}, { readTime: 1000 }, { readTime: { toMillis: () => NaN } }]) {
    assert.throws(() => serverClock(snapshot));
  }
});
