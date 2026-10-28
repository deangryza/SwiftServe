const { beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

const store = {};
const table = name => (store[name] ||= {});
let nextId = 0;

const docRef = (name, id) => ({
  id,
  get: async () => {
    const value = table(name)[id];
    return { id, exists: value !== undefined, data: () => value, ref: docRef(name, id) };
  },
  set: async data => { table(name)[id] = data; },
  update: async data => {
    if (!table(name)[id]) throw Object.assign(new Error('Missing'), { code: 5 });
    table(name)[id] = { ...table(name)[id], ...data };
  },
  collection: sub => collectionRef(`${name}/${id}/${sub}`),
});
const query = (name, filters) => ({
  where: (field, _operator, value) => query(name, [...filters, [field, value]]),
  limit: () => query(name, filters),
  get: async () => ({
    docs: Object.entries(table(name))
      .filter(([, data]) => filters.every(([field, value]) => data[field] === value))
      .map(([id, data]) => ({ id, data: () => data, ref: docRef(name, id) })),
  }),
});
const collectionRef = name => ({
  doc: id => docRef(name, id ?? `generated-${++nextId}`),
  where: (field, operator, value) => query(name, []).where(field, operator, value),
  get: async () => query(name, []).get(),
});
const db = { collection: collectionRef };

const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: {
  db,
  auth: { verifyIdToken: async token => ({ uid: token, admin: token === 'admin', email: `${token}@example.com` }) },
} };
const app = express();
app.use(express.json());
app.use('/api/sos', require('../src/routes/sosRoutes'));
app.use('/api/admin', require('../src/routes/adminDataRoutes'));

const as = uid => ({ Authorization: `Bearer ${uid}` });

beforeEach(() => {
  for (const key of Object.keys(store)) delete store[key];
  Object.assign(table('service_requests'), {
    job: { clientId: 'client', workerId: 'worker', status: 'ongoing', modality: 'onsite', title: 'Fix sink', location: 'Malolos' },
    done: { clientId: 'client', workerId: 'worker', status: 'completed', modality: 'onsite' },
    online: { clientId: 'client', workerId: 'worker', status: 'accepted', modality: 'online' },
  });
  table('service_requests/job/private').location = { address: '12 Mabini St, Malolos' };
  Object.assign(table('users'), {
    client: { fullName: 'Carla Client', phoneNumber: '+639171111111', role: 'client' },
    worker: { fullName: 'Wally Worker', phoneNumber: '+639172222222', role: 'worker', photoBase64: 'face' },
  });
  table('worker_verifications').worker = { status: 'verified', idType: 'Driver License', maskedIdNumber: '****1234' };
});

test('a client SOS captures the worker identity and job address', async () => {
  const response = await request(app).post('/api/sos').set(as('client'))
    .send({ requestId: 'job', position: { lat: 14.84, lng: 120.81, accuracy: 12 } });
  assert.equal(response.status, 201);
  const alert = table('sos_alerts')[response.body.id];
  assert.equal(alert.status, 'active');
  assert.equal(alert.raisedByUid, 'client');
  assert.equal(alert.raisedBy.phone, '+639171111111');
  assert.equal(alert.otherParty.role, 'worker');
  assert.equal(alert.otherParty.phone, '+639172222222');
  assert.equal(alert.otherParty.photoBase64, 'face');
  assert.equal(alert.workerIdentity.maskedIdNumber, '****1234');
  assert.equal(alert.jobAddress, '12 Mabini St, Malolos');
  assert.deepEqual(alert.position, { lat: 14.84, lng: 120.81, accuracy: 12 });
});

test('a worker can raise SOS against the client', async () => {
  const response = await request(app).post('/api/sos').set(as('worker')).send({ requestId: 'job' });
  assert.equal(response.status, 201);
  const alert = table('sos_alerts')[response.body.id];
  assert.equal(alert.raisedBy.role, 'worker');
  assert.equal(alert.otherParty.uid, 'client');
  assert.equal(alert.position, null);
});

test('pressing again refreshes the same active alert', async () => {
  const first = await request(app).post('/api/sos').set(as('client')).send({ requestId: 'job' });
  const second = await request(app).post('/api/sos').set(as('client'))
    .send({ requestId: 'job', position: { lat: 1, lng: 2 } });
  assert.equal(second.status, 200);
  assert.equal(second.body.id, first.body.id);
  assert.equal(Object.keys(table('sos_alerts')).length, 1);
  assert.equal(table('sos_alerts')[first.body.id].pressCount, 2);
  assert.deepEqual(table('sos_alerts')[first.body.id].position, { lat: 1, lng: 2 });
});

test('only participants of an active in-person job can raise SOS', async () => {
  await request(app).post('/api/sos').send({ requestId: 'job' }).expect(401);
  await request(app).post('/api/sos').set(as('stranger')).send({ requestId: 'job' }).expect(403);
  await request(app).post('/api/sos').set(as('client')).send({ requestId: 'done' }).expect(409);
  await request(app).post('/api/sos').set(as('client')).send({ requestId: 'online' }).expect(409);
  await request(app).post('/api/sos').set(as('client')).send({ requestId: 'missing' }).expect(404);
  await request(app).post('/api/sos').set(as('client')).send({}).expect(400);
  assert.deepEqual(table('sos_alerts'), {});
});

test('invalid coordinates are dropped rather than stored', async () => {
  const response = await request(app).post('/api/sos').set(as('client'))
    .send({ requestId: 'job', position: { lat: 500, lng: 'x' } });
  assert.equal(table('sos_alerts')[response.body.id].position, null);
});

test('only the person who raised the alert can mark it safe', async () => {
  const { body } = await request(app).post('/api/sos').set(as('client')).send({ requestId: 'job' });
  await request(app).post(`/api/sos/${body.id}/safe`).set(as('worker')).expect(404);
  assert.equal(table('sos_alerts')[body.id].status, 'active');
  await request(app).post(`/api/sos/${body.id}/safe`).set(as('client')).expect(200);
  assert.equal(table('sos_alerts')[body.id].status, 'safe');
});

test('admins list alerts needing attention first and can resolve them', async () => {
  table('sos_alerts').old = { status: 'resolved', createdAt: new Date('2026-10-01'), raisedByUid: 'x' };
  const { body } = await request(app).post('/api/sos').set(as('client')).send({ requestId: 'job' });

  await request(app).get('/api/admin/sos').set(as('client')).expect(403);
  const list = await request(app).get('/api/admin/sos').set(as('admin')).expect(200);
  assert.equal(list.body.items[0].id, body.id);
  assert.equal(list.body.items[0].status, 'Active');

  await request(app).patch(`/api/admin/sos/${body.id}`).set(as('admin')).send({ status: 'deleted' }).expect(400);
  await request(app).patch(`/api/admin/sos/${body.id}`).set(as('admin'))
    .send({ status: 'resolved', adminNotes: 'Police responded; client safe.' }).expect(200);
  assert.equal(table('sos_alerts')[body.id].status, 'resolved');
  assert.equal(table('sos_alerts')[body.id].handledBy, 'admin@example.com');
});
