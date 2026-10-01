const assert = require('node:assert/strict');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const { afterEach, beforeEach, test } = require('node:test');

const {
  isLocalStorage,
  removeLocalPaths,
  removeStoredFiles,
  saveLocalBuffer,
  sendLocalFile,
  toAbsolutePath,
} = require('../src/services/verificationStorageService');

let uploadsDir;

beforeEach(async () => {
  uploadsDir = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-uploads-'));
});

afterEach(async () => {
  await fs.rm(uploadsDir, { recursive: true, force: true });
});

test('saves and removes a buffer under the uploads directory', async () => {
  const stored = await saveLocalBuffer('worker_verifications/w1/s1/government_id.jpg', Buffer.from('id-bytes'), uploadsDir);
  assert.equal(stored, 'worker_verifications/w1/s1/government_id.jpg');
  assert.equal(await fs.readFile(path.join(uploadsDir, stored), 'utf8'), 'id-bytes');

  await removeLocalPaths([stored], uploadsDir);
  await assert.rejects(fs.access(path.join(uploadsDir, stored)));

  // Removing a missing file is a no-op.
  await removeLocalPaths([stored], uploadsDir);
});

test('rejects paths escaping the uploads directory', () => {
  assert.throws(() => toAbsolutePath('../outside.jpg', uploadsDir), /Invalid storage path/);
  assert.throws(() => toAbsolutePath('a/../../outside.jpg', uploadsDir), /Invalid storage path/);
});

test('removeStoredFiles branches by backend', async () => {
  const stored = await saveLocalBuffer('w/s/government_id.jpg', Buffer.from('x'), uploadsDir);
  const deleted = [];
  const storage = {
    bucket: () => ({
      file: (filePath) => ({
        delete: async () => { deleted.push(filePath); },
      }),
    }),
  };

  await removeStoredFiles({ paths: [stored], backend: 'local', uploadsDir });
  await assert.rejects(fs.access(path.join(uploadsDir, stored)));

  await removeStoredFiles({ paths: ['gcs/id.jpg', null], backend: 'gcs', storage });
  assert.deepEqual(deleted, ['gcs/id.jpg']);

  await removeStoredFiles({ paths: [] });
  await removeStoredFiles();
});

test('sendLocalFile streams an existing file and reports misses', async () => {
  const stored = await saveLocalBuffer('w/s/government_id.jpg', Buffer.from('img'), uploadsDir);
  const headers = {};
  const res = {
    setHeader: (key, value) => { headers[key] = value; },
    sendFile: (absolute, callback) => { res.sent = absolute; callback(); },
  };

  assert.equal(await sendLocalFile(res, stored, { uploadsDir, contentType: 'image/jpeg' }), true);
  assert.equal(headers['Content-Type'], 'image/jpeg');
  assert.equal(res.sent, path.resolve(uploadsDir, 'w/s/government_id.jpg'));

  assert.equal(await sendLocalFile(res, 'missing.jpg', { uploadsDir }), false);
  assert.equal(await sendLocalFile(res, '../outside.jpg', { uploadsDir }), false);
});

test('local mode is the default until VERIFICATION_STORAGE=gcs', () => {
  const previous = process.env.VERIFICATION_STORAGE;
  try {
    delete process.env.VERIFICATION_STORAGE;
    assert.equal(isLocalStorage(), true);
    process.env.VERIFICATION_STORAGE = 'gcs';
    assert.equal(isLocalStorage(), false);
  } finally {
    if (previous === undefined) delete process.env.VERIFICATION_STORAGE;
    else process.env.VERIFICATION_STORAGE = previous;
  }
});
