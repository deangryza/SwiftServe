const assert = require('node:assert/strict');
const { test } = require('node:test');

const {
  compareAndCreateSubmission,
  maskIdNumber,
} = require('../src/services/faceVerificationService');

const fixtures = ({ secondUploadFails = false } = {}) => {
  let storedRecord;
  const deleted = [];
  let saves = 0;
  const files = new Map();
  const bucket = {
    file(path) {
      if (!files.has(path)) {
        files.set(path, {
          async save() {
            saves += 1;
            if (secondUploadFails && saves === 2) throw new Error('upload failed');
          },
          async delete() { deleted.push(path); },
          async setMetadata() {},
        });
      }
      return files.get(path);
    },
  };
  const db = {
    collection(name) {
      return {
        doc() {
          if (name === 'users') {
            return { get: async () => ({ exists: true, data: () => ({ role: 'worker', verificationStatus: 'pending' }) }) };
          }
          return {
            get: async () => ({ exists: false, data: () => undefined }),
            set: async (value) => { storedRecord = value; },
          };
        },
      };
    },
  };
  return {
    db,
    storage: { bucket: () => bucket },
    deleted,
    record: () => storedRecord,
  };
};

const input = (fixture, rekognition) => ({
  uid: 'worker-1',
  idType: 'National ID',
  idNumber: '123456789',
  document: { buffer: Buffer.from('id'), mimetype: 'image/jpeg' },
  selfie: { buffer: Buffer.from('face'), mimetype: 'image/png' },
  db: fixture.db,
  storage: fixture.storage,
  rekognition,
  threshold: 80,
  now: () => new Date('2026-01-01T00:00:00.000Z'),
});

test('stores only masked ID data after a passing comparison', async () => {
  const fixture = fixtures();
  const result = await compareAndCreateSubmission(input(fixture, {
    send: async () => ({ FaceMatches: [{ Similarity: 97.5 }] }),
  }));

  assert.equal(result.match, true);
  assert.equal(fixture.record().maskedIdNumber, '********6789');
  assert.equal(Object.values(fixture.record()).includes('123456789'), false);
  assert.equal(fixture.record().faceVerified, true);
  assert.equal(fixture.record().status, 'pending');
});

test('does not upload anything for a mismatch', async () => {
  const fixture = fixtures();
  const result = await compareAndCreateSubmission(input(fixture, {
    send: async () => ({ FaceMatches: [] }),
  }));

  assert.deepEqual(result, { match: false, confidence: 0 });
  assert.equal(fixture.record(), undefined);
});

test('removes the first object when the second upload fails', async () => {
  const fixture = fixtures({ secondUploadFails: true });
  await assert.rejects(
    compareAndCreateSubmission(input(fixture, {
      send: async () => ({ FaceMatches: [{ Similarity: 90 }] }),
    })),
    /upload failed/,
  );
  assert.equal(fixture.deleted.length, 1);
  assert.equal(fixture.record(), undefined);
});

test('masks short and long identifiers consistently', () => {
  assert.equal(maskIdNumber('123'), '********123');
  assert.equal(maskIdNumber('123456789'), '********6789');
});

