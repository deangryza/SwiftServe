import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateHostedStagingTarget } from '../src/lib/hostedStagingTarget.js';
import { validateFirebaseTarget } from '../src/lib/firebaseTarget.js';

const approvedOrigin = 'https://swiftserve-staging.example.test'; // Synthetic, never contacted.
const target = { VITE_SWIFTSERVE_TARGET: 'hosted-staging', VITE_FIREBASE_PROJECT_ID: 'swiftserve-staging-2026',
  VITE_FIRESTORE_DATABASE_ID: '(default)', VITE_USE_FIREBASE_EMULATORS: 'false',
  VITE_FIREBASE_AUTH_DOMAIN: 'swiftserve-staging-2026.firebaseapp.com', VITE_API_BASE_URL: approvedOrigin };
const validate = env => validateHostedStagingTarget(env,{approvedOrigin});

test('inactive staging validator accepts only the exact explicit staging target and approved origin',()=>{
  assert.deepEqual(validate(target),{project:'swiftserve-staging-2026',database:'(default)',emulator:false,apiBaseUrl:approvedOrigin});
  assert.ok(Object.isFrozen(validate(target)));
});
test('staging rejects production, unknown projects and implicit target/database values',()=>{
  for(const patch of [{VITE_SWIFTSERVE_TARGET:undefined},{VITE_SWIFTSERVE_TARGET:'production'},
    {VITE_FIREBASE_PROJECT_ID:'swiftserve-production'},{VITE_FIREBASE_PROJECT_ID:'unknown-project'},
    {VITE_FIREBASE_PROJECT_ID:undefined},{VITE_FIRESTORE_DATABASE_ID:undefined},{VITE_FIRESTORE_DATABASE_ID:'other'},
    {VITE_USE_FIREBASE_EMULATORS:undefined},{VITE_USE_FIREBASE_EMULATORS:'true'},
    {VITE_FIREBASE_AUTH_DOMAIN:'swiftserve-production.firebaseapp.com'}])assert.throws(()=>validate({...target,...patch}));
});
test('staging rejects missing API values, arbitrary API hosts and credential-bearing or non-origin URLs',()=>{
  for(const url of [undefined,'','http://localhost:5000','https://localhost','https://127.0.0.1','https://[::1]',
    'https://other.example.test',approvedOrigin+'/api',approvedOrigin+'/',approvedOrigin+'?q=1',approvedOrigin+'#x',
    'https://username:password@swiftserve-staging.example.test','https://swiftserve-staging.example.test:8443']) {
    assert.throws(()=>validate({...target,VITE_API_BASE_URL:url}));
  }
  assert.throws(()=>validateHostedStagingTarget(target));
});
test('production and emulator validators remain unchanged; staging is not activated',()=>{
  assert.deepEqual(validateFirebaseTarget({VITE_FIREBASE_PROJECT_ID:'swiftserve-production',VITE_API_BASE_URL:'http://localhost:5000'}),{project:'swiftserve-production',emulator:false});
  assert.throws(()=>validateFirebaseTarget(target));
});
