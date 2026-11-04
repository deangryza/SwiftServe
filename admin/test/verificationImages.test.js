import {test} from 'node:test';
import assert from 'node:assert/strict';
import {usesProtectedImages,protectedImagePath} from '../src/lib/verificationImages.js';
test('Blobs images use authenticated fetching just like private local files',()=>{
  assert.equal(usesProtectedImages('netlify-blobs'),true);assert.equal(usesProtectedImages('local'),true);assert.equal(usesProtectedImages('gcs'),false);
});
test('private image path preserves selfie selection and rejects arbitrary resource paths',()=>{
  assert.equal(protectedImagePath('https://example.test/api/admin/verifications/worker/image?kind=selfie'),'/api/admin/verifications/worker/image?kind=selfie');
  assert.equal(protectedImagePath('/api/admin/verifications/worker/image'),'/api/admin/verifications/worker/image');
  assert.throws(()=>protectedImagePath('/api/admin/users'));assert.throws(()=>protectedImagePath('/api/admin/verifications/worker/image?key=secret'));
});
