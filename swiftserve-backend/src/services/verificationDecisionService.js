const { evaluateWorkerVerification, SCHEMA_VERSION } = require('./workerVerificationPolicy');
// Retained only to identify historical face-only approvals, never for new approval.
const AUTO_REVIEWER = 'auto_face_match';
const FINAL_STATUSES = new Set(['verified', 'rejected']);
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

const isFinalStatus = (status) => FINAL_STATUSES.has(status);

const purgeDateFor = (status, now) => (
  isFinalStatus(status) ? new Date(now.getTime() + RETENTION_MS) : null
);

// Records older than the current evidence schema can be turned down or sent
// back for a fresh submission, but can never be approved.
const LEGACY_CLOSING_STATUSES = new Set(['rejected', 'resubmission_required']);
const isLegacyClosure = (evidence, workerId, status) => Boolean(evidence)
  && evidence.schemaVersion !== SCHEMA_VERSION && LEGACY_CLOSING_STATUSES.has(status)
  && (evidence.workerId === undefined || evidence.workerId === workerId);

// `users.verificationStatus` and `worker_profiles.verificationStatus` drive the
// verified badge in the mobile app.
const addStatusWrites = (batch, db, workerId, status, { senderId, now, evidence, account }) => {
  const currentEvidence = evidence?.schemaVersion === SCHEMA_VERSION && evidence.workerId === workerId;
  if ((!currentEvidence && !isLegacyClosure(evidence, workerId, status))
      || account?.verificationStatus === 'verified') {
    throw Object.assign(new Error('Legacy records require a separately approved transition.'), { status: 409, code: 'LEGACY_VERIFICATION_PROTECTED' });
  }
  if (!['verified', 'pending', 'under_review', 'rejected', 'resubmission_required'].includes(status)) {
    throw Object.assign(new Error('Unsupported verification status.'), { status: 400, code: 'INVALID_VERIFICATION_STATUS' });
  }
  const decision = evaluateWorkerVerification(evidence, { workerId, account, now });
  if (status === 'verified' && !decision.eligible) {
    throw Object.assign(new Error('Mandatory verification evidence is missing or invalid.'), {
      status: 409, code: 'VERIFICATION_REQUIREMENTS_NOT_MET', reasonCodes: decision.reasonCodes,
    });
  }
  batch.set(db.collection('users').doc(workerId), {
    verificationStatus: status,
    updatedAt: now,
  }, { merge: true });
  // Client-only accounts have no worker profile; never create one for them.
  const isWorker = account?.role === 'worker' || (Array.isArray(account?.roles) && account.roles.includes('worker'));
  if (isWorker || !account) {
    batch.set(db.collection('worker_profiles').doc(workerId), {
      verificationStatus: status,
      updatedAt: now,
    }, { merge: true });
  }
  batch.set(db.collection('notifications').doc(), {
    recipientId: workerId,
    recipientRole: 'account',
    type: 'verificationUpdated',
    senderId,
    title: 'Verification updated',
    body: `Your ${isWorker || !account ? 'worker' : 'account'} verification is now ${status.replaceAll('_', ' ')}.`,
    read: false,
    createdAt: now,
  });
  return decision;
};

module.exports = {
  AUTO_REVIEWER,
  evaluateWorkerVerification,
  addStatusWrites,
  isLegacyClosure,
  isFinalStatus,
  purgeDateFor,
};
