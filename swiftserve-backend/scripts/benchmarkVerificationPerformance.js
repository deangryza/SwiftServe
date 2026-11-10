'use strict';

// Standalone synthetic benchmark. Never loads dotenv, Firebase config or routes.
const { performance } = require('node:perf_hooks');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs/promises');
const crypto = require('node:crypto');
const resources = () => ({ rssBytes: process.memoryUsage().rss,
  peakProcessRssBytes: process.resourceUsage().maxRSS ? process.resourceUsage().maxRSS * 1024 : 'NOT MEASURED' });

async function documentRetryBaseline() {
  const measurements = [];
  const originalHash = crypto.createHash;
  crypto.createHash = function (...args) {
    const hash = originalHash.apply(this, args), originalDigest = hash.digest;
    const start = performance.now();
    hash.digest = function (...digestArgs) {
      const value = originalDigest.apply(this, digestArgs);
      measurements.push(performance.now() - start); return value;
    };
    return hash;
  };
  // Require only after installing the counter, in this isolated CLI process.
  let createDocumentService;
  try { ({ createDocumentService } = require('../src/services/documentSuitabilityService')); }
  finally { crypto.createHash = originalHash; }
  const { createCanvas, loadImage } = require('canvas');
  const c = createCanvas(300, 180), context = c.getContext('2d');
  context.fillStyle = '#ccc'; context.fillRect(0, 0, 300, 180);
  context.fillStyle = '#000'; context.fillText('SYNTHETIC TEST - NOT VALID ID', 10, 90);
  // Trailing bytes create a repeatable near-limit hashing load; not a realism test.
  const bytes = Buffer.concat([c.toBuffer('image/png'), Buffer.alloc(4 * 1024 * 1024)]);
  const decodeStart = performance.now(); await loadImage(bytes);
  const decodeMs = performance.now() - decodeStart;
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-performance-synthetic-'));
  Object.assign(process.env, { GCLOUD_PROJECT: 'demo-swiftserve-performance',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8187', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099', VERIFICATION_STORAGE: 'local' });
  for (const key of ['GOOGLE_APPLICATION_CREDENTIALS','K_SERVICE','NETLIFY','RENDER','NATIONAL_ID_MOCK_ENABLED','SWIFTSERVE_NETLIFY_PILOT']) delete process.env[key];
  const user = { role: 'worker' }, ref = (collection, id) => ({ collection, id });
  const get = async r => ({ data: () => r.collection === 'users' ? user : undefined });
  const db = { projectId: 'demo-swiftserve-performance', databaseId: '(default)',
    collection: collection => ({ doc: id => ({ ...ref(collection, id), get() { return get(this); } }),
      // No other account holds this synthetic image.
      where: () => ({ limit: () => ({ get: async () => ({ docs: [] }) }) }) }),
    async runTransaction(callback) {
      let result;
      for (let retry = 0; retry < 3; retry++) result = await callback({ get, set() {} });
      return result;
    } };
  const service = createDocumentService({ db, uploadsDir: dir, audit() {} });
  const start = performance.now();
  await service.submit('synthetic-subject', { idType: 'National ID' }, { buffer: bytes, mimetype: 'image/png' });
  return { fixtureBytes: bytes.length, transactionCallbacks: 3, imageDecodeMs: decodeMs,
    digestCalls: measurements.length, digestTotalMs: measurements.reduce((a, b) => a + b, 0),
    submissionMs: performance.now() - start, networkUsed: false, resources: resources(),
    note: 'In-memory transaction retries; no emulator/cloud. Includes local disk. Synthetic artifacts retained in TEMP.' };
}

async function inferenceBaseline() {
  const { createCanvas } = require('canvas');
  const { loadModels, getFaceDescriptor } = require('../src/services/faceVerificationService');
  const c = createCanvas(640, 480), ctx = c.getContext('2d');
  ctx.fillStyle = '#78aacc'; ctx.fillRect(0, 0, 640, 480);
  ctx.fillStyle = '#548040'; ctx.fillRect(0, 300, 640, 180);
  const bytes = c.toBuffer('image/png');
  const coldStart = performance.now(), runtime = await loadModels();
  const modelLoadMs = performance.now() - coldStart;
  const decode = [], detectionChain = [], attempts = [];
  const wrapped = { ...runtime, loadImage: async buffer => {
    const start = performance.now(); const result = await runtime.loadImage(buffer);
    decode.push(performance.now() - start); return result;
  }, faceapi: { detectAllFaces: image => ({ withFaceLandmarks: () => ({ withFaceDescriptors: async () => {
    const start = performance.now();
    const result = await runtime.faceapi.detectAllFaces(image).withFaceLandmarks().withFaceDescriptors();
    detectionChain.push(performance.now() - start); return result;
  } }) }) } };
  for (let i = 0; i < 3; i++) {
    const start = performance.now();
    try { await getFaceDescriptor(bytes, 'document', wrapped); attempts.push({ outcome: 'UNEXPECTED_FACE', durationMs: performance.now() - start }); }
    catch (e) {
      if (e.code !== 'FACE_NOT_DETECTED') throw e;
      attempts.push({ outcome: e.code, durationMs: performance.now() - start });
    }
  }
  return { modelLoadMs, decodeMs: decode, detectionChainMs: detectionChain, attempts, resources: resources(),
    landmarkMs: 'NOT MEASURED - no face fixture', descriptorMs: 'NOT MEASURED - no face fixture',
    qualityMs: 'NOT MEASURED - no face fixture',
    note: 'Unmodified model chain on procedural landscape; not genuine-face speed or accuracy.' };
}

function microBaseline() {
  const { compareDescriptors } = require('../src/services/faceVerificationService');
  const { pixelMetrics, checkPixelMetrics } = require('../src/services/captureQualityService');
  const a = Array(128).fill(.1), b = a.slice(); b[0] += .2;
  const pixels = new Uint8ClampedArray(128 * 128 * 4);
  for (let i=0;i<pixels.length;i+=4) { const v=(i/4)%2 ? 70 : 190; pixels.set([v,v,v,255],i); }
  let start=performance.now();
  for(let i=0;i<10000;i++) compareDescriptors(a,b);
  const comparatorMeanMs=(performance.now()-start)/10000;
  start=performance.now();
  for(let i=0;i<100;i++) checkPixelMetrics(pixelMetrics(pixels,128,128),'document');
  return { comparatorMeanMs, qualityPixelMeanMs:(performance.now()-start)/100, resources:resources(),
    note:'Synthetic vectors/pixel region only, not actual face quality or full verification latency. No optimization to these functions.' };
}

if (require.main === module) {
  const mode = process.argv[2];
  if (!['--document', '--inference','--micro'].includes(mode) || process.argv.length !== 3) {
    console.error('Use --document, --inference or --micro; external image paths are not accepted.'); process.exitCode = 1;
  } else Promise.resolve().then(() => mode === '--document' ? documentRetryBaseline() : mode === '--inference' ? inferenceBaseline() : microBaseline())
    .then(result => console.log(JSON.stringify({ mode, ...result }, null, 2)))
    .catch(() => { console.error('Synthetic benchmark failed; no verification outcome established.'); process.exitCode = 1; });
}
module.exports = { documentRetryBaseline };
