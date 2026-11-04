'use strict';

// Procedural fictional artwork only. No application/Firebase imports or downloads.
const { createCanvas, loadImage } = require('canvas');
const fs = require('node:fs/promises');
const path = require('node:path');
const { createHash } = require('node:crypto');
const WATERMARK = 'SYNTHETIC TEST DOCUMENT — NOT VALID ID';
const CATEGORIES = Object.freeze([
  ['philid_style', 'ORBIT RESIDENT CARD', true],
  ['digital_national_style', 'ORBIT DIGITAL RESIDENT', true],
  ['driver_style', 'ORBIT TRAVEL PERMIT', true],
  ['passport_style', 'ORBIT JOURNEY BOOK', true],
  ['umid_style', 'ORBIT MEMBER CARD', true],
  ['postal_style', 'ORBIT DELIVERY CARD', true],
  ['voter_style', 'ORBIT CIVIC CARD', true],
  ['unrelated_card', 'ORBIT GAME CLUB', false],
  ['paper', 'ORBIT PRACTICE NOTES', false],
  ['portrait', '', false], ['landscape', '', false],
  ['screenshot', 'ORBIT TASK BOARD', false],
  ['fabricated', 'ORBIT UNRECOGNIZED CARD', false], ['blank', '', false],
].map(([category, heading, supportedStyle]) => Object.freeze({ category, heading, supportedStyle })));
const CONDITIONS = Object.freeze(['clear', 'blur', 'low_light', 'overexposed', 'rotated', 'cropped',
  'perspective_approx', 'jpeg_artifacts', 'glare_shadow', 'partial', 'small']);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function original(spec, base) {
  const canvas = createCanvas(900, 550), c = canvas.getContext('2d');
  c.fillStyle = '#f4f0e5'; c.fillRect(0, 0, 900, 550);
  const lines = [];
  const text = (value, x, y, size = 24) => {
    c.fillStyle = '#202020'; c.font = `${size}px sans-serif`; c.fillText(value, x, y); lines.push(value);
  };
  if (spec.category === 'portrait') {
    // Geometric avatar, deliberately not a face photograph or face-model fixture.
    c.fillStyle = '#9aacc0'; c.fillRect(0, 0, 900, 550);
    c.fillStyle = '#cd9f79'; c.beginPath(); c.ellipse(450, 220, 100, 135, 0, 0, Math.PI * 2); c.fill();
    c.fillStyle = '#334455'; c.fillRect(310, 360, 280, 190);
  } else if (spec.category === 'landscape') {
    c.fillStyle = '#89bada'; c.fillRect(0, 0, 900, 330);
    c.fillStyle = '#5c8852'; c.fillRect(0, 330, 900, 220);
    c.fillStyle = '#baaf87'; c.beginPath(); c.moveTo(0, 400); c.lineTo(350, 110); c.lineTo(700, 400); c.fill();
  } else if (spec.category !== 'blank') {
    c.strokeStyle = '#444'; c.lineWidth = 3; c.strokeRect(25, 25, 850, 500);
    text(spec.heading, 55, 85, 30);
    if (spec.supportedStyle || spec.category === 'fabricated') {
      c.fillStyle = '#a6b4bb'; c.fillRect(55, 125, 170, 230); // portrait placeholder, no biometrics
      const start = base === 0 ? 270 : 305;
      text(`TEST SUBJECT: DEMO-${base === 0 ? 'ALPHA' : 'BETA'}`, start, 165);
      text('SIMULATION DATE: 2040-01-01', start, 225);
      text(`TEST REFERENCE: TEST-ONLY-${base === 0 ? 'A' : 'B'}`, start, 285);
      text('FICTIONAL ZONE: ORBIT SECTOR', start, 345);
      text('PATTERN ONLY - NO QR DATA', 55, 450, 20);
      // Stripes do not encode any QR/barcode payload or reproduce finder patterns.
      for (let i = 0; i < 9; i++) { c.fillStyle = i % 2 ? '#777' : '#ddd'; c.fillRect(650 + i * 16, 405, 9, 55); }
      if (spec.category === 'passport_style') {
        // Deliberately nonfunctional MRZ-like lines: no country code/check digits.
        text('TEST<<ORBIT<<DEMO<<<<<<<<<<<<', 55, 490, 20);
        text('INVALID<<TEST<<NO<<MRZ<<<<<<<', 55, 515, 20);
      }
    } else {
      for (let i = 0; i < 5; i++) text(`PRACTICE ROW ${i + 1} - FICTIONAL CONTENT`, 55, 170 + i * 65);
    }
    if (spec.category === 'screenshot' || spec.category === 'digital_national_style') {
      c.strokeStyle = '#777'; c.strokeRect(10, 10, 880, 530); // generic interface frame
    }
  }
  return { canvas, lines };
}

async function variant(source, condition) {
  const out = createCanvas(1000, 700), c = out.getContext('2d');
  c.fillStyle = '#bdbdbd'; c.fillRect(0, 0, out.width, out.height);
  let image = source;
  if (condition === 'jpeg_artifacts') image = await loadImage(source.toBuffer('image/jpeg', { quality: 0.12 }));
  c.save();
  if (condition === 'rotated') { c.translate(500, 325); c.rotate(Math.PI / 18); c.drawImage(image, -450, -275); }
  else if (condition === 'blur') {
    const tiny = createCanvas(100, 61); tiny.getContext('2d').drawImage(image, 0, 0, 100, 61);
    c.imageSmoothingEnabled = true; c.drawImage(tiny, 50, 50, 900, 550);
  } else if (condition === 'perspective_approx') {
    // Row-wise trapezoid approximation, not a calibrated projective homography.
    for (let y = 0; y < 550; y++) { const inset = (550 - y) * 0.13; c.drawImage(image, 0, y, 900, 1, 50 + inset, 50 + y, 900 - 2 * inset, 1); }
  } else if (condition === 'cropped') c.drawImage(image, 180, 0, 650, 550, 50, 50, 900, 550);
  else if (condition === 'partial') c.drawImage(image, 0, 0, 900, 290, 50, 50, 900, 290);
  else if (condition === 'small') c.drawImage(image, 350, 230, 270, 165);
  else c.drawImage(image, 50, 50, 900, 550);
  if (condition === 'low_light' || condition === 'overexposed') {
    c.fillStyle = condition === 'low_light' ? 'rgba(0,0,0,.82)' : 'rgba(255,255,255,.88)'; c.fillRect(0, 0, 1000, 620);
  }
  if (condition === 'glare_shadow') {
    c.fillStyle = 'rgba(255,255,255,.92)'; c.fillRect(250, 70, 250, 500);
    c.fillStyle = 'rgba(0,0,0,.7)'; c.fillRect(650, 50, 280, 550);
  }
  c.restore();
  // Always outside the transformed content, including blank/degraded fixtures.
  c.fillStyle = '#fff'; c.fillRect(0, 625, 1000, 75);
  c.fillStyle = '#a00000'; c.font = 'bold 24px sans-serif'; c.fillText(WATERMARK, 35, 665);
  return out.toBuffer('image/png');
}

async function generate(root) {
  // Exclusive creation: never overwrite an earlier corpus or user directory.
  await fs.mkdir(root, { recursive: false });
  const samples = [];
  for (const spec of CATEGORIES) for (let base = 0; base < 2; base++) {
    const baseId = `${spec.category}-${base}`, { canvas, lines } = original(spec, base);
    for (const condition of CONDITIONS) {
      const file = `${baseId}-${condition}.png`, bytes = await variant(canvas, condition);
      await fs.writeFile(path.join(root, file), bytes, { flag: 'wx' });
      samples.push({ id: file.slice(0, -4), file, baseId, split: base === 0 ? 'development' : 'test',
        category: spec.category, supportedStyle: spec.supportedStyle, condition, sha256: sha256(bytes),
        width: 1000, height: 700, source: 'procedural-canvas-fictional-v1',
        referenceText: [...lines, WATERMARK].join('\n'),
        referenceScope: condition === 'clear' ? 'rendered-text-reading-order' : 'base-text-only-not-visible-text-ground-truth',
        expectedDisposition: spec.category === 'blank' ? 'unreadable-content' : spec.supportedStyle ? 'supported-style' : 'unknown-or-unrelated' });
    }
  }
  const manifest = { schema: 'swiftserve-synthetic-ocr-v1', syntheticOnly: true, watermark: WATERMARK,
    note: 'Abstract fictional families, not official templates. No authenticity labels. No training performed.', samples };
  await fs.writeFile(path.join(root, 'manifest.json'), JSON.stringify(manifest, null, 2), { flag: 'wx' });
  return manifest;
}
module.exports = { CATEGORIES, CONDITIONS, WATERMARK, sha256, original, variant, generate };
