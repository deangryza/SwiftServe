const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const records = {
  users: {
    worker: { fullName: 'Real worker', role: 'worker', verificationStatus: 'verified', category: 'Cleaning' },
    dual: { fullName: 'Dual', role: 'client', roles: ['client', 'worker'], verificationStatus: 'pending' },
  },
  service_requests: { booking: { title: 'Clean home', clientName: 'Client', category: 'Cleaning', status: 'accepted', schedule: { toDate: () => new Date('2026-10-02T10:00:00Z') } } },
  reports: {}, service_categories: {}, worker_verifications: {}, notifications: {},
};
let writes = 0;
const doc = (name, id) => ({ id, exists: Boolean(records[name][id]), data: () => records[name][id] });
const db = {
  collection: name => ({
    get: async () => ({ docs: Object.keys(records[name]).map(id => doc(name, id)) }),
    doc: (id = `generated-${writes}`) => ({ id, get: async () => doc(name, id),
      set: async data => { writes++; records[name] ||= {}; records[name][id] = data; },
      update: async data => { writes++; records[name][id] = { ...records[name][id], ...data }; } }),
  }),
  runTransaction: async callback => callback({ get: reference => reference.get(), update: (reference, data) => reference.update(data), set: (reference, data) => reference.set(data) }),
};
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: { db, auth: {
  verifyIdToken: async token => ({ uid: 'admin', admin: token === 'admin' }),
  getUser: async uid => ({ uid, disabled: false, customClaims: { admin: uid === 'admin' } }),
} } };
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
test('booking DTO exposes cancel reason and labels who cancelled without raw uids', async () => {
  const original = records.service_requests.booking;
  const fetch = async () => (await request(app).get('/api/admin/bookings').set('Authorization', 'Bearer admin').expect(200)).body.items[0];
  try {
    records.service_requests.booking = { ...original, status: 'cancelled', clientId: 'client-uid', cancelledBy: 'client-uid',
      cancelReason: 'Schedule changed', cancelNote: 'Moving next week' };
    let item = await fetch();
    assert.equal(item.cancelledBy, 'Client');
    assert.equal(item.cancelReason, 'Schedule changed');
    assert.equal(item.cancelNote, 'Moving next week');
    records.service_requests.booking = { ...original, status: 'cancelled', clientId: 'client-uid', cancelledBy: 'admin-uid' };
    item = await fetch();
    assert.equal(item.cancelledBy, 'Admin');
    assert.equal(item.cancelReason, '');
    assert.equal(item.cancelNote, '');
    records.service_requests.booking = { ...original };
    item = await fetch();
    assert.equal(item.cancelledBy, '');
    assert.ok(!JSON.stringify(item).includes('admin-uid'));
  } finally {
    records.service_requests.booking = original;
  }
});
test('accepted bookings require override and completed bookings cannot be cancelled', async () => {
  const initialWrites = writes;
  await request(app).patch('/api/admin/bookings/booking').set('Authorization', 'Bearer admin').send({ status: 'Cancelled' }).expect(409);
  assert.equal(writes, initialWrites);
  await request(app).patch('/api/admin/bookings/booking').set('Authorization', 'Bearer admin').send({ status: 'Cancelled', override: true }).expect(200);
  assert.equal(records.service_requests.booking.status, 'cancelled');
  assert.ok(Object.values(records.admin_audit_logs).some(item => item.action === 'booking.cancelled' && item.targetId === 'booking'));
  records.service_requests.booking.status = 'completed';
  await request(app).patch('/api/admin/bookings/booking').set('Authorization', 'Bearer admin').send({ status: 'Cancelled', override: true }).expect(409);
});
test('rejects worker approval through user management and malformed categories', async () => {
  await request(app).patch('/api/admin/users/worker').set('Authorization', 'Bearer admin').send({ status: 'Rejected' }).expect(400);
  await request(app).post('/api/admin/categories').set('Authorization', 'Bearer admin').send({ name: '', status: 'Active' }).expect(400);
});

test('dual-role users list both roles and show worker verification', async () => {
  const users = await request(app).get('/api/admin/users').set('Authorization', 'Bearer admin').expect(200);
  const dual = users.body.items.find(item => item.id === 'dual');
  assert.equal(dual.role, 'Client');
  assert.deepEqual(dual.roles, ['Client', 'Worker']);
  assert.equal(dual.status, 'Pending');
});
