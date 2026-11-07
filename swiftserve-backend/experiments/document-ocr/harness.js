'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const { sha256, WATERMARK } = require('./corpus');
const MAX_SAMPLES = 400, MAX_BYTES = 5 * 1024 * 1024, MAX_PIXELS = 16000000;
const NOT_MEASURED = 'NOT MEASURED';

function validateManifest(manifest) {
  if (manifest?.schema !== 'swiftserve-synthetic-ocr-v1' || manifest.syntheticOnly !== true
    || manifest.watermark !== WATERMARK || !Array.isArray(manifest.samples)
    || !manifest.samples.length || manifest.samples.length > MAX_SAMPLES) throw Error('Invalid synthetic manifest');
  const ids = new Set(), bases = new Map();
  for (const s of manifest.samples) {
    if (!/^[a-z0-9_-]+\.png$/.test(s.file || '') || s.id !== s.file.slice(0, -4) || ids.has(s.id)
      || !/^[a-f0-9]{64}$/.test(s.sha256 || '') || !['development', 'test'].includes(s.split)
      || !s.baseId || s.source !== 'procedural-canvas-fictional-v1'
      || typeof s.referenceText !== 'string' || !s.referenceText.includes(WATERMARK)) throw Error('Invalid fixture metadata');
    if (bases.has(s.baseId) && bases.get(s.baseId) !== s.split) throw Error('Base fixture crosses dataset splits');
    bases.set(s.baseId, s.split); ids.add(s.id);
  }
}

async function verifyFixture(root, s) {
  const filename = path.join(root, s.file), stat = await fs.lstat(filename);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_BYTES) throw Error('Fixture file limit/type rejected');
  const bytes = await fs.readFile(filename);
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))
    || bytes.toString('ascii', 12, 16) !== 'IHDR') throw Error('Invalid PNG');
  const w = bytes.readUInt32BE(16), h = bytes.readUInt32BE(20);
  if (!w || !h || w * h > MAX_PIXELS || w !== s.width || h !== s.height) throw Error('Fixture pixel limit/dimensions rejected');
  if (sha256(bytes) !== s.sha256) throw Error('Fixture digest mismatch');
  return bytes;
}

// No OCR adapter is enabled in this phase: never fetch packages/models or accept
// reference text as OCR output. No image/manifest label drives an acceptance verdict.
function unavailableAssessment() {
  return { outcome: 'DOCUMENT_REVIEW_REQUIRED', predictedCategory: 'unknown', reason: 'OCR_ENGINE_UNAVAILABLE' };
}
async function run(root) {
  const manifestFile = path.join(root, 'manifest.json');
  if ((await fs.stat(manifestFile)).size > 2 * 1024 * 1024) throw Error('Manifest too large');
  const manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'));
  validateManifest(manifest);
  const results = [];
  for (const sample of manifest.samples) {
    try { await verifyFixture(root, sample); results.push({ id: sample.id, ...unavailableAssessment() }); }
    catch { results.push({ id: sample.id, outcome: 'DOCUMENT_UNREADABLE', predictedCategory: 'unknown', reason: 'FIXTURE_INTEGRITY_OR_LIMIT_ERROR' }); }
  }
  return { schema: 'swiftserve-synthetic-ocr-report-v1', syntheticOnly: true, ocrInferenceExecuted: false,
    engine: { status: 'UNAVAILABLE', package: 'tesseract.js', version: null },
    sampleCount: results.length, corpusCounts: manifest.samples.reduce((counts, s) => { counts[s.category] = (counts[s.category] || 0) + 1; return counts; }, {}),
    metrics: Object.fromEntries(['perClassPrecision','perClassRecall','confusionMatrix','falseAcceptanceRate','falseRejectionRate',
      'unknownHandlingAccuracy','unreadableHandlingAccuracy','characterErrorRate','wordErrorRate','abstentionRate',
      'averageProcessingMs','p50ProcessingMs','p95ProcessingMs','peakMemoryBytes'].map(key => [key, NOT_MEASURED])),
    note: 'Fallback records and corpus integrity checks are not OCR/classification measurements. No classifier executed.', results };
}
module.exports = { MAX_SAMPLES, MAX_BYTES, MAX_PIXELS, validateManifest, verifyFixture, unavailableAssessment, run };
