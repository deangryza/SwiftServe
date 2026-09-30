const assert = require('node:assert/strict');
const { test } = require('node:test');
const express = require('express');
const multer = require('multer');
const request = require('supertest');

const createVerificationRouter = require('../src/routes/verificationRoutes');

const createApp = (compare) => {
  const app = express();
  const authenticate = (req, _res, next) => {
    req.user = { uid: 'worker-1' };
    next();
  };
  const noLimit = (_req, _res, next) => next();
  app.use('/api', createVerificationRouter({ authenticate, compare, attemptLimiter: noLimit }));
  app.use((error, _req, res, _next) => {
    if (error?.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ code: 'IMAGE_TOO_LARGE' });
    }
    if (error?.code === 'UNSUPPORTED_IMAGE_TYPE') {
      return res.status(415).json({ code: error.code });
    }
    if (error instanceof multer.MulterError) {
      return res.status(400).json({ code: 'INVALID_UPLOAD' });
    }
    return res.status(500).json({ code: 'INTERNAL_ERROR' });
  });
  return app;
};

const addValidPair = (builder) => builder
  .field('idType', 'Philippine National ID')
  .field('idNumber', '123456789')
  .attach('document', Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00]), { filename: 'id.jpg', contentType: 'image/jpeg' })
  .attach('selfie', Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), { filename: 'selfie.png', contentType: 'image/png' });

test('returns 201 for a passing comparison', async () => {
  const response = await addValidPair(request(createApp(async () => ({
    match: true,
    confidence: 96.25,
    status: 'pending',
  }))).post('/api/verify'));

  assert.equal(response.status, 201);
  assert.deepEqual(response.body, {
    match: true,
    confidence: 96.25,
    verification: { status: 'pending' },
  });
});

test('returns a domain result without persisting a mismatch', async () => {
  let calls = 0;
  const response = await addValidPair(request(createApp(async () => {
    calls += 1;
    return { match: false, confidence: 0 };
  })).post('/api/verify'));

  assert.equal(response.status, 200);
  assert.equal(response.body.code, 'FACE_MISMATCH');
  assert.equal(calls, 1);
});

test('rejects missing files and unsupported media types', async () => {
  const app = createApp(async () => ({ match: true, confidence: 100, status: 'pending' }));
  const missing = await request(app).post('/api/verify')
    .field('idType', 'ID')
    .field('idNumber', '1234');
  assert.equal(missing.status, 400);
  assert.equal(missing.body.code, 'INVALID_UPLOAD');

  const unsupported = await request(app).post('/api/verify')
    .field('idType', 'ID')
    .field('idNumber', '1234')
    .attach('document', Buffer.from('document'), { filename: 'id.gif', contentType: 'image/gif' })
    .attach('selfie', Buffer.from('selfie'), { filename: 'selfie.jpg', contentType: 'image/jpeg' });
  assert.equal(unsupported.status, 415);
  assert.equal(unsupported.body.code, 'UNSUPPORTED_IMAGE_TYPE');
});

test('maps Rekognition no-face and outage errors', async () => {
  for (const [name, expectedStatus, expectedCode] of [
    ['InvalidParameterException', 400, 'FACE_NOT_DETECTED'],
    ['ThrottlingException', 503, 'VERIFICATION_UNAVAILABLE'],
  ]) {
    const error = new Error(name);
    error.name = name;
    const response = await addValidPair(request(createApp(async () => { throw error; })).post('/api/verify'));
    assert.equal(response.status, expectedStatus);
    assert.equal(response.body.code, expectedCode);
  }
});
