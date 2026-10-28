// Shared by admin review and automatic face-match approval so both paths
// write the same worker status, badge source, and notification.
const AUTO_REVIEWER = 'auto_face_match';
const FINAL_STATUSES = new Set(['verified', 'rejected']);
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

const isFinalStatus = (status) => FINAL_STATUSES.has(status);

const purgeDateFor = (status, now) => (
  isFinalStatus(status) ? new Date(now.getTime() + RETENTION_MS) : null
);

// `users.verificationStatus` and `worker_profiles.verificationStatus` drive the
// verified badge in the mobile app.
const addStatusWrites = (batch, db, workerId, status, { senderId, now }) => {
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
    body: `Your identity verification is now ${status.replaceAll('_', ' ')}.`,
    read: false,
    createdAt: now,
  });
};

module.exports = {
  AUTO_REVIEWER,
  addStatusWrites,
  isFinalStatus,
  purgeDateFor,
};
