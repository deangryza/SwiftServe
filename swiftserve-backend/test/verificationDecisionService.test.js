const { test } = require('node:test');
const assert = require('node:assert/strict');
const { addStatusWrites } = require('../src/services/verificationDecisionService');
const { newEvidence, evaluateWorkerVerification, POLICY_VERSION } = require('../src/services/workerVerificationPolicy');
const now = new Date('2026-11-03T04:00:00Z');
const account = { role: 'worker', verificationStatus: 'pending' };
function evidence() {
  const record = newEvidence({ match: true, band: 'strong', distance: 0.4, similarity: 90 }, {
    workerId: 'worker', submissionId: 'synthetic-attempt', now, thresholds: { autoVerifyMin: 80, reviewMin: 60 },
  });
  const proof = { validatedByBackend: true, environment: 'LIVE', userId: 'worker', attemptId: 'synthetic-attempt',
    reference: 'synthetic-policy-fixture-not-a-real-proof', validatedAt: now, expiresAt: new Date(now.getTime() + 60000) };
  // Internal evaluator fixtures only. No PSA response, credentials or API request.
  record.government = { ...proof, status: 'AUTHENTICATED', provider: 'PSA' };
  record.liveness = { ...proof, status: 'PASSED', source: 'SERVER', provider: 'synthetic-test-provider' };
  record.review = { required: true, status: 'APPROVED', reviewerId: 'reviewer', reasonCode: 'CHECKS_REVIEWED', reviewedAt: now };
  return record;
}
function evaluate(record) { return evaluateWorkerVerification(record, { workerId: 'worker', account, now }); }
test('versioned policy approves only a complete bound server-evidence fixture', () => {
  const result = evaluate(evidence());
  assert.equal(result.policyVersion, POLICY_VERSION);
  assert.equal(result.status, 'APPROVED'); assert.equal(result.eligible, true);
});
test('strong face alone, borderline, mismatch and face errors cannot approve', () => {
  const bare = newEvidence({ match: true, band: 'strong', distance: 0.4, similarity: 90 }, {
    workerId: 'worker', submissionId: 'attempt', now, thresholds: { autoVerifyMin: 80, reviewMin: 60 },
  });
  assert.equal(evaluate(bare).eligible, false);
  for (const status of ['BORDERLINE', 'NO_MATCH', 'FACE_NOT_DETECTED', 'ERROR', 'NOT_STARTED']) {
    const record = evidence(); record.face.status = status;
    assert.equal(evaluate(record).eligible, false);
  }
});
test('missing, mock, stale, unbound or unvalidated government and liveness evidence fail closed', () => {
  for (const field of ['government', 'liveness']) {
    for (const patch of [null, { provider: 'MOCK' }, { environment: 'MOCK' }, { validatedByBackend: false },
      { userId: 'other' }, { attemptId: 'old-attempt' }, { expiresAt: now }, { validatedAt: 123 }, { reference: '' }]) {
      const record = evidence(); record[field] = patch === null ? undefined : { ...record[field], ...patch };
      assert.equal(evaluate(record).eligible, false, `${field}: ${JSON.stringify(patch)}`);
    }
  }
});
test('required review cannot be disabled or self-approved; account and schema are mandatory', () => {
  for (const patch of [{ required: false, status: 'NOT_REQUIRED' }, { status: 'PENDING' }, { reviewerId: 'worker' }, { reviewedAt: null }]) {
    const record = evidence(); record.review = { ...record.review, ...patch }; assert.equal(evaluate(record).eligible, false);
  }
  const record = evidence(); record.schemaVersion = 1; assert.equal(evaluate(record).eligible, false);
  assert.equal(evaluateWorkerVerification(evidence(), { workerId: 'worker', now }).eligible, false);
  assert.equal(evaluateWorkerVerification(evidence(), { account, now }).eligible, false);
});
test('mock records and contradictory face evidence cannot be relabeled into official eligibility', () => {
  for (const patch of [{ providerType: 'MOCK' }, { checkSource: 'SYNTHETIC_FIXTURE' }]) {
    assert.equal(evaluate({ ...evidence(), ...patch }).eligible, false);
  }
  const record = evidence(); record.face.band = 'borderline';
  assert.equal(evaluate(record).eligible, false);
  record.face.band = 'strong'; record.face.similarity = 79;
  assert.equal(evaluate(record).eligible, false);
});
test('the admin accountStatus suspension field blocks otherwise complete evidence', () => {
  const decision = evaluateWorkerVerification(evidence(), { workerId: 'worker', account: { ...account, accountStatus: 'suspended' }, now });
  assert.equal(decision.eligible, false);
  assert.ok(decision.reasonCodes.includes('WORKER_ACCOUNT_REQUIRED'));
});
test('status writer refuses approval without policy evidence before scheduling any writes', () => {
  const writes = [], db = { collection: name => ({ doc: (id = 'notice') => `${name}/${id}` }) };
  const batch = { set: (...args) => writes.push(args) };
  const incomplete = evidence(); delete incomplete.government;
  assert.throws(() => addStatusWrites(batch, db, 'worker', 'verified', { senderId: 'reviewer', now, evidence: incomplete, account }), { code: 'VERIFICATION_REQUIREMENTS_NOT_MET' });
  assert.throws(() => addStatusWrites(batch, db, 'worker', 'verified', { senderId: 'reviewer', now }), { code: 'LEGACY_VERIFICATION_PROTECTED' });
  assert.deepEqual(writes, []);
  const result = addStatusWrites(batch, db, 'worker', 'verified', { senderId: 'reviewer', now, evidence: evidence(), account });
  assert.equal(result.eligible, true); assert.equal(writes[0][1].verificationStatus, 'verified');
  assert.equal(writes[1][1].verificationStatus, 'verified'); assert.equal(writes[2][1].recipientRole, 'account');
});
test('writer preserves already verified accounts instead of reinterpreting legacy trust', () => {
  assert.throws(() => addStatusWrites({ set: () => assert.fail('No writes') }, {}, 'worker', 'rejected', {
    senderId: 'reviewer', now, evidence: evidence(), account: { ...account, verificationStatus: 'verified' },
  }), { code: 'LEGACY_VERIFICATION_PROTECTED' });
});
