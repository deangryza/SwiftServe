const assert = require('node:assert/strict');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const { afterEach, beforeEach, test } = require('node:test');

const {
  createImageHandler,
  localImageUrl,
} = require('../src/controllers/adminVerificationController');

let uploadsDir;

beforeEach(async () => {
  uploadsDir = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-admin-img-'));
});

afterEach(async () => {
  await fs.rm(uploadsDir, { recursive: true, force: true });
});

const databaseFor = (data) => ({
  collection: () => ({
    doc: () => ({
      get: async () => ({
        exists: data !== undefined,
        data: () => data,
      }),
    }),
  }),
});

const mockRes = () => {
  const res = {
    statusCode: 200,
    body: undefined,
    headers: {},
    sent: undefined,
    status(code) { res.statusCode = code; return res; },
    json(value) { res.body = value; return res; },
    setHeader(key, value) { res.headers[key] = value; },
    sendFile(absolute, callback) { res.sent = absolute; callback(); },
  };
  return res;
};

test('streams a locally stored government ID', async () => {
  await fs.mkdir(path.join(uploadsDir, 'worker_verifications/w1/s1'), { recursive: true });
  await fs.writeFile(path.join(uploadsDir, 'worker_verifications/w1/s1/government_id.jpg'), 'img');
  const handler = createImageHandler({
    database: databaseFor({
      storageBackend: 'local',
      governmentIdPath: 'worker_verifications/w1/s1/government_id.jpg',
      governmentIdMimeType: 'image/jpeg',
    }),
    uploadsDir,
  });
  const res = mockRes();
  await handler({ params: { workerId: 'w1' } }, res);

  assert.equal(res.sent, path.resolve(uploadsDir, 'worker_verifications/w1/s1/government_id.jpg'));
  assert.equal(res.headers['Content-Type'], 'image/jpeg');
});

test('rejects missing, non-local, and absent-file images with 404', async () => {
  const missing = createImageHandler({ database: databaseFor(undefined), uploadsDir });
  const missingRes = mockRes();
  await missing({ params: { workerId: 'ghost' } }, missingRes);
  assert.equal(missingRes.statusCode, 404);

  const gcs = createImageHandler({
    database: databaseFor({ storageBackend: 'gcs', governmentIdPath: 'gcs/id.jpg' }),
    uploadsDir,
  });
  const gcsRes = mockRes();
  await gcs({ params: { workerId: 'w1' } }, gcsRes);
  assert.equal(gcsRes.statusCode, 404);

  const gone = createImageHandler({
    database: databaseFor({ storageBackend: 'local', governmentIdPath: 'gone.jpg' }),
    uploadsDir,
  });
  const goneRes = mockRes();
  await gone({ params: { workerId: 'w1' } }, goneRes);
  assert.equal(goneRes.statusCode, 404);
});

test('builds an absolute same-host image URL', () => {
  const req = { protocol: 'http', get: () => 'localhost:5000' };
  assert.equal(
    localImageUrl(req, 'worker-1'),
    'http://localhost:5000/api/admin/verifications/worker-1/image',
  );
});
