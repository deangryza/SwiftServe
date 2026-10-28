const { test } = require('node:test');
const assert = require('node:assert/strict');
const { addStatusWrites } = require('../src/services/verificationDecisionService');

test('identity decisions keep the canonical account status and publish account-wide notifications', () => {
  for (const status of ['verified', 'pending', 'rejected', 'resubmission_required']) {
    const writes = [];
    const db = { collection: name => ({ doc: (id = 'notice') => `${name}/${id}` }) };
    const batch = { set: (ref, data, options) => writes.push({ ref, data, options }) };
    const now = new Date();
    addStatusWrites(batch, db, 'same-account-uid', status, { senderId: 'admin', now });
    assert.equal(writes[0].ref, 'users/same-account-uid');
    assert.equal(writes[0].data.verificationStatus, status);
    assert.equal(writes[1].ref, 'worker_profiles/same-account-uid');
    assert.equal(writes[1].data.verificationStatus, status);
    assert.equal(writes[2].data.recipientId, 'same-account-uid');
    assert.equal(writes[2].data.recipientRole, 'account');
    assert.equal(writes[2].data.type, 'verificationUpdated');
    assert.equal(writes[2].data.read, false);
    assert.equal(writes[2].data.createdAt, now);
  }
});
