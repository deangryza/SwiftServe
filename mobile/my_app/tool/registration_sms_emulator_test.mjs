import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomInt } from 'node:crypto';

// No Admin SDK, cloud credentials, Firebase CLI project fallback or live URLs.
const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const project = 'demo-swiftserve-cleanup';
const enabled = process.env.RUN_REGISTRATION_SMS_EMULATOR_TESTS === 'true';
if (enabled && host !== '127.0.0.1:9099') throw new Error('Refusing non-local Auth emulator target.');
const root = `http://${host}`;
async function request(operation, body) {
  const response = await fetch(`${root}/identitytoolkit.googleapis.com/v1/accounts:${operation}?key=demo-otp-only`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(10000),
  });
  const result = await response.json();
  return { status: response.status, result };
}

test('local Auth emulator: email UID survives phone linking; wrong code cannot verify', { skip: !enabled }, async () => {
  const created = [];
  try {
    const signup = await request('signUp', { email: `otp-${randomUUID()}@example.test`, password: 'synthetic-local-password', returnSecureToken: true });
    assert.equal(signup.status, 200, 'synthetic email signup failed');
    created.push(signup.result.idToken);
    const uid = signup.result.localId;
    // Fictional North American 555-01xx range; the emulator never sends SMS.
    const phoneNumber = `+165055501${String(randomInt(0, 100)).padStart(2, '0')}`;
    const challenge = await request('sendVerificationCode', { phoneNumber });
    assert.equal(challenge.status, 200, 'local code request failed');
    const response = await fetch(`${root}/emulator/v1/projects/${project}/verificationCodes`, { signal: AbortSignal.timeout(10000) });
    assert.equal(response.status, 200, 'local verification-code lookup failed');
    const messages = await response.json();
    const code = messages.verificationCodes.find((entry) => entry.sessionInfo === challenge.result.sessionInfo)?.code;
    assert.match(code ?? '', /^\d{6}$/, 'emulator code unavailable');
    const wrong = code === '000000' ? '111111' : '000000';
    const rejected = await request('signInWithPhoneNumber', { idToken: signup.result.idToken, sessionInfo: challenge.result.sessionInfo, code: wrong });
    assert.equal(rejected.status, 400, 'wrong code was not rejected');
    const before = await request('lookup', { idToken: signup.result.idToken });
    assert.equal(before.result.users[0].localId, uid);
    assert.equal(before.result.users[0].phoneNumber, undefined);
    const linked = await request('signInWithPhoneNumber', { idToken: signup.result.idToken, sessionInfo: challenge.result.sessionInfo, code });
    assert.equal(linked.status, 200, 'phone link failed');
    assert.equal(linked.result.localId, uid, 'link unexpectedly created a different UID');
    created[0] = linked.result.idToken;
    const after = await request('lookup', { idToken: linked.result.idToken });
    assert.equal(after.result.users[0].phoneNumber, phoneNumber);
    assert.equal(after.result.users[0].localId, uid);
  } finally {
    // Delete only the random synthetic account created in this test. Never flush
    // the emulator or touch pre-existing users. Tokens/codes are never logged.
    for (const idToken of created) {
      const deleted = await request('delete', { idToken });
      assert.equal(deleted.status, 200, 'synthetic account cleanup failed');
    }
  }
});
