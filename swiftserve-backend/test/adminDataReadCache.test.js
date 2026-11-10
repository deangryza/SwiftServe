const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const records = {
  users: { client: { fullName: 'Client', role: 'client' } },
  service_requests: { booking: { title: 'Clean home', status: 'pending' } },
  reports: {}, service_categories: {}, worker_verifications: {}, sos_alerts: {},
};
const reads = {};
const totalReads = () => Object.values(reads).reduce((sum, count) => sum + count, 0);
const db = {
  collection: name => ({
    get: async () => {
      reads[name] = (reads[name] || 0) + 1;
      return { docs: Object.keys(records[name]).map(id => ({ id, exists: true, data: () => records[name][id] })) };
    },
  }),
};
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: { db, auth: {
  verifyIdToken: async () => ({ uid: 'admin', admin: true }),
  getUser: async uid => ({ uid, disabled: false, customClaims: { admin: true } }),
} } };

const routes = require('../src/routes/adminDataRoutes');
const app = express();
app.use(express.json());
app.use('/api/admin', routes.clearOnWrite);
app.use('/api/admin', routes);
const authorized = call => call.set('Authorization', 'Bearer admin');

test('one overview refresh reads each collection once and repeats share it', async () => {
  await authorized(request(app).get('/api/admin/overview')).expect(200);
  assert.deepEqual(reads, { users: 1, service_requests: 1, reports: 1, service_categories: 1, worker_verifications: 1 });
  await authorized(request(app).get('/api/admin/overview')).expect(200);
  await authorized(request(app).get('/api/admin/users')).expect(200);
  assert.equal(totalReads(), 5);
});

test('an admin write makes the next request read fresh data', async () => {
  const before = reads.users;
  await authorized(request(app).patch('/api/admin/bookings/missing-route').send({})).expect(() => {});
  await authorized(request(app).get('/api/admin/users')).expect(200);
  assert.equal(reads.users, before + 1);
});
