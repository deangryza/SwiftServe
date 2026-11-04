const assert = require('node:assert/strict');
const { test } = require('node:test');
const express = require('express');
const multer = require('multer');
const request = require('supertest');

// HTTP unit tests must never initialize ADC or a real Firebase project.
const firebaseConfig = require.resolve('../src/config/firebase');
require.cache[firebaseConfig] = { id: firebaseConfig, filename: firebaseConfig, loaded: true, exports: {
  db: { collection: () => assert.fail('Unexpected database access; inject a synthetic repository') },
  storage: null, auth: { verifyIdToken: () => assert.fail('Inject synthetic authentication') },
} };
const createVerificationRouter = require('../src/routes/verificationRoutes');
const {
  FaceDetectionError,
  VerificationConflictError,
} = require('../src/services/faceVerificationService');

const createApp = (compare, {
  authenticate = (req, _res, next) => { req.user = { uid: 'worker-1' }; next(); },
  attemptLimiter = (_req, _res, next) => next(),
} = {}) => {
  const app = express();
  app.use('/api', createVerificationRouter({ authenticate, compare, attemptLimiter, checkDocument: async () => undefined }));
  app.use((error, _req, res, _next) => {
    if (error?.code === 'LIMIT_FILE_SIZE') return res.status(413).json({ code: 'IMAGE_TOO_LARGE' });
    if (error?.code === 'UNSUPPORTED_IMAGE_TYPE') return res.status(415).json({ code: error.code });
    if (error instanceof multer.MulterError) return res.status(400).json({ code: 'INVALID_UPLOAD' });
    return res.status(500).json({ code: 'INTERNAL_ERROR' });
  });
  return app;
};

const addValidPair = (builder) => builder
  .field('idType', 'Philippine National ID')
  .field('idNumber', '123456789')
  .attach('document', Buffer.from([0xff, 0xd8, 0xff, 0, 0, 0, 0, 0]), { filename: 'id.jpg', contentType: 'image/jpeg' })
  .attach('selfie', Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), { filename: 'selfie.png', contentType: 'image/png' });

test('returns the distance contract and clears buffers after a passing comparison', async () => {
  let files;
  const response = await addValidPair(request(createApp(async (value) => {
    files = [value.document, value.selfie];
    return { match: true, band: 'strong', similarity: 96.25, confidence: 96.25, distance: 0.0375, status: 'pending',
      faceResult: { status: 'MATCH' }, workerDecision: { eligible: false, status: 'BLOCKED' } };
  })).post('/api/verify'));

  assert.equal(response.status, 201);
  assert.deepEqual(response.body, {
    match: true,
    similarity: 96.25,
    confidence: 96.25,
    distance: 0.0375,
    band: 'strong',
    faceResult: { status: 'MATCH' },
    workerDecision: { eligible: false, status: 'BLOCKED' },
    governmentStatus: 'NOT_INTEGRATED', livenessStatus: 'NOT_IMPLEMENTED', reviewStatus: 'PENDING',
    verification: { status: 'pending' },
  });
  assert.equal(files[0].buffer, undefined);
  assert.equal(files[1].buffer, undefined);
});

test('requester comparison-only route uses existing comparator without persistence or worker writes', async () => {
  let compared = 0;
  const database = { collection: name => { assert.equal(name, 'users'); return { doc: uid => {
    assert.equal(uid, 'client'); return { get: async () => ({ data: () => ({ role: 'client' }) }) };
  } }; } };
  const app = express(); app.use('/api', createVerificationRouter({ database, checkDocument: async () => undefined,
    authenticate: (req, _res, next) => { req.user = { uid: 'client' }; next(); },
    attemptLimiter: (_req, _res, next) => next(),
    compare: () => assert.fail('Requester must never create worker submission'),
    faceCompare: async () => { compared++; return { match: true, band: 'strong', similarity: 90, confidence: 90, distance: 0.4 }; },
  }));
  const response = await addValidPair(request(app).post('/api/verify/face')).expect(201);
  assert.equal(compared, 1); assert.equal(response.body.faceResult.status, 'MATCH');
  assert.equal(response.body.workerDecision.eligible, false);
  assert.equal(response.body.workerDecision.status, 'NOT_APPLICABLE');
  assert.equal(response.body.workerDecision.officiallyVerified, false);
});

test('comparison-only rejects missing, inactive and conflicting account states before inference', async () => {
  for (const profile of [undefined, { role: 'admin' }, { role: 'client', accountStatus: 'active', status: 'suspended' }, { role: 'worker', accountStatus: 'disabled', status: 'active' }]) {
    const app = express(); app.use('/api', createVerificationRouter({ checkDocument: async () => undefined,
      database: { collection: () => ({ doc: () => ({ get: async () => ({ data: () => profile }) }) }) },
      authenticate: (req, _res, next) => { req.user = { uid: 'synthetic-user' }; next(); },
      attemptLimiter: (_req, _res, next) => next(),
      compare: () => assert.fail('Must not persist'),
      faceCompare: () => assert.fail('Must reject before inference'),
    }));
    await addValidPair(request(app).post('/api/verify/face')).expect(403);
  }
});

test('client-submitted verification, government, liveness and face verdicts are rejected', async () => {
  let calls = 0;
  const app = createApp(async () => { calls++; throw new Error('Must not compare'); });
  for (const field of ['verificationStatus', 'government', 'liveness', 'face', 'workerDecision', 'quality', 'qualityVerdict']) {
    const response = await request(app).post('/api/verify').field('idType', 'National ID').field(field, 'verified')
      .attach('document', Buffer.from([255,216,255,0,0,0,0,0]), { filename: 'id.jpg', contentType: 'image/jpeg' })
      .attach('selfie', Buffer.from([255,216,255,0,0,0,0,0]), { filename: 'selfie.jpg', contentType: 'image/jpeg' });
    assert.equal(response.status, 400); assert.equal(response.body.code, 'INVALID_VERIFICATION_FIELDS');
  }
  assert.equal(calls, 0);
});

test('returns a mismatch result with confidence and distance', async () => {
  const response = await addValidPair(request(createApp(async () => ({
    match: false,
    band: 'mismatch',
    similarity: 31.5,
    confidence: 31.5,
    distance: 0.685,
  }))).post('/api/verify'));

  assert.equal(response.status, 200);
  assert.deepEqual(response.body, {
    match: false,
    similarity: 31.5,
    confidence: 31.5,
    distance: 0.685,
    band: 'mismatch',
    code: 'FACE_MISMATCH',
  });
});

test('maps face-count failures with the affected image', async () => {
  for (const [code, image] of [
    ['FACE_NOT_DETECTED', 'document'],
    ['MULTIPLE_FACES_DETECTED', 'selfie'],
  ]) {
    const response = await addValidPair(request(createApp(async () => {
      throw new FaceDetectionError(code, image);
    })).post('/api/verify'));
    assert.equal(response.status, 400);
    assert.equal(response.body.code, code);
    assert.equal(response.body.image, image);
    assert.ok(response.body.message);
  }
});

test('rejects missing, spoofed, unsupported, and oversized uploads', async () => {
  const app = createApp(async () => ({ match: true, confidence: 100, distance: 0, status: 'pending' }));
  const missing = await request(app).post('/api/verify').field('idType', 'ID').field('idNumber', '1234');
  assert.equal(missing.status, 400);
  assert.equal(missing.body.code, 'INVALID_UPLOAD');

  const spoofed = await request(app).post('/api/verify')
    .field('idType', 'ID').field('idNumber', '1234')
    .attach('document', Buffer.from('not jpeg'), { filename: 'id.jpg', contentType: 'image/jpeg' })
    .attach('selfie', Buffer.from('not jpeg'), { filename: 'selfie.jpg', contentType: 'image/jpeg' });
  assert.equal(spoofed.status, 415);

  const unsupported = await request(app).post('/api/verify')
    .field('idType', 'ID').field('idNumber', '1234')
    .attach('document', Buffer.from('document'), { filename: 'id.gif', contentType: 'image/gif' })
    .attach('selfie', Buffer.from('selfie'), { filename: 'selfie.jpg', contentType: 'image/jpeg' });
  assert.equal(unsupported.status, 415);

  const oversized = await request(app).post('/api/verify')
    .field('idType', 'ID').field('idNumber', '1234')
    .attach('document', Buffer.alloc((5 * 1024 * 1024) + 1, 1), { filename: 'id.jpg', contentType: 'image/jpeg' })
    .attach('selfie', Buffer.from([0xff, 0xd8, 0xff, 0, 0, 0, 0, 0]), { filename: 'selfie.jpg', contentType: 'image/jpeg' });
  assert.equal(oversized.status, 413);
});

test('preserves authentication, rate-limit, conflict, and generic failure responses', async () => {
  const unauthorized = await addValidPair(request(createApp(async () => ({}), {
    authenticate: (_req, res) => res.status(401).json({ code: 'UNAUTHENTICATED' }),
  })).post('/api/verify'));
  assert.equal(unauthorized.status, 401);

  const limited = await addValidPair(request(createApp(async () => ({}), {
    attemptLimiter: (_req, res) => res.status(429).json({ code: 'RATE_LIMITED' }),
  })).post('/api/verify'));
  assert.equal(limited.status, 429);

  const conflict = await addValidPair(request(createApp(async () => {
    throw new VerificationConflictError('Already pending.');
  })).post('/api/verify'));
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.code, 'VERIFICATION_CONFLICT');

  const unexpected = await addValidPair(request(createApp(async () => {
    throw new Error('inference failed');
  })).post('/api/verify'));
  assert.equal(unexpected.status, 500);
  assert.equal(unexpected.body.code, 'INTERNAL_ERROR');
});

test('requires a selfie alongside the ID document', async () => {
  const app = createApp(async () => { throw new Error('comparison must not run'); });
  const response = await request(app).post('/api/verify')
    .field('idType', 'Philippine National ID')
    .field('idNumber', '123456789')
    .attach('document', Buffer.from([0xff, 0xd8, 0xff, 0, 0, 0, 0, 0]), { filename: 'id.jpg', contentType: 'image/jpeg' });

  assert.equal(response.status, 400);
  assert.equal(response.body.code, 'INVALID_UPLOAD');
});

test('invalid descriptors surface as processing failure, never a match or verification response', async () => {
  const { compareDescriptors } = require('../src/services/faceVerificationService');
  let files;
  const response = await addValidPair(request(createApp(async input => {
    files = [input.document, input.selfie];
    return compareDescriptors(new Float32Array(128), new Float32Array(128));
  })).post('/api/verify')).expect(500);
  assert.equal(response.body.code, 'INTERNAL_ERROR');
  assert.equal(response.body.match, undefined);
  assert.equal(response.body.verification, undefined);
  assert.ok(files.every(file => file.buffer === undefined));
});

test('quality rejection returns actionable 422 without a match, score or verification verdict', async () => {
  const { CaptureQualityError } = require('../src/services/captureQualityService');
  let files;
  const response = await addValidPair(request(createApp(async input => {
    files = [input.document, input.selfie]; throw new CaptureQualityError('TOO_BLURRY', 'selfie');
  })).post('/api/verify')).expect(422);
  assert.equal(response.body.code, 'IMAGE_QUALITY');
  assert.equal(response.body.reason, 'TOO_BLURRY');
  assert.equal(response.body.image, 'selfie');
  assert.match(response.body.message, /steady/);
  assert.equal(response.body.match, undefined); assert.equal(response.body.similarity, undefined);
  assert.equal(response.body.verification, undefined); assert.ok(files.every(file => file.buffer === undefined));
});
