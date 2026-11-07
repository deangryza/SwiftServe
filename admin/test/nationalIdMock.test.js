import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canApproveMock, mockReviewRecord } from '../src/lib/nationalIdMockReview.js';
import { validateFirebaseTarget } from '../src/lib/firebaseTarget.js';
const sample = { verificationReference: `mock-v1-${'a'.repeat(64)}`, providerType: 'MOCK', officiallyVerified: false,
  verificationStatus: 'MANUAL_REVIEW', governmentVerificationStatus: 'MANUAL_REVIEW', faceVerificationStatus: 'PASSED', livenessStatus: 'PASSED' };
test('review UI accepts only mock records and complete checks', () => {
  assert.equal(canApproveMock(sample), true);
  for (const patch of [{ providerType: 'PSA' }, { officiallyVerified: true }, { livenessStatus: 'UNSUPPORTED' }, { faceVerificationStatus: 'FAILED' }, { governmentVerificationStatus: 'FAILED' }]) assert.equal(canApproveMock({ ...sample, ...patch }), false);
  assert.equal(mockReviewRecord({ ...sample, verificationReference: '../users' }), false);
});
test('identity review target is opt-in, exact demo/default database and local only', () => {
  const env = { DEV: true, VITE_ENABLE_NATIONAL_ID_MOCK: 'true', VITE_USE_FIREBASE_EMULATORS: 'true',
    VITE_FIREBASE_PROJECT_ID: 'demo-swiftserve-cleanup', VITE_FIRESTORE_DATABASE_ID: '(default)', VITE_API_BASE_URL: 'http://127.0.0.1:5007' };
  assert.deepEqual(validateFirebaseTarget(env), { project: env.VITE_FIREBASE_PROJECT_ID, emulator: true });
  for (const patch of [{ DEV: false }, { VITE_FIREBASE_PROJECT_ID: 'swiftserve-production' }, { VITE_FIRESTORE_DATABASE_ID: 'other' }, { VITE_USE_FIREBASE_EMULATORS: 'false' }, { VITE_API_BASE_URL: 'http://127.0.0.1:5000' }]) assert.throws(() => validateFirebaseTarget({ ...env, ...patch }));
});
