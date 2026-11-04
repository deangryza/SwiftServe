import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateFirebaseTarget } from '../src/lib/firebaseTarget.js';
const cloud = { VITE_FIREBASE_PROJECT_ID: 'swiftserve-production', VITE_API_BASE_URL: 'http://127.0.0.1:5000' };
test('production target is explicit and does not enable emulators', () => {
  assert.deepEqual(validateFirebaseTarget(cloud), { project: 'swiftserve-production', emulator: false });
  assert.throws(() => validateFirebaseTarget({ ...cloud, VITE_FIREBASE_PROJECT_ID: 'unexpected-project' }));
});
test('emulator requires development and the isolated demo project', () => {
  const demo = { DEV: true, VITE_USE_FIREBASE_EMULATORS: 'true', VITE_FIREBASE_PROJECT_ID: 'demo-swiftserve-admin-management', VITE_API_BASE_URL: 'http://127.0.0.1:5003' };
  assert.equal(validateFirebaseTarget(demo).emulator, true);
  assert.throws(() => validateFirebaseTarget({ ...demo, DEV: false }));
  assert.throws(() => validateFirebaseTarget({ ...demo, VITE_FIREBASE_PROJECT_ID: 'swiftserve-production' }));
  assert.equal(validateFirebaseTarget({ ...demo, VITE_FIREBASE_PROJECT_ID: 'demo-swiftserve-netlify', VITE_API_BASE_URL: 'http://localhost:8888' }).emulator, true);
});
test('cloud tokens cannot be sent to demo API or insecure remote API', () => {
  assert.throws(() => validateFirebaseTarget({ ...cloud, VITE_API_BASE_URL: 'http://127.0.0.1:5003' }));
  assert.throws(() => validateFirebaseTarget({ ...cloud, VITE_API_BASE_URL: 'http://example.test' }));
  assert.doesNotThrow(() => validateFirebaseTarget({ ...cloud, VITE_API_BASE_URL: 'https://example.test' }));
});
