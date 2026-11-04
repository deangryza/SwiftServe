import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canReviewDocument, documentDecision } from '../src/lib/documentReview.js';
const record = { sessionId:'synthetic-session', attemptId:'synthetic-attempt', status:'DOCUMENT_REVIEW_REQUIRED', mock:false };
test('only pending non-mock evidence and explicit manage permission enable document decisions', () => {
  assert.equal(canReviewDocument(record,true),true);
  for(const item of [null,{...record,mock:true},{...record,status:'DOCUMENT_ACCEPTED'},{...record,status:'DOCUMENT_REJECTED'}])assert.equal(canReviewDocument(item,true),false);
  assert.equal(canReviewDocument(record,false),false);
});
test('review payload binds session and attempt and cannot carry government/liveness or worker decisions',()=>{
  const result=documentDecision(record,'DOCUMENT_ACCEPTED','SUITABLE');
  assert.deepEqual(result,{sessionId:'synthetic-session',attemptId:'synthetic-attempt',status:'DOCUMENT_ACCEPTED',reasonCode:'SUITABLE'});
  assert.throws(()=>documentDecision(record,'verified','SUITABLE'));
  assert.throws(()=>documentDecision(record,'DOCUMENT_ACCEPTED','UNREADABLE'));
  assert.throws(()=>documentDecision({},'DOCUMENT_ACCEPTED','SUITABLE'));
});
