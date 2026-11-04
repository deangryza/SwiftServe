'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { loadImage } = require('canvas');
const { CATEGORIES, CONDITIONS, WATERMARK, original, variant, generate } = require('./corpus');
const { validateManifest, verifyFixture, unavailableAssessment, run } = require('./harness');
const { main } = require('./benchmark');

test('all categories have explicitly fictional text, with no official issuer/ID payload', () => {
  assert.equal(CATEGORIES.length, 14); assert.equal(CATEGORIES.filter(s => s.supportedStyle).length, 7);
  for (const spec of CATEGORIES) for (const base of [0, 1]) {
    const { lines } = original(spec, base);
    assert.ok(!/Philippine|Pilipinas|PSA|SSS|GSIS|COMELEC|LTO|PHLPOST/i.test(lines.join(' ')));
    assert.ok(!/@|https?:|\b\d{10,}\b/.test(lines.join(' ')));
    if (spec.supportedStyle) assert.ok(lines.some(line => line.includes('DEMO-')));
  }
});

test('all conditions remain valid images with a visible warning footer', async () => {
  const { canvas } = original(CATEGORIES[0], 0);
  for (const condition of CONDITIONS) {
    const image = await loadImage(await variant(canvas, condition));
    assert.equal(image.width, 1000); assert.equal(image.height, 700);
    const { createCanvas } = require('canvas'), check = createCanvas(1000, 700), ctx = check.getContext('2d');
    ctx.drawImage(image, 0, 0);
    const pixels = ctx.getImageData(0, 625, 1000, 75).data;
    let red = 0;
    for (let i = 0; i < pixels.length; i += 4) if (pixels[i] > 80 && pixels[i + 1] < 80 && pixels[i + 2] < 80) red++;
    assert.ok(red > 500, `warning footer missing: ${condition}`);
  }
});

test('unavailable OCR always abstains, including unknown images; never accepts', () => {
  for (const spec of CATEGORIES) assert.deepEqual(unavailableAssessment(spec), {
    outcome: 'DOCUMENT_REVIEW_REQUIRED', predictedCategory: 'unknown', reason: 'OCR_ENGINE_UNAVAILABLE',
  });
});

test('CLI refuses arbitrary image paths and commands', async () => {
  for (const args of [[], ['real-id.png'], ['--prepare', 'external-path'], ['--ocr']]) await assert.rejects(main(args));
});

test('complete corpus, split integrity, limits, corruption isolation and non-overwrite', async () => {
  const parent = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-ocr-synthetic-'));
  const root = path.join(parent, 'corpus');
  // Test artifacts are deliberately left in TEMP; no recursive removal of user files.
  const manifest = await generate(root);
  assert.equal(manifest.samples.length, 308);
  validateManifest(manifest);
  await assert.rejects(generate(root), { code: 'EEXIST' });
  const clone = () => JSON.parse(JSON.stringify(manifest));
  let bad = clone(); bad.samples[1].split = 'test'; assert.throws(() => validateManifest(bad), /splits/);
  bad = clone(); bad.samples[0].file = '../private.png'; assert.throws(() => validateManifest(bad));
  bad = clone(); bad.samples.push(bad.samples[0]); assert.throws(() => validateManifest(bad));
  bad = clone(); bad.samples = Array(401).fill(bad.samples[0]); assert.throws(() => validateManifest(bad));
  bad = clone(); bad.syntheticOnly = false; assert.throws(() => validateManifest(bad));
  bad = clone(); bad.samples[0].referenceText = ''; assert.throws(() => validateManifest(bad));
  assert.ok(manifest.samples.every(s => s.referenceText.includes(WATERMARK)));
  const first = manifest.samples[0], file = path.join(root, first.file), bytes = await fs.readFile(file);
  await verifyFixture(root, first);
  await assert.rejects(verifyFixture(root, { ...first, width: 1 }), /dimensions/);
  const huge = Buffer.from(bytes); huge.writeUInt32BE(20000, 16); huge.writeUInt32BE(20000, 20);
  await fs.writeFile(file, huge); await assert.rejects(verifyFixture(root, first), /pixel/);
  await fs.writeFile(file, Buffer.alloc(5 * 1024 * 1024 + 1)); await assert.rejects(verifyFixture(root, first), /limit/);
  await fs.writeFile(file, 'synthetic corrupt fixture');
  const report = await run(root);
  assert.equal(report.ocrInferenceExecuted, false);
  assert.equal(report.results[0].outcome, 'DOCUMENT_UNREADABLE');
  assert.equal(report.results[1].outcome, 'DOCUMENT_REVIEW_REQUIRED');
  assert.ok(report.results.every(r => r.outcome !== 'DOCUMENT_ACCEPTED_FOR_REVIEW'));
  assert.ok(Object.values(report.metrics).every(value => value === 'NOT MEASURED'));
  assert.equal(Object.keys(report.corpusCounts).length, 14);
});
