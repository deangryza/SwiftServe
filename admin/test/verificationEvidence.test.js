import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canApproveEvidence, canReviewEvidence, reviewBlockedReason, verificationRows, verificationBlockers } from '../src/lib/verificationEvidence.js';
test('disabled review actions always explain why', () => {
  assert.equal(reviewBlockedReason({ schemaVersion: 2, reviewable: true, status: 'pending' }, true), null);
  const locked = { schemaVersion: 2, reviewable: false, status: 'pending' };
  for (const [record, canManage, text] of [
    [locked, false, 'permission'],
    [{ status: 'pending' }, true, 'out of date'],
    [{ reviewable: false, status: 'rejected' }, true, 'already rejected'],
    [{ ...locked, status: 'rejected' }, true, 'already rejected'],
    [{ ...locked, status: 'verified' }, true, 'already verified'],
    [{ ...locked, providerType: 'MOCK' }, true, 'Mock'],
    [locked, true, 'already verified'],
  ]) assert.ok(reviewBlockedReason(record, canManage).includes(text), text);
});
test('approval requires permission, backend readiness and a mutable non-mock record', () => {
  const ready = { schemaVersion: 2, reviewable: true, approvalReady: true };
  assert.equal(canApproveEvidence(ready, true), true);
  for (const record of [{ ...ready, approvalReady: false }, { ...ready, reviewable: false }, { ...ready, providerType: 'MOCK' }, { ...ready, checkSource: 'SYNTHETIC_FIXTURE' }, {}]) {
    assert.equal(canApproveEvidence(record, true), false);
  }
  assert.equal(canApproveEvidence(ready, false), false);
  assert.equal(canReviewEvidence(ready, false), false);
});
test('legacy face match never renders official government authentication', () => {
  const rows = verificationRows({ status: 'verified', faceMatchBand: 'strong' });
  assert.ok(rows.some(([, value]) => value.includes('NOT OFFICIALLY VERIFIED')));
  assert.ok(rows.some(([, value]) => value.includes('LEGACY WORKER ACCESS')));
  assert.ok(verificationBlockers({ policyReasons: ['OFFICIAL_GOVERNMENT_AUTHENTICATION_REQUIRED'] })[0].includes('missing'));
});
test('mock evidence is labeled even when contradictory official fields are present', () => {
  const rows = verificationRows({ providerType: 'MOCK', officialGovernmentAuthenticated: true, livenessStatus: 'PASSED' });
  assert.ok(rows.some(([, value]) => value === 'MOCK / NOT OFFICIALLY VERIFIED'));
  assert.ok(rows.some(([, value]) => value.includes('NOT OFFICIALLY VERIFIED')));
  assert.ok(rows.some(([, value]) => value.includes('MOCK PASS')));
});
