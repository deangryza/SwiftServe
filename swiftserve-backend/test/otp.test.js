const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

process.env.OTP_TOKEN_SECRET = 'test-secret-that-is-long-enough';
process.env.IPROGSMS_API_TOKEN = 'test-iprog-token';
process.env.PHONE_OTP_REQUIRED = 'true';

// In-memory Firestore covering what the OTP service and profile creation use.
const collections = {};
const ref = (name, id) => ({
  name,
  id,
  get: async () => {
    const value = (collections[name] || {})[id];
    return { exists: value !== undefined, data: () => value };
  },
  set: async (data, options) => {
    const target = collections[name] || (collections[name] = {});
    target[id] = options?.merge ? { ...target[id], ...data } : data;
  },
});
const db = {
  collection: (name) => ({
    doc: (id) => ref(name, id),
    where: (field, _op, value) => ({
      limit: () => ({
        get: async () => ({
          docs: Object.entries(collections[name] || {})
            .filter(([, data]) => data[field] === value)
            .map(([id, data]) => ({ id, data: () => data })),
        }),
      }),
    }),
  }),
  runTransaction: async (callback) => {
    const pending = [];
    const result = await callback({
      get: (reference) => reference.get(),
      set: (reference, data, options) => pending.push([reference, data, options]),
    });
    for (const [reference, data, options] of pending) await reference.set(data, options);
    return result;
  },
};
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = {
  id: configPath, filename: configPath, loaded: true,
  exports: { db, auth: { verifyIdToken: async (token) => ({ uid: token }) } },
};

// Fake IPROG SMS: remembers the last code per number.
const iprog = { sent: [], codes: {}, fail: false };
global.fetch = async (url, options) => {
  const body = JSON.parse(options.body);
  assert.equal(body.api_token, 'test-iprog-token');
  if (iprog.fail) return { ok: false, json: async () => ({ status: 'error' }) };
  if (url.endsWith('/send_otp')) {
    iprog.sent.push(body);
    iprog.codes[body.phone_number] = '123456';
    return { ok: true, json: async () => ({ status: 'success', data: { otp_code: '123456' } }) };
  }
  const valid = iprog.codes[body.phone_number] === body.otp;
  return { ok: true, json: async () => (valid ? { status: 'success' } : { status: 'error', message: 'Invalid OTP' }) };
};

const { readPhoneToken, signPhoneToken } = require('../src/services/otpService');
const app = express();
app.use(express.json());
app.use('/api/otp', require('../src/routes/otpRoutes'));
app.use('/api/users', require('../src/routes/userRoutes'));

beforeEach(() => {
  for (const key of Object.keys(collections)) delete collections[key];
  iprog.sent.length = 0;
  iprog.codes = {};
  iprog.fail = false;
});

const send = (phoneNumber) => request(app).post('/api/otp/send').send({ phoneNumber });
const verify = (phoneNumber, code) => request(app).post('/api/otp/verify').send({ phoneNumber, code });

test('only Philippine mobile numbers can request a code', async () => {
  for (const phone of ['+14155550123', '+63212345678', '09171234567', '']) {
    const response = await send(phone).expect(400);
    assert.equal(response.body.code, 'INVALID_PHONE_NUMBER');
  }
  assert.equal(iprog.sent.length, 0);
});

test('sending a code never returns the code to the app', async () => {
  const response = await send('+639171234567').expect(200);
  assert.equal(JSON.stringify(response.body).includes('123456'), false);
  assert.equal(iprog.sent[0].phone_number, '639171234567');
  assert.match(iprog.sent[0].message, /:otp/);
});

test('resending within 60 seconds is refused', async () => {
  await send('+639171234567').expect(200);
  const again = await send('+639171234567').expect(429);
  assert.equal(again.body.code, 'OTP_COOLDOWN');
  assert.ok(again.body.retryAfterSeconds > 0);
  assert.equal(iprog.sent.length, 1);
});

test('a wrong code is rejected and five wrong codes lock the code', async () => {
  await send('+639171234567').expect(200);
  for (let i = 0; i < 5; i++) {
    const wrong = await verify('+639171234567', '000000').expect(400);
    assert.equal(wrong.body.code, 'OTP_INVALID');
  }
  const locked = await verify('+639171234567', '123456').expect(429);
  assert.equal(locked.body.code, 'OTP_TOO_MANY_ATTEMPTS');
});

test('the correct code returns a token tied to that number', async () => {
  await send('+639171234567').expect(200);
  const response = await verify('+639171234567', '123456').expect(200);
  assert.equal(readPhoneToken(response.body.verificationToken), '+639171234567');
  // The same code cannot be reused for another verification.
  await verify('+639171234567', '123456').expect(429);
});

test('SMS provider failures are reported without exposing details', async () => {
  iprog.fail = true;
  const response = await send('+639171234567').expect(502);
  assert.equal(response.body.code, 'OTP_SEND_FAILED');
});

test('expired or tampered tokens are invalid', () => {
  const token = signPhoneToken('+639171234567', { now: Date.now() - 25 * 60 * 60 * 1000 });
  assert.equal(readPhoneToken(token), null);
  const valid = signPhoneToken('+639171234567');
  assert.equal(readPhoneToken(`${valid}x`), null);
  assert.equal(readPhoneToken('nonsense'), null);
});

const profile = (uid, extra) => request(app).post('/api/users/profile')
  .set('Authorization', `Bearer ${uid}`)
  .send({ fullName: 'Ana Cruz', email: `${uid}@example.com`, phoneNumber: '+639171234567', role: 'client', ...extra });

test('creating a profile requires a verified phone number', async () => {
  const missing = await profile('u1', {}).expect(400);
  assert.equal(missing.body.code, 'PHONE_VERIFICATION_REQUIRED');
  const otherPhone = await profile('u1', { phoneVerificationToken: signPhoneToken('+639179999999') }).expect(400);
  assert.equal(otherPhone.body.code, 'PHONE_VERIFICATION_REQUIRED');
  const foreign = await profile('u1', { phoneNumber: '+14155550123', phoneVerificationToken: signPhoneToken('+14155550123') })
    .expect(400);
  assert.equal(foreign.body.code, 'INVALID_PHONE_NUMBER');

  await profile('u1', { phoneVerificationToken: signPhoneToken('+639171234567') }).expect(201);
  assert.equal(collections.users.u1.phoneVerified, true);
});
