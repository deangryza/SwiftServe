// Internal evidence contract, not a PSA API schema. No provider integration here.
const POLICY_VERSION = 'worker-verification-v1';
const SCHEMA_VERSION = 2;
const STATUSES = Object.freeze({
  face: ['NOT_STARTED', 'PROCESSING', 'MATCH', 'BORDERLINE', 'NO_MATCH', 'FACE_NOT_DETECTED', 'ERROR'],
  government: ['NOT_INTEGRATED', 'PENDING', 'AUTHENTICATED', 'NOT_AUTHENTICATED', 'UNAVAILABLE', 'ERROR', 'EXPIRED'],
  liveness: ['NOT_IMPLEMENTED', 'PENDING', 'PASSED', 'FAILED', 'ERROR', 'EXPIRED'],
  review: ['PENDING', 'APPROVED', 'REJECTED'],
  decision: ['PENDING', 'BLOCKED', 'REVIEW_REQUIRED', 'APPROVED', 'REJECTED', 'EXPIRED', 'REVOKED'],
});
const milliseconds = value => value instanceof Date ? value.getTime()
  : value && typeof value.toMillis === 'function' ? value.toMillis() : NaN;
const faceResultFor = comparison => ({
  status: comparison.band === 'strong' && comparison.match === true ? 'MATCH'
    : comparison.band === 'borderline' && comparison.match === true ? 'BORDERLINE'
    : comparison.band === 'mismatch' && comparison.match === false ? 'NO_MATCH' : 'ERROR',
  distance: comparison.distance, similarity: comparison.similarity, band: comparison.band,
});
function newEvidence(comparison, { workerId, submissionId, now, thresholds }) {
  return { schemaVersion: SCHEMA_VERSION, workerId, submissionId,
    face: { ...faceResultFor(comparison), provider: 'local_face_api', source: 'SERVER',
      thresholds: { ...thresholds }, completedAt: now },
    government: { status: 'NOT_INTEGRATED', provider: 'NONE' },
    liveness: { status: 'NOT_IMPLEMENTED' },
    review: { required: true, status: 'PENDING' },
  };
}
function evaluateWorkerVerification(record, { workerId, account, now = new Date() } = {}) {
  const reasons = [], time = milliseconds(now);
  const binding = typeof workerId === 'string' && workerId.length > 0 && workerId.length <= 128
    && record?.schemaVersion === SCHEMA_VERSION && record.workerId === workerId
    && typeof record.submissionId === 'string' && record.submissionId.length > 0 && record.submissionId.length <= 128
    && record.providerType !== 'MOCK' && record.checkSource !== 'SYNTHETIC_FIXTURE';
  if (!binding) reasons.push('EVIDENCE_BINDING_REQUIRED');
  if (!account || !(account.role === 'worker' || (Array.isArray(account.roles) && account.roles.includes('worker')))
      || ['suspended', 'disabled', 'inactive'].includes(account.status)
      || ['suspended', 'disabled', 'inactive'].includes(account.accountStatus)) reasons.push('WORKER_ACCOUNT_REQUIRED');
  const face = record?.face, government = record?.government, live = record?.liveness, review = record?.review;
  if (face?.status !== 'MATCH' || face.source !== 'SERVER' || face.provider !== 'local_face_api' || face.band !== 'strong'
      || !Number.isFinite(face.distance) || face.distance < 0 || !Number.isFinite(face.similarity) || face.similarity > 100
      || !Number.isFinite(face.thresholds?.autoVerifyMin) || face.thresholds.autoVerifyMin < 0 || face.thresholds.autoVerifyMin > 100
      || face.similarity < face.thresholds.autoVerifyMin || !Number.isFinite(milliseconds(face.completedAt))
      || milliseconds(face.completedAt) > time) reasons.push('FACE_MATCH_REQUIRED');
  // Every external result must be backend-validated, live, bound to this exact
  // user/attempt, and unexpired. No endpoint currently produces these proofs.
  const trusted = evidence => binding && evidence?.validatedByBackend === true
    && evidence.environment === 'LIVE' && evidence.userId === workerId
    && evidence.attemptId === record.submissionId
    && typeof evidence.reference === 'string' && evidence.reference.length > 0 && evidence.reference.length <= 256
    && Number.isFinite(time) && milliseconds(evidence.validatedAt) <= time
    && Number.isFinite(milliseconds(evidence.validatedAt)) && milliseconds(evidence.expiresAt) > time;
  const official = government?.status === 'AUTHENTICATED' && government.provider === 'PSA' && trusted(government);
  if (!official) reasons.push('OFFICIAL_GOVERNMENT_AUTHENTICATION_REQUIRED');
  if (!(live?.status === 'PASSED' && live.source === 'SERVER' && typeof live.provider === 'string'
      && live.provider.length > 0 && !['MOCK', 'SYNTHETIC', 'NONE'].includes(live.provider) && trusted(live))) {
    reasons.push('TRUSTED_SERVER_LIVENESS_REQUIRED');
  }
  // Initial policy always requires review. The stored required flag cannot opt out.
  const approvedReview = review?.status === 'APPROVED' && typeof review.reviewerId === 'string'
    && review.reviewerId.length > 0 && review.reviewerId !== workerId
    && typeof review.reasonCode === 'string' && review.reasonCode.length > 0
    && Number.isFinite(milliseconds(review.reviewedAt)) && milliseconds(review.reviewedAt) <= time;
  if (!approvedReview) reasons.push('ADMIN_REVIEW_REQUIRED');
  const rejected = face?.status === 'NO_MATCH' || government?.status === 'NOT_AUTHENTICATED'
    || live?.status === 'FAILED' || review?.status === 'REJECTED';
  const expired = government?.status === 'EXPIRED' || live?.status === 'EXPIRED';
  const status = reasons.length === 0 ? 'APPROVED' : rejected ? 'REJECTED' : expired ? 'EXPIRED'
    : reasons.length === 1 && reasons[0] === 'ADMIN_REVIEW_REQUIRED' ? 'REVIEW_REQUIRED' : 'BLOCKED';
  return { policyVersion: POLICY_VERSION, status, eligible: status === 'APPROVED',
    officiallyVerified: official === true, reasonCodes: reasons, evaluatedAt: now };
}
module.exports = { POLICY_VERSION, SCHEMA_VERSION, STATUSES, faceResultFor, newEvidence, evaluateWorkerVerification };
