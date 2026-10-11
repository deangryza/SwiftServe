const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');
const { createCanvas } = require('canvas');

const records = {};
const db = {
  collection: name => ({ doc: id => ({ name, id, update: async data => {
    if (!records[id]) throw Object.assign(new Error('Missing'), { code: 5 });
    records[id] = { ...records[id], ...data };
  } }) }),
  batch: () => {
    const pending = [];
    return {
      set: (ref, data) => pending.push([ref, data]),
      commit: async () => pending.forEach(([ref, data]) => { if (ref.name === 'users') records[ref.id] = data; }),
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
    .send({ fullName: 'Alice Santos', email: 'alice@example.com', role: 'client', photoBase64: photo }).expect(201);
  assert.equal(records.alice.fullName, 'Alice Santos');
  assert.equal(Buffer.from(records.alice.photoBase64, 'base64')[0], 0xff);
});

test('photo updates affect only the authenticated profile and preserve its details', async () => {
  records.bob = { fullName: 'Bob', role: 'client', phoneNumber: '123' };
  await request(app).patch('/api/users/profile/photo').send({ photoBase64: photo }).expect(401);
  await request(app).patch('/api/users/profile/photo').set('Authorization', 'Bearer bob')
    .send({ uid: 'alice', photoBase64: photo }).expect(200);
  assert.equal(records.bob.fullName, 'Bob');
  assert.equal(records.bob.phoneNumber, '123');
  assert.ok(records.bob.photoBase64);
  await request(app).patch('/api/users/profile/photo').set('Authorization', 'Bearer missing')
    .send({ photoBase64: photo }).expect(404);
});

test('invalid and oversized images are rejected before writing a profile', async () => {
  for (const photoBase64 of ['not an image', 'A'.repeat(65540), Buffer.from('fake').toString('base64')]) {
    await request(app).post('/api/users/profile').set('Authorization', 'Bearer invalid')
      .send({ fullName: 'Invalid', email: 'invalid@example.com', role: 'client', photoBase64 }).expect(400);
  }
  assert.equal(records.invalid, undefined);
});
