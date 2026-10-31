const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const express = require('express');
const request = require('supertest');

const emails = new Map([['used@example.com', { uid: 'existing' }], ['google@example.com', { uid: 'google-user' }]]);
const authPhones = new Map([['+639171111111', { uid: 'existing' }]]);
const users = new Map([['legacy', { phoneNumber: '+639172222222' }]]);
const claims = new Map();
const claimId = value => crypto.createHash('sha256').update(value).digest('hex');
claims.set(claimId('+639173333333'), { uid: 'claimed' });
claims.set(claimId('+639174444444'), { uid: 'google-user' });
claims.set(claimId('+639175555555'), {});
let fail = false, lookups = 0;
const missing = () => Object.assign(new Error('Missing'), { code: 'auth/user-not-found' });
const lookup = async (map, value) => {
  lookups++;
  if (fail) throw new Error('Simulated outage');
  if (!map.has(value)) throw missing();
  return map.get(value);
};
const firebasePath = require.resolve('../src/config/firebase');
require.cache[firebasePath] = { id: firebasePath, filename: firebasePath, loaded: true, exports: {
  auth: {
    getUserByEmail: value => lookup(emails, value),
    getUserByPhoneNumber: value => lookup(authPhones, value),
    verifyIdToken: async token => {
      if (token !== 'google-user') throw new Error('Invalid');
      return { uid: token };
    },
  },
  db: { collection: name => ({
    doc: id => ({ get: async () => {
      const value = (name === 'phone_number_claims' ? claims : users).get(id);
      return { exists: value !== undefined, data: () => value };
    } }),
    where: (field, _operator, value) => ({ limit: size => ({ get: async () => ({
      docs: [...users].filter(([, data]) => data[field] === value).slice(0, size).map(([id]) => ({ id })),
    }) }) }),
  }) },
} };
const app = express();
app.use(express.json());
app.use('/api/users', require('../src/routes/userRoutes'));
const check = body => request(app).post('/api/users/registration-availability').send(body);

test('email checks normalize case and report password/federated accounts without user data', async () => {
  for (const email of [' USED@EXAMPLE.COM ', 'google@example.com']) {
    const response = await check({ kind: 'email', value: email }).expect(200);
    assert.deepEqual(response.body, { available: false });
    assert.equal(response.headers['cache-control'], 'no-store');
  }
  assert.deepEqual((await check({ kind: 'email', value: 'new@example.com' }).expect(200)).body, { available: true });
});

test('phone checks cover Auth, hashed claims, and legacy profiles for either role', async () => {
  for (const value of ['+639171111111', '+639172222222', '+639173333333', '+639175555555']) {
    assert.deepEqual((await check({ kind: 'phone', value }).expect(200)).body, { available: false });
  }
  assert.deepEqual((await check({ kind: 'phone', value: '+639179999999' }).expect(200)).body, { available: true });
});

test('authenticated setup can keep its own contact but cannot impersonate another UID', async () => {
  const own = await check({ kind: 'phone', value: '+639174444444' }).set('Authorization', 'Bearer google-user').expect(200);
  assert.deepEqual(own.body, { available: true });
  assert.deepEqual((await check({ kind: 'phone', value: '+639174444444' }).expect(200)).body, { available: false });
  await check({ kind: 'phone', value: '+639173333333', uid: 'claimed' }).expect(400);
});

test('malformed and bulk requests never query account records', async () => {
  const before = lookups;
  for (const body of [{}, { kind: 'email', value: 'bad' }, { kind: 'phone', value: '09171234567' },
    { kind: 'email', value: ['used@example.com'] }, { kind: 'email', value: 'a'.repeat(255) + '@e.com' }]) {
    await check(body).expect(400);
  }
  assert.equal(lookups, before);
});

test('lookup failure is unknown/unavailable service, never a false available response', async () => {
  fail = true;
  try {
    const response = await check({ kind: 'email', value: 'new@example.com' }).expect(503);
    assert.equal(response.body.available, undefined);
  } finally { fail = false; }
});

test('availability route rate-limits repeated enumeration requests', async () => {
  const statuses = [];
  for (let index = 0; index < 35; index++) statuses.push((await check({ kind: 'email', value: 'new@example.com' })).status);
  assert.ok(statuses.includes(429));
  assert.equal(statuses.at(-1), 429);
});
