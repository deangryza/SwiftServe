const { test } = require('node:test');
const assert = require('node:assert/strict');
const { idFor, enqueue, context, recordUpdate } = require('../src/activityPush');
test('activity IDs are bounded, stable and separate each source and recipient', () => {
  const a = idFor('message', { conversationId: 'a'.repeat(1495), messageId: '1' }, 'worker');
  assert.equal(a, idFor('message', { conversationId: 'a'.repeat(1495), messageId: '1' }, 'worker'));
  assert.ok(a.length < 100);
  assert.notEqual(a, idFor('notification', { conversationId: 'a'.repeat(1495), messageId: '1' }, 'worker'));
  assert.notEqual(idFor('message', 'a', 'bc'), idFor('message', 'ab', 'c'));
});
test('disabled and dry-run activity handlers never touch Firestore', async () => {
  const db = new Proxy({}, { get() { throw new Error('touched database'); } });
  for (const env of [{}, { ACTIVITY_PUSH_ENABLED: 'true', ACTIVITY_PUSH_DRY_RUN: 'true' }])
    assert.equal((await enqueue({ db, env })).status, 'disabled');
  assert.equal((await recordUpdate({ db, env: {} })).status, 'disabled');
});
test('chat rejects self, outsiders and blocked users; preview never contains message text', async () => {
  const records = { 'conversations/c': { participantIds: ['a', 'b'] }, 'conversations/c/messages/m': { senderId: 'a', text: 'Private address 123 Street' }, 'public_profiles/a': { fullName: 'Alice' } };
  const db = { doc: path => path };
  const tx = { get: async path => ({ data: () => records[path], exists: !!records[path] }) };
  const event = { conversationId: 'c', messageId: 'm', recipientId: 'b' };
  assert.equal(await context(tx, db, { ...event, recipientId: 'a' }), null);
  assert.equal(await context(tx, db, { ...event, recipientId: 'other' }), null);
  const payload = await context(tx, db, event);
  assert.equal(payload.title, 'Alice');
  assert.equal(payload.body, 'Sent you a message.');
  assert.ok(!JSON.stringify(payload).includes('123 Street'));
  records['user_blocks/b_a'] = {};
  assert.equal(await context(tx, db, event), null);
});
