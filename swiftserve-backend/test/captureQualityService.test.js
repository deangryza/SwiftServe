const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createCanvas } = require('canvas');
const { CAPTURE_QUALITY, CaptureQualityError, checkFaceGeometry, pixelMetrics, checkPixelMetrics } = require('../src/services/captureQualityService');
const { getFaceDescriptor, FaceDetectionError, compareAndCreateSubmission } = require('../src/services/faceVerificationService');
const points = Array.from({ length: 68 }, () => ({ x: 100, y: 100 }));
const box = { x: 50, y: 50, width: 100, height: 100, area: 10000 };
const rejects = reason => error => error instanceof CaptureQualityError && error.code === 'IMAGE_QUALITY' && error.reason === reason;
function pixels(value, sharp = false, size = 100) {
  const rgba = new Uint8ClampedArray(size * size * 4);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const i = (y * size + x) * 4, v = sharp ? ((Math.floor(x / 4) + Math.floor(y / 4)) % 2 ? value + 30 : value - 30) : value;
    rgba[i] = rgba[i + 1] = rgba[i + 2] = v; rgba[i + 3] = 255;
  }
  return rgba;
}
test('synthetic face-region fixtures separate blur, darkness, overexposure and usable detail', () => {
  for (const [value, reason] of [[5, 'TOO_DARK'], [250, 'TOO_BRIGHT'], [120, 'TOO_BLURRY']]) {
    assert.throws(() => checkPixelMetrics(pixelMetrics(pixels(value), 100, 100), 'selfie'), rejects(reason));
  }
  checkPixelMetrics(pixelMetrics(pixels(120, true), 100, 100), 'selfie');
  // Smooth illumination ramp: contrast alone is not sharp facial detail.
  const ramp = pixels(100);
  for (let y = 0; y < 100; y++) for (let x = 0; x < 100; x++) {
    const i = (y * 100 + x) * 4; ramp[i] = ramp[i + 1] = ramp[i + 2] = 50 + x;
  }
  assert.throws(() => checkPixelMetrics(pixelMetrics(ramp, 100, 100), 'document'), rejects('TOO_BLURRY'));
});
test('quality metric boundaries are inclusive and finite', () => {
  for (const mean of [15, 240]) checkPixelMetrics({ mean, sharpness: 4 }, 'selfie');
  assert.throws(() => checkPixelMetrics({ mean: 14.999, sharpness: 4 }, 'selfie'), rejects('TOO_DARK'));
  assert.throws(() => checkPixelMetrics({ mean: 240.001, sharpness: 4 }, 'selfie'), rejects('TOO_BRIGHT'));
  assert.throws(() => checkPixelMetrics({ mean: 120, sharpness: 3.999 }, 'selfie'), rejects('TOO_BLURRY'));
  assert.throws(() => checkPixelMetrics({ mean: NaN, sharpness: 4 }, 'selfie'), rejects('FACE_DETAIL'));
  assert.equal(CAPTURE_QUALITY.minFaceSide, 64);
});
test('face geometry rejects small, edge-clipped and unusable landmarks without accessory classification', () => {
  checkFaceGeometry(200, 200, { ...box, width: 64, height: 64 }, points, 'document');
  assert.throws(() => checkFaceGeometry(200, 200, { ...box, width: 63.99 }, points, 'document'), rejects('FACE_TOO_SMALL'));
  for (const edit of [{ x: -1 }, { y: 0 }, { x: 100 }, { height: 151 }]) {
    assert.throws(() => checkFaceGeometry(200, 200, { ...box, ...edit }, points, 'selfie'), rejects('FACE_CROPPED'));
  }
  assert.throws(() => checkFaceGeometry(200, 200, box, [{ x: 1, y: 2 }], 'selfie'), rejects('FACE_DETAIL'));
  assert.throws(() => checkFaceGeometry(200, 200, box, points.map((p, i) => i ? p : { x: 201, y: 5 }), 'selfie'), rejects('FACE_DETAIL'));
});
function runtimeFor(faces, value = 120, sharp = true) {
  const input = createCanvas(200, 200), context = input.getContext('2d');
  const data = context.createImageData(200, 200); data.data.set(pixels(value, sharp, 200)); context.putImageData(data, 0, 0);
  return { createCanvas, loadImage: async () => input, faceapi: { detectAllFaces: () => ({
    withFaceLandmarks() { return this; }, withFaceDescriptors: async () => faces,
  }) } };
}
const detection = (bounds = box) => ({ detection: { box: bounds }, landmarks: { positions: points }, descriptor: Float32Array.from({ length: 128 }, () => 0.1) });
test('backend uses actual canvas pixels and returns unchanged descriptor only after quality passes', async () => {
  const result = detection();
  const runtime = runtimeFor([result]), input = await runtime.loadImage(), before = input.toBuffer('image/png');
  assert.equal(await getFaceDescriptor(Buffer.from('synthetic'), 'selfie', runtime), result.descriptor);
  assert.deepEqual(input.toBuffer('image/png'), before);
  await assert.rejects(getFaceDescriptor(Buffer.from('synthetic'), 'selfie', runtimeFor([result], 120, false)), rejects('TOO_BLURRY'));
  await assert.rejects(getFaceDescriptor(Buffer.from('synthetic'), 'document', runtimeFor([result], 5, false)), rejects('TOO_DARK'));
});

test('unsuitable images cannot create failed-match scores, image uploads or worker/submission writes', async () => {
  let writes = 0;
  const db = { collection: name => ({ doc: () => ({
    get: async () => name === 'users'
      ? { exists: true, data: () => ({ role: 'worker', verificationStatus: 'pending' }) }
      : { exists: false },
    collection: () => ({ add: () => { writes++; assert.fail('No match score for quality rejection'); } }),
  }) }), runTransaction: () => { writes++; assert.fail('No write transaction'); } };
  await assert.rejects(compareAndCreateSubmission({ uid: 'synthetic-worker', db, storage: null, blobStorage: null,
    document: { buffer: Buffer.from('synthetic') }, selfie: { buffer: Buffer.from('synthetic') },
    verify: () => getFaceDescriptor(Buffer.from('synthetic'), 'document', runtimeFor([detection()], 5, false)),
  }), rejects('TOO_DARK'));
  assert.equal(writes, 0);
});
test('no-face and multiple-selfie handling remain distinct; largest-ID portrait selection is unchanged', async () => {
  const a = detection({ ...box, width: 70, height: 70, area: 4900 }), b = detection();
  assert.equal(await getFaceDescriptor(Buffer.from('synthetic'), 'document', runtimeFor([a, b])), b.descriptor);
  await assert.rejects(getFaceDescriptor(Buffer.from('synthetic'), 'selfie', runtimeFor([a, b])), e => e instanceof FaceDetectionError && e.code === 'MULTIPLE_FACES_DETECTED');
  await assert.rejects(getFaceDescriptor(Buffer.from('synthetic'), 'selfie', runtimeFor([])), e => e instanceof FaceDetectionError && e.code === 'FACE_NOT_DETECTED');
  // No fallback to a smaller portrait if the selected main portrait is unusable.
  const clipped = detection({ ...box, x: 0, area: 12000 });
  await assert.rejects(getFaceDescriptor(Buffer.from('synthetic'), 'document', runtimeFor([a, clipped])), rejects('FACE_CROPPED'));
});
