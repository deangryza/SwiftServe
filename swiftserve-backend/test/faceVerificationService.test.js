const assert = require('node:assert/strict');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const { afterEach, test } = require('node:test');

const {
  FACE_MATCH_THRESHOLD,
  MODEL_FILES,
  FaceDetectionError,
  compareAndCreateSubmission,
  compareDescriptors,
  getFaceDescriptor,
  loadModels,
  maskIdNumber,
  resetModelStateForTests,
  validateModelFiles,
  verifyFaces,
} = require('../src/services/faceVerificationService');

afterEach(resetModelStateForTests);

const fixtures = ({ secondUploadFails = false, prior } = {}) => {
  let storedRecord;
  const deleted = [];
  const metadata = [];
  let saves = 0;
  const files = new Map();
  const bucket = {
    file(filePath) {
      if (!files.has(filePath)) {
        files.set(filePath, {
          async save() {
            saves += 1;
            if (secondUploadFails && saves === 2) throw new Error('upload failed');
          },
          async delete() { deleted.push(filePath); },
          async setMetadata(value) { metadata.push([filePath, value]); },
        });
      }
      return files.get(filePath);
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
            get: async () => ({ exists: Boolean(prior), data: () => prior }),
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
    metadata,
    record: () => storedRecord,
  };
};

const input = (fixture, verify) => ({
  uid: 'worker-1',
  idType: 'National ID',
  idNumber: '123456789',
  document: { buffer: Buffer.from('id'), mimetype: 'image/jpeg' },
  selfie: { buffer: Buffer.from('face'), mimetype: 'image/png' },
  db: fixture.db,
  storage: fixture.storage,
  verify,
  now: () => new Date('2026-01-01T00:00:00.000Z'),
});

const comparison = (match = true) => ({ match, confidence: 75, distance: 0.25 });

test('loads each model once and validates all required model files', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-models-'));
  try {
    await Promise.all(MODEL_FILES.map((filename) => fs.writeFile(path.join(directory, filename), 'model')));
    const calls = [];
    const network = (name) => ({ loadFromDisk: async (value) => calls.push([name, value]) });
    const runtime = {
      tf: { setBackend: async () => true, ready: async () => undefined },
      faceapi: { nets: {
        ssdMobilenetv1: network('detector'),
        faceLandmark68Net: network('landmarks'),
        faceRecognitionNet: network('recognition'),
      } },
    };
    const first = loadModels({ modelsPath: directory, runtime });
    const second = loadModels({ modelsPath: directory, runtime });
    const [firstRuntime, secondRuntime] = await Promise.all([first, second]);
    assert.equal(firstRuntime, runtime);
    assert.equal(secondRuntime, runtime);
    assert.equal(calls.length, 3);
    assert.ok(calls.every(([, value]) => value === directory));
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('rejects missing or empty model artifacts and permits a retry', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-models-'));
  try {
    await fs.writeFile(path.join(directory, MODEL_FILES[0]), '');
    await assert.rejects(validateModelFiles(directory), /missing or empty/);
    await assert.rejects(loadModels({ modelsPath: directory, runtime: {} }), /models:download/);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test('extracts one descriptor and rejects zero or multiple faces with image attribution', async () => {
  const runtimeFor = (detections) => ({
    loadImage: async (buffer) => ({ buffer }),
    faceapi: {
      detectAllFaces() {
        return {
          withFaceLandmarks() { return this; },
          async withFaceDescriptors() { return detections; },
        };
      },
    },
  });

  const expected = Float32Array.from([0.1, 0.2]);
  assert.equal(
    await getFaceDescriptor(Buffer.from('image'), 'document', runtimeFor([{ descriptor: expected }])),
    expected,
  );

  await assert.rejects(
    getFaceDescriptor(Buffer.from('image'), 'document', runtimeFor([])),
    (error) => error instanceof FaceDetectionError
      && error.code === 'FACE_NOT_DETECTED'
      && error.image === 'document',
  );
  await assert.rejects(
    getFaceDescriptor(Buffer.from('image'), 'selfie', runtimeFor([{}, {}])),
    (error) => error instanceof FaceDetectionError
      && error.code === 'MULTIPLE_FACES_DETECTED'
      && error.image === 'selfie',
  );
});

test('compares descriptors at the exact threshold and clamps heuristic confidence', () => {
  assert.deepEqual(compareDescriptors([0], [FACE_MATCH_THRESHOLD]), {
    match: true,
    distance: 0.6,
    confidence: 40,
  });
  assert.deepEqual(compareDescriptors([0], [0.600001]), {
    match: false,
    distance: 0.600001,
    confidence: 40,
  });
  assert.equal(compareDescriptors([0], [2]).confidence, 0);
  assert.equal(compareDescriptors([1], [1]).confidence, 100);
  assert.throws(() => compareDescriptors([0], [0, 1]), /equal lengths/);
  assert.throws(() => compareDescriptors([Number.NaN], [0]), /finite/);
});

test('orchestrates document then selfie descriptors', async () => {
  const images = [];
  const result = await verifyFaces(Buffer.from('id'), Buffer.from('selfie'), {
    descriptor: async (_buffer, image) => {
      images.push(image);
      return image === 'document' ? [0, 0] : [0.3, 0.4];
    },
  });
  assert.deepEqual(images, ['document', 'selfie']);
  assert.deepEqual(result, { match: true, distance: 0.5, confidence: 50 });
});

test('stores local comparison metadata and only a masked identifier after a match', async () => {
  const fixture = fixtures();
  const result = await compareAndCreateSubmission(input(fixture, async () => comparison()));

  assert.equal(result.match, true);
  assert.equal(result.status, 'pending');
  assert.equal(fixture.record().maskedIdNumber, '********6789');
  assert.equal(Object.values(fixture.record()).includes('123456789'), false);
  assert.equal(fixture.record().faceVerificationProvider, 'local_face_api');
  assert.equal(fixture.record().faceDistance, 0.25);
  assert.equal(fixture.record().faceMatchConfidence, 75);
  assert.equal(fixture.record().faceMatchThreshold, 0.6);
});

test('does not upload or store a mismatch', async () => {
  const fixture = fixtures();
  const result = await compareAndCreateSubmission(input(fixture, async () => comparison(false)));

  assert.deepEqual(result, comparison(false));
  assert.equal(fixture.record(), undefined);
});

test('removes partial uploads and schedules replaced images for deletion', async () => {
  const failed = fixtures({ secondUploadFails: true });
  await assert.rejects(
    compareAndCreateSubmission(input(failed, async () => comparison())),
    /upload failed/,
  );
  assert.equal(failed.deleted.length, 1);
  assert.equal(failed.record(), undefined);

  const replacement = fixtures({
    prior: {
      status: 'rejected',
      governmentIdPath: 'old/id.jpg',
      facePhotoPath: 'old/selfie.jpg',
    },
  });
  await compareAndCreateSubmission(input(replacement, async () => comparison()));
  assert.deepEqual(replacement.metadata.map(([filePath]) => filePath), ['old/id.jpg', 'old/selfie.jpg']);
});

test('masks short and long identifiers consistently', () => {
  assert.equal(maskIdNumber('123'), '********123');
  assert.equal(maskIdNumber('123456789'), '********6789');
});

// TODO(face-verification): temporary ID-only bypass coverage. Remove when
// face matching is re-enabled.
test('creates an ID-only pending submission while the face check is disabled', async () => {
  const previous = process.env.DISABLE_FACE_VERIFICATION;
  process.env.DISABLE_FACE_VERIFICATION = 'true';
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-id-only-'));
  try {
    const fixture = fixtures();
    const result = await compareAndCreateSubmission({
      uid: 'worker-1',
      idType: 'National ID',
      idNumber: '123456789',
      document: { buffer: Buffer.from('id'), mimetype: 'image/jpeg' },
      selfie: undefined,
      db: fixture.db,
      storage: fixture.storage,
      verify: async () => { throw new Error('face matcher must not run while bypassed'); },
      now: () => new Date('2026-01-01T00:00:00.000Z'),
      uploadsDir: directory,
    });

    assert.deepEqual(result, {
      match: true,
      confidence: null,
      distance: null,
      status: 'pending',
      bypassed: true,
    });
    assert.equal(fixture.record().status, 'pending');
    assert.equal(fixture.record().faceVerified, false);
    assert.equal(fixture.record().faceVerificationProvider, 'bypassed');
    assert.equal(fixture.record().facePhotoPath, null);
    assert.equal(fixture.record().maskedIdNumber, '********6789');
    assert.equal(fixture.record().storageBackend, 'local');
    assert.equal(fixture.record().governmentIdMimeType, 'image/jpeg');
    const saved = await fs.readFile(path.join(directory, fixture.record().governmentIdPath));
    assert.deepEqual(saved, Buffer.from('id'));
  } finally {
    if (previous === undefined) delete process.env.DISABLE_FACE_VERIFICATION;
    else process.env.DISABLE_FACE_VERIFICATION = previous;
    await fs.rm(directory, { recursive: true, force: true });
  }
});
