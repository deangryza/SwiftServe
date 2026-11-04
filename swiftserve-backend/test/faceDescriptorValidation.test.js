const assert = require('node:assert/strict');
const { test } = require('node:test');
const { compareDescriptors, verifyFaces, compareAndCreateSubmission } = require('../src/services/faceVerificationService');

const thresholds = { autoVerifyMin: 80, reviewMin: 60 };
// Nonzero 128-dimensional synthetic descriptors. Varying index 0 gives an exact
// Euclidean-distance fixture without suggesting these are real face embeddings.
const vector = (distance = 0) => {
  const values = new Array(128).fill(0);
  values[127] = 1;
  values[0] = distance;
  return values;
};
const invalid = error => error instanceof TypeError && error.code === 'INVALID_FACE_DESCRIPTOR';

for (const length of [0, 1, 127, 129]) {
  test(`rejects ${length}-dimensional descriptors in either position and equal-length pairs`, () => {
    const bad = new Array(length).fill(0.1);
    for (const pair of [[bad, vector()], [vector(), bad], [bad, bad]]) {
      assert.throws(() => compareDescriptors(...pair, thresholds), invalid);
    }
  });
}
test('rejects zero vectors in either position, including identical signed-zero vectors', () => {
  const zero = new Float32Array(128), negativeZero = new Array(128).fill(-0);
  for (const pair of [[zero, vector()], [vector(), zero], [zero, negativeZero]]) {
    assert.throws(() => compareDescriptors(...pair, thresholds), invalid);
  }
});
test('rejects NaN, infinities, sparse, nonnumeric, missing and non-vector descriptors', () => {
  for (const value of [NaN, Infinity, -Infinity, undefined, '0.1']) {
    const bad = vector(); bad[64] = value;
    assert.throws(() => compareDescriptors(bad, vector(), thresholds), invalid);
    assert.throws(() => compareDescriptors(vector(), bad, thresholds), invalid);
  }
  for (const bad of [null, undefined, new Array(128), { ...vector(), length: 128 }, '1'.repeat(128), new DataView(new ArrayBuffer(128))]) {
    assert.throws(() => compareDescriptors(bad, vector(), thresholds), invalid);
  }
});
test('identical valid arrays and Float32 descriptors retain the existing strong score', () => {
  assert.deepEqual(compareDescriptors(vector(), Float32Array.from(vector()), thresholds), {
    match: true, band: 'strong', distance: 0, similarity: 100, confidence: 100,
  });
  // No evidence-based norm interval exists: do not invent a near-zero cutoff.
  const tiny = new Array(128).fill(1e-30);
  assert.equal(compareDescriptors(tiny, tiny, thresholds).similarity, 100);
});
test('different valid descriptors retain Euclidean distance and existing bands', () => {
  for (const [distance, similarity, band] of [[0.3, 86.67, 'strong'], [0.5, 73.33, 'borderline'], [0.7, 45, 'mismatch'], [1.4, 0, 'mismatch']]) {
    const result = compareDescriptors(vector(), vector(distance), thresholds);
    assert.equal(result.distance, distance);
    assert.equal(result.similarity, similarity);
    assert.equal(result.band, band);
    assert.equal(result.match, band !== 'mismatch');
  }
});
test('exact thresholds remain inclusive and borderline remains comparison-only match', () => {
  assert.equal(compareDescriptors(vector(), vector(0.45), thresholds).band, 'strong');
  assert.equal(compareDescriptors(vector(), vector(0.6), thresholds).band, 'borderline');
  assert.equal(compareDescriptors(vector(), vector(0.4875), { autoVerifyMin: 75, reviewMin: 60 }).band, 'strong');
});
test('preserves six-decimal distance rounding then two-decimal score rounding', () => {
  for (const [distance, rounded, score, band] of [
    [0.4500374, 0.450037, 80, 'strong'],
    [0.4500376, 0.450038, 79.99, 'borderline'],
    [0.60003, 0.60003, 60, 'borderline'],
    [0.60004, 0.60004, 59.99, 'mismatch'],
  ]) {
    const result = compareDescriptors(vector(), vector(distance), thresholds);
    assert.equal(result.distance, rounded);
    assert.equal(result.similarity, score);
    assert.equal(result.band, band);
  }
});
test('unrepresentable distance is a processing error rather than a verdict', () => {
  assert.throws(() => compareDescriptors(vector(1e308), vector(-1e308), thresholds), invalid);
});
test('invalid inference output rejects verifyFaces and creates no submission or attempt writes', async () => {
  let writes = 0;
  const db = { collection: name => ({ doc: () => ({
    get: async () => name === 'users'
      ? { exists: true, data: () => ({ role: 'worker', verificationStatus: 'pending' }) }
      : { exists: false },
    collection: () => ({ add: () => { writes++; assert.fail('No failure-score record for invalid processing'); } }),
  }) }), runTransaction: () => { writes++; assert.fail('No submission transaction'); } };
  for (const position of ['document', 'selfie']) {
    const verify = (document, selfie) => verifyFaces(document, selfie, {
      thresholds, descriptor: async (_buffer, image) => image === position ? new Float32Array(128) : vector(),
    });
    await assert.rejects(verify(Buffer.from('synthetic'), Buffer.from('synthetic')), invalid);
    await assert.rejects(compareAndCreateSubmission({
      uid: 'synthetic-worker', db, storage: null, verify, thresholds, blobStorage: null,
      document: { buffer: Buffer.from('synthetic') }, selfie: { buffer: Buffer.from('synthetic') },
    }), invalid);
  }
  assert.equal(writes, 0);
});

test('baseline diagnostic reports installed model fingerprints without exposing unrelated environment', () => {
  const { inspectBaseline } = require('../scripts/inspectFaceMatchingBaseline');
  const baseline = inspectBaseline({ FACE_AUTO_VERIFY_MIN: '75', FACE_REVIEW_MIN: '60', SECRET: 'must-not-appear' });
  assert.equal(baseline.accuracyMeasured, false);
  assert.equal(baseline.descriptorDimensions, 128);
  assert.equal(baseline.models.length, 6);
  assert.ok(baseline.models.every(model => model.bytes > 0 && /^[a-f0-9]{64}$/.test(model.sha256)));
  assert.equal(baseline.versions['@vladmandic/face-api'], '1.7.15');
  assert.deepEqual(baseline.effectiveThresholds, { autoVerifyMin: 75, reviewMin: 60 });
  assert.equal(JSON.stringify(baseline).includes('must-not-appear'), false);
});

test('threshold fallbacks and review clamp remain unchanged and diagnostics redact invalid values', () => {
  const { inspectBaseline } = require('../scripts/inspectFaceMatchingBaseline');
  assert.deepEqual(inspectBaseline({}).effectiveThresholds, { autoVerifyMin: 80, reviewMin: 60 });
  assert.deepEqual(inspectBaseline({ FACE_AUTO_VERIFY_MIN: '50', FACE_REVIEW_MIN: '70' }).effectiveThresholds, { autoVerifyMin: 50, reviewMin: 50 });
  const invalid = inspectBaseline({ FACE_AUTO_VERIFY_MIN: 'not-a-number', FACE_REVIEW_MIN: '101' });
  assert.deepEqual(invalid.effectiveThresholds, { autoVerifyMin: 80, reviewMin: 60 });
  assert.equal(JSON.stringify(invalid).includes('not-a-number'), false);
});
