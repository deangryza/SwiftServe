const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const request = require('supertest');

// Minimal in-memory Firestore covering what pushService uses.
function fakeDb() {
  const store = new Map();
  const ref = (path) => ({
    path,
    get: async () => ({ exists: store.has(path), data: () => store.get(path) }),
    set: async (data) => { store.set(path, data); },
    delete: async () => { store.delete(path); },
    create: async (data) => {
      if (store.has(path)) throw Object.assign(new Error('exists'), { code: 6 });
      store.set(path, data);
    },
    collection: (name) => collection(`${path}/${name}`),
  });
  const collection = (path) => ({
    doc: (id) => ref(`${path}/${id}`),
    get: async () => ({
      docs: [...store.keys()]
        .filter((key) => key.startsWith(`${path}/`) && !key.slice(path.length + 1).includes('/'))
        .map((key) => ({ ref: ref(key), data: () => store.get(key) })),
    }),
  });
  return { store, collection };
}

function fakeMessaging({ failToken } = {}) {
  const sent = [];
  return {
    sent,
    sendEach: async (messages) => {
      sent.push(...messages);
      return {
        successCount: messages.filter((m) => m.token !== failToken).length,
        responses: messages.map((m) => (m.token === failToken
          ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
          : { success: true })),
      };
    },
  };
}

const db = fakeDb();
const configPath = require.resolve('../src/config/firebase');
require.cache[configPath] = {
  id: configPath, filename: configPath, loaded: true,
  exports: { db, auth: { verifyIdToken: async (token) => ({ uid: token }) } },
};
const { pushNotification, pushChat } = require('../src/services/pushService');
const app = express();
app.use(express.json());
app.use('/api/push', require('../src/routes/pushRoutes'));

const register = (uid, body) => request(app)
  .post('/api/push/devices').set('Authorization', `Bearer ${uid}`).send(body);

test('device registration requires sign-in and valid fields', async () => {
  await request(app).post('/api/push/devices').send({}).expect(401);
  await register('client1', { installationId: 'bad id!', token: 't', platform: 'android' }).expect(400);
  await register('client1', { installationId: 'phone1', token: '', platform: 'android' }).expect(400);
  await register('client1', { installationId: 'phone1', token: 't', platform: 'web' }).expect(400);
});

test('registers, then revokes, a phone for the signed-in user only', async () => {
  await register('client1', {
    installationId: 'phone1', token: 'token-a', platform: 'android', enabled: true, chats: true, activities: true,
  }).expect(200);
  const saved = db.store.get('push_devices/client1/devices/phone1');
  assert.equal(saved.token, 'token-a');
  assert.equal(saved.enabled, true);
  await register('client1', { installationId: 'phone1', revoke: true }).expect(200);
  assert.equal(db.store.has('push_devices/client1/devices/phone1'), false);
});

test('a notification is pushed once to enabled phones that want activities', async () => {
  const local = fakeDb();
  local.store.set('push_devices/worker1/devices/a', { token: 'on', enabled: true, activities: true });
  local.store.set('push_devices/worker1/devices/b', { token: 'muted', enabled: true, activities: false });
  local.store.set('push_devices/worker1/devices/c', { token: 'off', enabled: false });
  const messaging = fakeMessaging();
  const notification = {
    recipientId: 'worker1', senderId: 'client1', title: 'Application accepted', body: 'Ann selected you.',
  };
  await pushNotification({ db: local, messaging, id: 'n1', notification });
  await pushNotification({ db: local, messaging, id: 'n1', notification }); // duplicate event
  assert.equal(messaging.sent.length, 1);
  assert.equal(messaging.sent[0].token, 'on');
  assert.equal(messaging.sent[0].notification.title, 'Application accepted');
  assert.deepEqual(messaging.sent[0].data, {
    type: 'activity', notificationId: 'n1', recipientId: 'worker1', eventId: 'n_n1',
  });
});

test('invalid tokens are removed after a failed send', async () => {
  const local = fakeDb();
  local.store.set('push_devices/worker1/devices/a', { token: 'stale', enabled: true });
  const messaging = fakeMessaging({ failToken: 'stale' });
  await pushNotification({
    db: local, messaging, id: 'n2', notification: { recipientId: 'worker1', senderId: 'x', title: 'T', body: 'B' },
  });
  assert.equal(local.store.has('push_devices/worker1/devices/a'), false);
});

test('chat pushes go to the other participant without message text', async () => {
  const local = fakeDb();
  local.store.set('public_profiles/client1', { fullName: 'Ann' });
  local.store.set('push_devices/worker1/devices/a', { token: 'w', enabled: true, chats: true });
  local.store.set('push_devices/client1/devices/a', { token: 'c', enabled: true, chats: true });
  const messaging = fakeMessaging();
  const conversation = {
    participantIds: ['client1', 'worker1'], lastSenderId: 'client1', lastMessageId: 'm1', lastMessage: 'secret',
  };
  await pushChat({ db: local, messaging, id: 'client1_worker1', conversation });
  await pushChat({ db: local, messaging, id: 'client1_worker1', conversation }); // read-receipt update
  assert.equal(messaging.sent.length, 1);
  assert.equal(messaging.sent[0].token, 'w');
  assert.equal(messaging.sent[0].notification.title, 'Ann');
  assert.equal(messaging.sent[0].notification.body, 'Sent you a message.');
});
