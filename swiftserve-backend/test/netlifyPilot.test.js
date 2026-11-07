const { test } = require('node:test');
const assert = require('node:assert/strict');
const { environment } = require('../scripts/startNetlifyPilot');
const { validatePilot, PROJECT } = require('../src/config/netlifyPilot');
const { createBlobStorage, localFetch } = require('../src/services/netlifyVerificationStorage');
const { inspectImage, MAX_BYTES } = require('../src/services/verificationImagePolicy');
test('pilot requires exact demo project, default database, loopback emulators and disabled gates', () => {
  const env = environment(); assert.equal(validatePilot(env), PROJECT);
  for (const changes of [{ GOOGLE_CLOUD_PROJECT: 'swiftserve-production' }, { FIREBASE_PROJECT_ID: 'swiftserve-staging-2026' },
    { FIRESTORE_DATABASE_ID: 'other' }, { FIREBASE_AUTH_EMULATOR_HOST: '' }, { FIRESTORE_EMULATOR_HOST: 'example.test:8080' },
    { NETLIFY_DEV: 'false' }, { GOOGLE_APPLICATION_CREDENTIALS: 'key.json' }, { EXPIRED_JOB_CLEANUP_ENABLED: 'true' },
    { PUSH_DELIVERY_ENABLED: 'true' }, { SWIFTSERVE_SUPER_ADMIN_UIDS: 'any' }, { NETLIFY_AUTH_TOKEN: 'any' }]) {
    assert.throws(() => validatePilot({ ...env, ...changes }));
  }
});
test('function rejects non-local configuration before loading Firebase', async () => {
  const { handler } = require('../netlify/functions/api');
  assert.equal((await handler({}, {})).statusCode, 503);
});
test('Blobs cannot target production or make any remote HTTP request', async () => {
  assert.throws(() => createBlobStorage({ project: 'swiftserve-production' }));
  assert.throws(() => createBlobStorage({ project: PROJECT, environment: 'production' }));
  assert.throws(() => localFetch('https://api.netlify.com/anything'));
  assert.throws(() => localFetch('http://example.test/anything'));
});
test('image policy rejects wrong type, oversized payloads, malformed headers and excessive dimensions', () => {
  const image = Buffer.alloc(40); Buffer.from([137,80,78,71,13,10,26,10]).copy(image); image.writeUInt32BE(13,8);image.write('IHDR',12);image.writeUInt32BE(32,16);image.writeUInt32BE(32,20);
  assert.equal(inspectImage({ buffer: image, mimetype: 'image/png' }).width,32);
  assert.throws(() => inspectImage({ buffer: image, mimetype: 'image/svg+xml' }));
  assert.throws(() => inspectImage({ buffer: Buffer.alloc(MAX_BYTES+1), mimetype: 'image/png' }));
  image.writeUInt32BE(50000,16); assert.throws(() => inspectImage({ buffer: image, mimetype: 'image/png' }));
  assert.throws(() => inspectImage({ buffer: Buffer.alloc(30), mimetype: 'image/jpeg' }));
});
