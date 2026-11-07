// Read-only diagnostics: no dotenv, Firebase initialization, inference, images,
// credentials or network calls. Reports only model/configuration metadata.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { MODELS_PATH, MODEL_FILES, DESCRIPTOR_DIMENSIONS, decisionThresholds } = require('../src/services/faceVerificationService');

function inspectBaseline(env = process.env) {
  const version = name => JSON.parse(fs.readFileSync(path.resolve(__dirname, '../node_modules', name, 'package.json'), 'utf8')).version;
  return {
    baselineVersion: 'swiftserve-face-baseline-v1',
    accuracyMeasured: false,
    versions: Object.fromEntries(['@tensorflow/tfjs', '@tensorflow/tfjs-backend-wasm', '@vladmandic/face-api', 'canvas'].map(name => [name, version(name)])),
    descriptorDimensions: DESCRIPTOR_DIMENSIONS,
    models: MODEL_FILES.map(name => {
      const bytes = fs.readFileSync(path.join(MODELS_PATH, name));
      return { name, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
    }),
    thresholdSource: 'supplied environment only; this command does not load .env or inspect another running process',
    configured: Object.fromEntries(['FACE_AUTO_VERIFY_MIN', 'FACE_REVIEW_MIN'].map(name => {
      const raw = env[name];
      const accepted = raw !== undefined && raw !== '' && Number.isFinite(Number(raw)) && Number(raw) >= 0 && Number(raw) <= 100;
      return [name, { provided: raw !== undefined, acceptedValue: accepted ? Number(raw) : null }];
    })),
    effectiveThresholds: decisionThresholds(env),
    comparison: { distance: 'Euclidean; rounded to 6 decimals', score: 'piecewise anchors; rounded to 2 decimals before band selection', identityProbability: false },
  };
}
if (require.main === module) {
  try { console.log(JSON.stringify(inspectBaseline(), null, 2)); }
  catch { console.error('Unable to inspect face baseline; check installed packages and model files.'); process.exitCode = 1; }
}
module.exports = { inspectBaseline };
