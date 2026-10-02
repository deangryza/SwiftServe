const assert = require('node:assert/strict');
const { test } = require('node:test');
const express = require('express');
const multer = require('multer');
const request = require('supertest');

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
  app.use('/api', createVerificationRouter({ authenticate, compare, attemptLimiter }));
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
    return { match: true, confidence: 96.25, distance: 0.0375, status: 'pending' };
  })).post('/api/verify'));

  assert.equal(response.status, 201);
  assert.deepEqual(response.body, {
    match: true,
    confidence: 96.25,
    distance: 0.0375,
    bypassed: false,
    verification: { status: 'pending' },
  });
  assert.equal(files[0].buffer, undefined);
  assert.equal(files[1].buffer, undefined);
});

test('returns a mismatch result with confidence and distance', async () => {
  const response = await addValidPair(request(createApp(async () => ({
    match: false,
    confidence: 31.5,
    distance: 0.685,
  }))).post('/api/verify'));

  assert.equal(response.status, 200);
  assert.deepEqual(response.body, {
    match: false,
    confidence: 31.5,
    distance: 0.685,
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

// TODO(face-verification): temporary ID-only bypass coverage. Remove these
// tests when face matching is re-enabled.
test('accepts an ID-only upload while the face check is disabled', async (t) => {
  const previous = process.env.DISABLE_FACE_VERIFICATION;
  process.env.DISABLE_FACE_VERIFICATION = 'true';
  try {
    const app = createApp(async () => ({
      match: true,
      confidence: null,
      distance: null,
      status: 'pending',
      bypassed: true,
    }));
    const response = await request(app).post('/api/verify')
      .field('idType', 'Philippine National ID')
      .field('idNumber', '123456789')
      .attach('document', Buffer.from([0xff, 0xd8, 0xff, 0, 0, 0, 0, 0]), { filename: 'id.jpg', contentType: 'image/jpeg' });

    assert.equal(response.status, 201);
    assert.deepEqual(response.body, {
      match: true,
      confidence: null,
      distance: null,
      bypassed: true,
      verification: { status: 'pending' },
    });
  } finally {
    if (previous === undefined) delete process.env.DISABLE_FACE_VERIFICATION;
    else process.env.DISABLE_FACE_VERIFICATION = previous;
  }
});
