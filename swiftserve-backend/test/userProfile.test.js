const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { createCanvas } = require('canvas');

const records = {};
const phoneClaims = {};
const publicProfiles = {};
const collections = {
  users: records,
  phone_number_claims: phoneClaims,
  public_profiles: publicProfiles,
};
const db = {
  collection: name => ({
    doc: id => ({
      name,
      id,
      get: async () => {
        const value = (collections[name] || {})[id];
        return { exists: value !== undefined, data: () => value };
      },
      update: async data => {
        const target = collections[name] || records;
        if (!target[id]) throw Object.assign(new Error('Missing'), { code: 5 });
        target[id] = { ...target[id], ...data };
      },
    }),
    where: (field, _operator, value) => ({
      limit: () => ({
        get: async () => ({
          docs: Object.entries(collections[name] || {})
            .filter(([, data]) => data[field] === value)
            .map(([id, data]) => ({ id, data: () => data })),
        }),
      }),
    }),
  }),
  runTransaction: async callback => {
    const pending = [];
    const transaction = {
      get: async ref => {
        const value = (collections[ref.name] || {})[ref.id];
        return { exists: value !== undefined, data: () => value };
      },
      set: (ref, data) => pending.push([ref, data]),
    };
    const result = await callback(transaction);
    pending.forEach(([ref, data]) => {
      const target = collections[ref.name] || (collections[ref.name] = {});
      target[ref.id] = data;
    });
    return result;
  },
  batch: () => {
    const pending = [];
    return {
      set: (ref, data, options) => pending.push(['set', ref, data, options]),
      update: (ref, data) => pending.push(['update', ref, data]),
      commit: async () => pending.forEach(([operation, ref, data, options]) => {
        const target = collections[ref.name] || (collections[ref.name] = {});
        if (operation === 'update' || options?.merge) {
          target[ref.id] = { ...target[ref.id], ...data };
        } else {
          target[ref.id] = data;
        }
      }),
    };
  },
};
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: {
  db, auth: { verifyIdToken: async token => ({ uid: token }) },
} };
const app = express();
app.use(express.json());
app.use('/api/users', require('../src/routes/userRoutes'));
const photo = createCanvas(8, 8).toBuffer('image/png').toString('base64');

test('registration persists a usable thumbnail with the actual name', async () => {
  await request(app).post('/api/users/profile').set('Authorization', 'Bearer alice')
    .send({ fullName: 'Alice Santos', email: 'alice@example.com', phoneNumber: '+639171111111', role: 'client', photoBase64: photo }).expect(201);
  assert.equal(records.alice.fullName, 'Alice Santos');
  assert.equal(Buffer.from(records.alice.photoBase64, 'base64')[0], 0xff);
  assert.equal(publicProfiles.alice.fullName, 'Alice Santos');
  assert.equal(publicProfiles.alice.role, 'client');
  assert.equal(publicProfiles.alice.photoBase64, records.alice.photoBase64);
  assert.equal(publicProfiles.alice.location, '');
  assert.equal(publicProfiles.alice.description, '');
  assert.deepEqual(publicProfiles.alice.skills, []);
});

test('photo updates affect only the authenticated profile and preserve its details', async () => {
  records.bob = { fullName: 'Bob', role: 'client', phoneNumber: '123' };
  await request(app).patch('/api/users/profile/photo').send({ photoBase64: photo }).expect(401);
  await request(app).patch('/api/users/profile/photo').set('Authorization', 'Bearer bob')
    .send({ uid: 'alice', photoBase64: photo }).expect(200);
  assert.equal(records.bob.fullName, 'Bob');
  assert.equal(records.bob.phoneNumber, '123');
  assert.ok(records.bob.photoBase64);
  assert.equal(publicProfiles.bob.fullName, 'Bob');
  assert.equal(publicProfiles.bob.photoBase64, records.bob.photoBase64);
  await request(app).patch('/api/users/profile/photo').set('Authorization', 'Bearer missing')
    .send({ photoBase64: photo }).expect(404);
});

test('invalid and oversized images are rejected before writing a profile', async () => {
  for (const photoBase64 of ['not an image', 'A'.repeat(65540), Buffer.from('fake').toString('base64')]) {
    await request(app).post('/api/users/profile').set('Authorization', 'Bearer invalid')
      .send({ fullName: 'Invalid', email: 'invalid@example.com', phoneNumber: '+639172222222', role: 'client', photoBase64 }).expect(400);
  }
  assert.equal(records.invalid, undefined);
});

test('a phone number can belong to only one account', async () => {
  const first = await request(app).post('/api/users/profile')
    .set('Authorization', 'Bearer phone-owner')
    .send({
      fullName: 'Phone Owner',
      email: 'owner@example.com',
      phoneNumber: '+63 917 333 3333',
      role: 'client',
    });
  assert.equal(first.status, 201);

  const duplicate = await request(app).post('/api/users/profile')
    .set('Authorization', 'Bearer other-user')
    .send({
      fullName: 'Other User',
      email: 'other@example.com',
      phoneNumber: '+639173333333',
      role: 'worker',
    });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.code, 'PHONE_NUMBER_IN_USE');
  assert.equal(records['other-user'], undefined);

  const retry = await request(app).post('/api/users/profile')
    .set('Authorization', 'Bearer phone-owner')
    .send({
      fullName: 'Phone Owner',
      email: 'owner@example.com',
      phoneNumber: '+639173333333',
      role: 'client',
    });
  assert.equal(retry.status, 201);
});

test('profile creation rejects missing or invalid phone numbers', async () => {
  for (const phoneNumber of ['', '09171234567', '+123']) {
    const response = await request(app).post('/api/users/profile')
      .set('Authorization', `Bearer invalid-phone-${phoneNumber}`)
      .send({
        fullName: 'Invalid Phone',
        email: 'invalid-phone@example.com',
        phoneNumber,
        role: 'client',
      });
    assert.equal(response.status, 400);
    assert.equal(response.body.code, 'INVALID_PHONE_NUMBER');
  }
});
