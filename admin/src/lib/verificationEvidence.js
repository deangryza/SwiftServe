const reasons = {
  DOCUMENT_REVIEW_REQUIRED: 'Document suitability review is required for this evidence attempt.',
  FACE_MATCH_REQUIRED: 'An acceptable face match is required.',
  OFFICIAL_GOVERNMENT_AUTHENTICATION_REQUIRED: 'Official government authentication is missing, invalid or expired.',
  TRUSTED_SERVER_LIVENESS_REQUIRED: 'Trusted server-side liveness is missing, invalid or expired.',
  ADMIN_REVIEW_REQUIRED: 'Administrative review is required.',
  EVIDENCE_BINDING_REQUIRED: 'Evidence ownership, attempt or source is invalid.',
  WORKER_ACCOUNT_REQUIRED: 'An eligible worker account is required.',
};
export const isMockEvidence = record => record?.providerType === 'MOCK' || record?.checkSource === 'SYNTHETIC_FIXTURE';
export const canReviewEvidence = (record, canManage) => canManage === true && record?.reviewable === true && !isMockEvidence(record);
export const canApproveEvidence = (record, canManage) => canReviewEvidence(record, canManage) && record.approvalReady === true;
export function verificationRows(record) {
  const mock = isMockEvidence(record);
  return [
    ['Evidence source', mock ? 'MOCK / NOT OFFICIALLY VERIFIED' : record.schemaVersion === 2 ? 'Backend checks' : 'Legacy record — no official PSA claim'],
    ['Document suitability', record.documentSuitabilityBound === true ? 'Reviewed attempt attached; current acceptance is rechecked by the backend' : record.status === 'verified' ? 'Legacy record — not retroactively reviewed' : 'DOCUMENT REVIEW REQUIRED'],
    ['Face matching', record.face?.status || ({ strong: 'FACE MATCHED', borderline: 'BORDERLINE', mismatch: 'NO MATCH' }[record.faceMatchBand]) || 'NOT RECORDED'],
    ['QR scan / format', 'DEMO ONLY — client-side format check; not authentication evidence'],
    ['Government authentication', !mock && record.officialGovernmentAuthenticated === true ? 'OFFICIAL AUTHENTICATION RECORDED' : 'PSA NOT INTEGRATED / NOT OFFICIALLY VERIFIED'],
    ['Server-side liveness', record.livenessStatus === 'PASSED' ? mock ? 'MOCK PASS ONLY' : 'SERVER PASS RECORDED' : 'LIVENESS NOT AVAILABLE / NOT PASSED'],
    ['Administrative review', record.reviewStatus || 'PENDING'],
    ['Worker eligibility', mock ? 'NO PRIVILEGES FROM MOCK' : record.workerDecision?.status || (record.status === 'verified' ? 'LEGACY WORKER ACCESS RETAINED' : 'PENDING')],
  ];
}
export const verificationBlockers = record => (record.policyReasons || []).map(code => reasons[code] || 'Required backend evidence is unavailable.');
