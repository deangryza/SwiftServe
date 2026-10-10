const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const records = {
  users: { worker: { fullName: 'Real worker', role: 'worker', verificationStatus: 'verified', category: 'Cleaning' } },
  service_requests: { booking: { title: 'Clean home', clientName: 'Client', category: 'Cleaning', status: 'accepted', schedule: { toDate: () => new Date('2026-10-02T10:00:00Z') } } },
  reports: {}, service_categories: {}, worker_verifications: {}, notifications: {},
};
let writes = 0;
const doc = (name, id) => ({ id, exists: Boolean(records[name][id]), data: () => records[name][id] });
const db = {
  collection: name => ({
    get: async () => ({ docs: Object.keys(records[name]).map(id => doc(name, id)) }),
    doc: id => ({ get: async () => doc(name, id), update: async data => { writes++; records[name][id] = { ...records[name][id], ...data }; } }),
  }),
  runTransaction: async callback => callback({ get: reference => reference.get(), update: (reference, data) => reference.update(data) }),
};
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: { db, auth: { verifyIdToken: async token => ({ uid: 'admin', admin: token === 'admin' }) } } };
const app = express();
app.use(express.json());
app.use('/api/admin', require('../src/routes/adminDataRoutes'));
app.use((error, _req, res, _next) => res.status(500).json({ message: error.message }));

test('admin data requires authenticated administrator claims', async () => {
  await request(app).get('/api/admin/users').expect(401);
  await request(app).get('/api/admin/users').set('Authorization', 'Bearer worker').expect(403);
});
test('maps Firestore worker roles and booking statuses without demo records', async () => {
  const users = await request(app).get('/api/admin/users').set('Authorization', 'Bearer admin').expect(200);
  assert.equal(users.body.items[0].id, 'worker');
  assert.equal(users.body.items[0].role, 'Worker');
  assert.equal(users.body.items[0].status, 'Verified');
  const bookings = await request(app).get('/api/admin/bookings').set('Authorization', 'Bearer admin').expect(200);
  assert.equal(bookings.body.items[0].status, 'Accepted');
  assert.equal(bookings.body.items[0].serviceTitle, 'Clean home');
  const reports = await request(app).get('/api/admin/reports').set('Authorization', 'Bearer admin').expect(200);
  assert.deepEqual(reports.body.items, []);
});
test('accepted bookings require override and completed bookings cannot be cancelled', async () => {
  const initialWrites = writes;
  await request(app).patch('/api/admin/bookings/booking').set('Authorization', 'Bearer admin').send({ status: 'Cancelled' }).expect(409);
  assert.equal(writes, initialWrites);
  await request(app).patch('/api/admin/bookings/booking').set('Authorization', 'Bearer admin').send({ status: 'Cancelled', override: true }).expect(200);
  assert.equal(records.service_requests.booking.status, 'cancelled');
  records.service_requests.booking.status = 'completed';
  await request(app).patch('/api/admin/bookings/booking').set('Authorization', 'Bearer admin').send({ status: 'Cancelled', override: true }).expect(409);
});
test('rejects worker approval through user management and malformed categories', async () => {
  await request(app).patch('/api/admin/users/worker').set('Authorization', 'Bearer admin').send({ status: 'Rejected' }).expect(400);
  await request(app).post('/api/admin/categories').set('Authorization', 'Bearer admin').send({ name: '', status: 'Active' }).expect(400);
});
