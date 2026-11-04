export const canReviewDocument = (record, canManage) => canManage === true && record?.status === 'DOCUMENT_REVIEW_REQUIRED' && record.mock !== true;
export function documentDecision(record, status, reasonCode) {
  const allowed = { DOCUMENT_ACCEPTED: ['SUITABLE'], DOCUMENT_REJECTED: ['NOT_SUPPORTED','INCOMPLETE'], DOCUMENT_UNREADABLE: ['UNREADABLE'] };
  if (!allowed[status]?.includes(reasonCode) || !record?.sessionId || !record?.attemptId) throw new Error('Invalid document decision');
  return { status, reasonCode, sessionId: record.sessionId, attemptId: record.attemptId };
}
