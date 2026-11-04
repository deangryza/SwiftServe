const { inspectImage } = require('../services/verificationImagePolicy');
const LABEL = 'MOCK / NOT OFFICIALLY VERIFIED';
const CONSENT_VERSION = 'swiftserve-identity-mock-v1';
const STATES = Object.freeze(['NOT_STARTED', 'CONSENT_REQUIRED', 'PENDING', 'PROCESSING', 'GOVERNMENT_VERIFIED', 'FACE_VERIFIED', 'VERIFIED', 'REJECTED', 'MANUAL_REVIEW', 'EXPIRED', 'FAILED']);
const fail = (status, code) => Object.assign(new Error(code), { status, code });
function localTarget(db, env) {
  const loopback = value => /^(127\.0\.0\.1|localhost):\d{2,5}$/.test(value || '');
  if (env.NATIONAL_ID_MOCK_ENABLED !== 'true' || !/^demo-[a-z0-9-]+$/.test(db.projectId || '') ||
      (env.NATIONAL_ID_SYNTHETIC_CHECKS === 'true' && env.NATIONAL_ID_FACE_COMPARISON_ENABLED === 'true') ||
      db.databaseId !== '(default)' || env.GCLOUD_PROJECT !== db.projectId ||
      !loopback(env.FIRESTORE_EMULATOR_HOST) || !loopback(env.FIREBASE_AUTH_EMULATOR_HOST) ||
      ['K_SERVICE', 'FUNCTION_TARGET', 'NETLIFY', 'RENDER', 'GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_CONFIG'].some(key => env[key])) {
    throw fail(503, 'MOCK_ENVIRONMENT_REQUIRED');
  }
}
function fields(body, allowed) {
  if (!body || Object.keys(body).some(key => !allowed.includes(key))) throw fail(400, 'INVALID_REQUEST');
}
async function validateImages(document, selfie) {
  // Cheap signature/dimension/byte checks precede decoding and inference.
  for (const file of [document, selfie]) {
    const info = inspectImage(file);
    if (info.width < 256 || info.height < 200) throw fail(400, 'IMAGE_QUALITY');
  }
  const { loadImage, createCanvas } = require('canvas');
  for (const file of [document, selfie]) {
    let image;
    try { image = await loadImage(file.buffer); } catch { throw fail(400, 'INVALID_IMAGE'); }
    const canvas = createCanvas(64, 64), context = canvas.getContext('2d');
    context.drawImage(image, 0, 0, 64, 64);
    const pixels = context.getImageData(0, 0, 64, 64).data;
    let sum = 0, squares = 0;
    for (let i = 0; i < pixels.length; i += 4) {
      const light = (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3;
      sum += light; squares += light * light;
    }
    const mean = sum / 4096;
    if (mean < 10 || mean > 245 || squares / 4096 - mean * mean < 100) throw fail(400, 'IMAGE_QUALITY');
  }
}
// Descriptor comparison is read-only. Never call compareAndCreateSubmission,
// which can update existing worker trust/verification records.
async function tensorflowFace(document, selfie, env) {
  if (env.NATIONAL_ID_FACE_COMPARISON_ENABLED !== 'true') return { outcome: 'UNAVAILABLE' };
  const { verifyFaces } = require('../services/faceVerificationService');
  const result = await verifyFaces(document.buffer, selfie.buffer);
  return { outcome: result.band === 'strong' ? 'PASSED' : result.match ? 'MANUAL_REVIEW' : 'FAILED' };
}
module.exports = { LABEL, CONSENT_VERSION, STATES, fail, localTarget, fields, validateImages, tensorflowFace };
