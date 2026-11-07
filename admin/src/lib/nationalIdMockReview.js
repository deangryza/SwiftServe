export const MOCK_IDENTITY_LABEL = 'MOCK / NOT OFFICIALLY VERIFIED';
export function mockReviewRecord(record) {
  return record?.providerType === 'MOCK' && record.officiallyVerified === false &&
    /^mock-v1-[a-f0-9]{64}$/.test(record.verificationReference || '');
}
export function canApproveMock(record) {
  return mockReviewRecord(record) && record.verificationStatus === 'MANUAL_REVIEW' &&
    ['PASSED', 'MANUAL_REVIEW'].includes(record.governmentVerificationStatus) &&
    record.faceVerificationStatus === 'PASSED' && record.livenessStatus === 'PASSED';
}
