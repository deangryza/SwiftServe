const { evaluateWorkerVerification, SCHEMA_VERSION } = require('./workerVerificationPolicy');
// Retained only to identify historical face-only approvals, never for new approval.
const AUTO_REVIEWER = 'auto_face_match';
const FINAL_STATUSES = new Set(['verified', 'rejected']);
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

const isFinalStatus = (status) => FINAL_STATUSES.has(status);

const purgeDateFor = (status, now) => (
  isFinalStatus(status) ? new Date(now.getTime() + RETENTION_MS) : null
);

// `users.verificationStatus` and `worker_profiles.verificationStatus` drive the
// verified badge in the mobile app.
const addStatusWrites = (batch, db, workerId, status, { senderId, now, evidence, account }) => {
  if (evidence?.schemaVersion !== SCHEMA_VERSION || evidence.workerId !== workerId
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
  batch.set(db.collection('worker_profiles').doc(workerId), {
    verificationStatus: status,
    updatedAt: now,
  }, { merge: true });
  batch.set(db.collection('notifications').doc(), {
    recipientId: workerId,
    recipientRole: 'account',
    type: 'verificationUpdated',
    senderId,
    title: 'Verification updated',
    body: `Your worker verification is now ${status.replaceAll('_', ' ')}.`,
    read: false,
    createdAt: now,
  });
  return decision;
};

module.exports = {
  AUTO_REVIEWER,
  evaluateWorkerVerification,
  addStatusWrites,
  isFinalStatus,
  purgeDateFor,
};
