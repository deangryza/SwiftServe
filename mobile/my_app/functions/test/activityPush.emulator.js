const { test, before, beforeEach, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { enqueue, recordUpdate } = require('../src/activityPush');
const { dispatch, retryDue, registerDevice, OUTBOX } = require('../src/runtime');
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw new Error('Loopback only');
describe('activity push persistence', { skip: !host }, () => {
  const projectId = 'demo-swiftserve-activity';
  const env = { FUNCTIONS_EMULATOR: 'true', FIRESTORE_EMULATOR_HOST: host, EXPIRY_EXPECTED_PROJECT: projectId,
    EXPIRY_DATABASE: '(default)', ACTIVITY_PUSH_ENABLED: 'true', ACTIVITY_PUSH_DRY_RUN: 'false',
    ACTIVITY_EVENTS_ENABLED: 'true', EXPIRY_TOKEN_REGISTRATION_ENABLED: 'true' };
  let app, db;
  const now = 1800000000000;
  const options = extra => ({ db, env, now: () => now, ...extra });
  before(() => { app = initializeApp({ projectId }, 'activity-tests'); db = getFirestore(app); });
  beforeEach(async () => {
    const response = await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
    assert.ok(response.ok);
    await db.doc('_jobExpiryControl/settings').set({ activityPushEnabled: true, activityEventsEnabled: true, registrationEnabled: true });
    await db.doc('conversations/c').set({ participantIds: ['sender', 'recipient'], clientId: 'sender', workerId: 'recipient' });
    await db.doc('conversations/c/messages/m').set({ senderId: 'sender', text: 'Secret message' });
    await db.doc('public_profiles/sender').set({ fullName: 'Sender' });
  });
  after(async () => { await db.terminate(); await deleteApp(app); });
  const device = (installation = 'a', extra = {}) => registerDevice(options({ uid: 'recipient', data: {
    installationId: installation.repeat(32), platform: 'android', token: `test-token-${installation.repeat(30)}`, ...extra } }));
  async function queue() {
    await enqueue(options({ conversationId: 'c', messageId: 'm' }));
    return (await db.collection(OUTBOX).get()).docs[0];
  }
  test('duplicate chat triggers and concurrent dispatch send only to recipient once per device', async () => {
    await device(); await device('b');
    await Promise.all([queue(), queue()]);
    const events = await db.collection(OUTBOX).get(); assert.equal(events.size, 1);
    const sent = [];
    await Promise.all([1, 2].map(() => dispatch(options({ eventId: events.docs[0].id, send: async message => sent.push(message) }))));
    assert.equal(sent.length, 2);
    assert.ok(sent.every(message => message.data.recipientId === 'recipient' && message.data.conversationId === 'c'));
    assert.ok(sent.every(message => !JSON.stringify(message).includes('Secret message')));
    await dispatch(options({ eventId: events.docs[0].id, send: async () => assert.fail('duplicate') }));
  });
  test('disabled devices and disabled chat preferences send nothing, preserve messages', async () => {
    await device('a', { enabled: false }); await device('b', { chats: false });
    const event = await queue();
    const result = await dispatch(options({ eventId: event.id, send: async () => assert.fail('disabled') }));
    assert.equal(result.status, 'no_targets');
    assert.ok((await db.doc('conversations/c/messages/m').get()).exists);
  });
  test('refreshed tokens replace old targets; revoked tokens are not sent', async () => {
    await device(); await device('a', { token: 'fresh-token-abcdefghijklmnop' });
    const event = await queue(); const sent = [];
    await dispatch(options({ eventId: event.id, send: async message => sent.push(message.token) }));
    assert.deepEqual(sent, ['fresh-token-abcdefghijklmnop']);
    await device('a', { token: 'fresh-token-abcdefghijklmnop', revoke: true });
    assert.equal((await db.collection('users/recipient/push_devices').get()).size, 0);
  });
  test('temporary send failure is recovered; invalid tokens are pruned', async () => {
    await device(); const event = await queue();
    assert.equal((await dispatch(options({ eventId: event.id, send: async () => { throw { code: 'messaging/internal-error' }; } }))).status, 'pending');
    await event.ref.update({ dueAt: Timestamp.fromMillis(now) });
    await retryDue(options({ send: async () => { throw { code: 'messaging/registration-token-not-registered' }; } }));
    assert.equal((await db.collection('users/recipient/push_devices').get()).size, 0);
  });
  test('existing application notification is reused, never duplicated', async () => {
    await db.doc('service_requests/job').set({ clientId: 'recipient' });
    await db.doc('notifications/application').set({ recipientId: 'recipient', senderId: 'sender', requestId: 'job', type: 'workerApplication' });
    await device();
    await enqueue(options({ notificationId: 'application' })); await enqueue(options({ notificationId: 'application' }));
    const events = await db.collection(OUTBOX).get(); assert.equal(events.size, 1);
    const sent = []; await dispatch(options({ eventId: events.docs[0].id, send: async message => sent.push(message) }));
    assert.equal(sent[0].data.notificationId, 'application');
    assert.equal((await db.collection('notifications').get()).size, 1);
  });
  test('rejection and booking updates produce deduplicated in-app records even without push devices', async () => {
    await db.doc('service_requests/job').set({ clientId: 'sender', workerId: 'recipient', status: 'ongoing' });
    await db.doc('service_requests/job/applications/recipient').set({ status: 'rejected' });
    const rejection = options({ requestId: 'job', workerId: 'recipient', status: 'rejected', version: 'v1' });
    await recordUpdate(rejection); await recordUpdate(rejection);
    await recordUpdate(options({ requestId: 'job', status: 'ongoing', version: 'v2' }));
    assert.equal((await db.collection('notifications').get()).size, 3);
    await recordUpdate(options({ requestId: 'job', status: 'completed', version: 'v3' }));
    assert.equal((await db.collection('notifications').get()).size, 3);
    const rejectionRecord = (await db.collection('notifications').where('type', '==', 'applicationRejected').get()).docs[0];
    await rejectionRecord.ref.delete();
    await recordUpdate(rejection);
    assert.equal((await db.collection('notifications').get()).size, 2, 'retry must not resurrect a deleted in-app notification');
  });
  test('outsider notification and blocked conversation create no events', async () => {
    await db.doc('service_requests/job').set({ clientId: 'sender' });
    await db.doc('notifications/forged').set({ recipientId: 'recipient', requestId: 'job' });
    assert.equal((await enqueue(options({ notificationId: 'forged' }))).count, 0);
    await db.doc('user_blocks/recipient_sender').set({});
    assert.equal((await enqueue(options({ conversationId: 'c', messageId: 'm' }))).count, 0);
  });
  test('paused expiration outboxes cannot starve activity retries', async () => {
    const batch = db.batch();
    for (let i = 0; i < 100; i++) batch.set(db.collection(OUTBOX).doc(`paused${i}`), {
      type: 'jobExpired', status: 'pending', dueAt: Timestamp.fromMillis(now - 1), attempts: 0,
    });
    await batch.commit(); await device(); await queue();
    let sent = 0;
    await retryDue(options({ send: async () => { sent++; } }));
    assert.equal(sent, 1);
    assert.equal((await db.collection(OUTBOX).where('type', '==', 'jobExpired').where('status', '==', 'pending').get()).size, 100);
  });
});
