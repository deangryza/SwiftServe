const assert = require('node:assert/strict');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const { afterEach, beforeEach, test } = require('node:test');

const {
  MODEL_FILES,
  FaceDetectionError,
  compareAndCreateSubmission,
  compareDescriptors,
  decisionThresholds,
  distanceToSimilarity,
  exifRotation,
  getFaceDescriptor,
  loadModels,
  maskIdNumber,
  resetModelStateForTests,
  validateModelFiles,
  verifyFaces,
} = require('../src/services/faceVerificationService');

const THRESHOLDS = Object.freeze({ autoVerifyMin: 80, reviewMin: 60 });

let uploadsDir;
let previousStorage;

beforeEach(async () => {
  uploadsDir = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-face-'));
  previousStorage = process.env.VERIFICATION_STORAGE;
  process.env.VERIFICATION_STORAGE = 'local';
});

afterEach(async () => {
  resetModelStateForTests();
  if (previousStorage === undefined) delete process.env.VERIFICATION_STORAGE;
  else process.env.VERIFICATION_STORAGE = previousStorage;
  await fs.rm(uploadsDir, { recursive: true, force: true });
});

const fixtures = ({ secondUploadFails = false, prior } = {}) => {
  const writes = [];
  const attempts = [];
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
            return {
              name,
              get: async () => ({ exists: true, data: () => ({ role: 'worker', verificationStatus: 'pending' }) }),
            };
          }
          if (name === 'worker_verifications') {
            return {
              name,
              get: async () => ({ exists: Boolean(prior), data: () => prior }),
              collection: () => ({ add: async (value) => { attempts.push(value); } }),
            };
          }
          return { name };
        },
      };
    },
    batch() {
      const pending = [];
      return {
        set(ref, value) { pending.push([ref.name, value]); },
        async commit() { writes.push(...pending); },
      };
    },
  };
  return {
    db,
    storage: { bucket: () => bucket },
    attempts,
    deleted,
    metadata,
    writes,
    record: () => writes.find(([name]) => name === 'worker_verifications')?.[1],
    writesTo: (name) => writes.filter(([collection]) => collection === name).map(([, value]) => value),
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
  thresholds: THRESHOLDS,
  now: () => new Date('2026-01-01T00:00:00.000Z'),
  uploadsDir,
});

const comparison = (band, similarity) => ({
  match: band !== 'mismatch',
  band,
  similarity,
  confidence: similarity,
  distance: 0.4,
});

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

test('maps descriptor distance onto the calibrated similarity anchors', () => {
  assert.equal(distanceToSimilarity(0), 100);
  assert.equal(distanceToSimilarity(0.3), 86.67);
  assert.equal(distanceToSimilarity(0.45), 80);
  assert.equal(distanceToSimilarity(0.6), 60);
  assert.equal(distanceToSimilarity(0.8), 30);
  assert.equal(distanceToSimilarity(1), 0);
  assert.equal(distanceToSimilarity(1.4), 0);
});

test('assigns strong, borderline, and mismatch bands from similarity', () => {
  assert.deepEqual(compareDescriptors([0], [0.45], THRESHOLDS), {
    match: true,
    band: 'strong',
    distance: 0.45,
    similarity: 80,
    confidence: 80,
  });
  const borderline = compareDescriptors([0], [0.5], THRESHOLDS);
  assert.equal(borderline.band, 'borderline');
  assert.equal(borderline.match, true);
  assert.equal(borderline.similarity, 73.33);
  assert.equal(compareDescriptors([0], [0.6], THRESHOLDS).band, 'borderline');
  const mismatch = compareDescriptors([0], [0.7], THRESHOLDS);
  assert.equal(mismatch.band, 'mismatch');
  assert.equal(mismatch.match, false);
  assert.throws(() => compareDescriptors([0], [0, 1]), /equal lengths/);
  assert.throws(() => compareDescriptors([Number.NaN], [0]), /finite/);
});

test('reads decision thresholds from the environment with safe fallbacks', () => {
  assert.deepEqual(decisionThresholds({}), { autoVerifyMin: 80, reviewMin: 60 });
  assert.deepEqual(
    decisionThresholds({ FACE_AUTO_VERIFY_MIN: '85', FACE_REVIEW_MIN: '55' }),
    { autoVerifyMin: 85, reviewMin: 55 },
  );
  assert.deepEqual(
    decisionThresholds({ FACE_AUTO_VERIFY_MIN: 'high', FACE_REVIEW_MIN: '140' }),
    { autoVerifyMin: 80, reviewMin: 60 },
  );
  assert.deepEqual(
    decisionThresholds({ FACE_AUTO_VERIFY_MIN: '50', FACE_REVIEW_MIN: '70' }),
    { autoVerifyMin: 50, reviewMin: 50 },
  );
});

test('orchestrates document then selfie descriptors', async () => {
  const images = [];
  const result = await verifyFaces(Buffer.from('id'), Buffer.from('selfie'), {
    thresholds: THRESHOLDS,
    descriptor: async (_buffer, image) => {
      images.push(image);
      return image === 'document' ? [0, 0] : [0.3, 0.4];
    },
  });
  assert.deepEqual(images, ['document', 'selfie']);
  assert.equal(result.distance, 0.5);
  assert.equal(result.band, 'borderline');
});

test('auto-verifies a strong match and updates the worker badge source', async () => {
  const fixture = fixtures();
  const result = await compareAndCreateSubmission(input(fixture, async () => comparison('strong', 91.5)));

  assert.equal(result.status, 'verified');
  const record = fixture.record();
  assert.equal(record.status, 'verified');
  assert.equal(record.reviewedBy, 'auto_face_match');
  assert.equal(record.faceMatchConfidence, 91.5);
  assert.equal(record.faceMatchBand, 'strong');
  assert.equal(record.faceMatchThreshold, 60);
  assert.equal(record.faceAutoVerifyMin, 80);
  assert.equal(record.maskedIdNumber, '********6789');
  assert.equal(Object.values(record).includes('123456789'), false);
  assert.ok(record.purgeAfter instanceof Date);
  assert.equal(record.storageBackend, 'local');
  assert.deepEqual(fixture.writesTo('users').map((value) => value.verificationStatus), ['verified']);
  assert.deepEqual(fixture.writesTo('worker_profiles').map((value) => value.verificationStatus), ['verified']);
  assert.equal(fixture.writesTo('notifications').length, 1);
  assert.deepEqual(await fs.readFile(path.join(uploadsDir, record.governmentIdPath)), Buffer.from('id'));
  assert.deepEqual(await fs.readFile(path.join(uploadsDir, record.facePhotoPath)), Buffer.from('face'));
});

test('sends a borderline match to admin review without touching the worker status', async () => {
  const fixture = fixtures();
  const result = await compareAndCreateSubmission(input(fixture, async () => comparison('borderline', 70)));

  assert.equal(result.status, 'pending');
  assert.equal(fixture.record().status, 'pending');
  assert.equal(fixture.record().faceReviewFlag, 'borderline');
  assert.equal(fixture.writesTo('users').length, 0);
  assert.equal(fixture.writesTo('notifications').length, 0);
});

test('stores no images for a mismatch and logs the attempt score', async () => {
  const fixture = fixtures();
  const mismatch = comparison('mismatch', 42);
  const result = await compareAndCreateSubmission(input(fixture, async () => mismatch));

  assert.deepEqual(result, mismatch);
  assert.equal(fixture.writes.length, 0);
  assert.deepEqual(fixture.attempts, [{
    similarity: 42,
    distance: 0.4,
    reviewMin: 60,
    attemptedAt: new Date('2026-01-01T00:00:00.000Z'),
  }]);
  assert.deepEqual(await fs.readdir(uploadsDir), []);
});

test('removes partial Cloud Storage uploads and schedules replaced images for deletion', async () => {
  process.env.VERIFICATION_STORAGE = 'gcs';
  const failed = fixtures({ secondUploadFails: true });
  await assert.rejects(
    compareAndCreateSubmission(input(failed, async () => comparison('borderline', 70))),
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
  await compareAndCreateSubmission(input(replacement, async () => comparison('borderline', 70)));
  assert.equal(replacement.record().storageBackend, 'gcs');
  assert.deepEqual(replacement.metadata.map(([filePath]) => filePath), ['old/id.jpg', 'old/selfie.jpg']);
});

test('deletes replaced local images after a new submission', async () => {
  await fs.mkdir(path.join(uploadsDir, 'old'), { recursive: true });
  await fs.writeFile(path.join(uploadsDir, 'old/id.jpg'), 'old');
  const fixture = fixtures({
    prior: { status: 'resubmission_required', storageBackend: 'local', governmentIdPath: 'old/id.jpg' },
  });
  await compareAndCreateSubmission(input(fixture, async () => comparison('borderline', 70)));
  await assert.rejects(fs.access(path.join(uploadsDir, 'old/id.jpg')));
});

test('masks short and long identifiers consistently', () => {
  assert.equal(maskIdNumber('123'), '********123');
  assert.equal(maskIdNumber('123456789'), '********6789');
});

const jpegWithOrientation = (orientation) => {
  const tiff = Buffer.alloc(26);
  tiff.write('II', 0, 'ascii');
  tiff.writeUInt16LE(42, 2);
  tiff.writeUInt32LE(8, 4);
  tiff.writeUInt16LE(1, 8);
  tiff.writeUInt16LE(0x0112, 10);
  tiff.writeUInt16LE(3, 12);
  tiff.writeUInt32LE(1, 14);
  tiff.writeUInt16LE(orientation, 18);
  const payload = Buffer.concat([Buffer.from('Exif\0\0', 'ascii'), tiff]);
  const header = Buffer.alloc(4);
  header.writeUInt16BE(0xffe1, 0);
  header.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([Buffer.from([0xff, 0xd8]), header, payload, Buffer.from([0xff, 0xda])]);
};

test('reads the EXIF rotation phone cameras store with sideways pixels', () => {
  assert.equal(exifRotation(jpegWithOrientation(6)), 90);
  assert.equal(exifRotation(jpegWithOrientation(3)), 180);
  assert.equal(exifRotation(jpegWithOrientation(8)), 270);
  assert.equal(exifRotation(jpegWithOrientation(1)), 0);
  assert.equal(exifRotation(Buffer.from([0x89, 0x50, 0x4e, 0x47])), 0);
  assert.equal(exifRotation(Buffer.from([0xff, 0xd8, 0xff])), 0);
});

test('tries the EXIF orientation first, then other turns, and prefers the main ID portrait', async () => {
  const tried = [];
  const box = (area) => ({ detection: { box: { area } }, descriptor: [area] });
  const runtimeFor = (facesAt, faces) => ({
    loadImage: async () => ({ width: 720, height: 1280 }),
    createCanvas: (width, height) => {
      const target = { width, height, degrees: 0 };
      target.getContext = () => ({
        translate() {},
        rotate(radians) { target.degrees = Math.round((radians * 180) / Math.PI); },
        drawImage() {},
      });
      return target;
    },
    faceapi: {
      detectAllFaces(target) {
        tried.push(target.degrees);
        return {
          withFaceLandmarks() { return this; },
          async withFaceDescriptors() { return target.degrees === facesAt ? faces : []; },
        };
      },
    },
  });

  const sideways = jpegWithOrientation(6);
  assert.deepEqual(await getFaceDescriptor(sideways, 'document', runtimeFor(90, [box(4)])), [4]);
  assert.deepEqual(tried, [90]);

  tried.length = 0;
  const ghostImage = await getFaceDescriptor(sideways, 'document', runtimeFor(0, [box(2), box(9)]));
  assert.deepEqual(ghostImage, [9]);
  assert.deepEqual(tried, [90, 180, 0]);

  await assert.rejects(
    getFaceDescriptor(sideways, 'selfie', runtimeFor(90, [box(2), box(9)])),
    (error) => error.code === 'MULTIPLE_FACES_DETECTED',
  );
  tried.length = 0;
  await assert.rejects(
    getFaceDescriptor(sideways, 'document', runtimeFor(-1, [])),
    (error) => error.code === 'FACE_NOT_DETECTED',
  );
  assert.deepEqual(tried, [90, 180, 0, 270]);
});
