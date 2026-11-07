# Phase 6.3 — synthetic local OCR benchmark preparation

## Scope and environment

This is an isolated local experiment, not a production verification feature.
The Phase 6.2 feasibility report was delivered in the preceding conversation;
no saved Phase 6.2 report was found in `docs/`. Its recommendation was an optional
local OCR baseline with uncertainty and independent human review.

Inspected: backend `package.json`, existing documentSuitabilityService,
documentSuitabilityRoutes, verificationStorageService, documentSuitability.test.js,
and docs/document-suitability-phase61a.md. The existing review workflow remains
human-controlled, binds exact bytes/session/attempt, and is restricted to demo
emulators. Nothing in the experiment modifies it.

Available locally: Node v24.18.0 and existing canvas 3.2.0. `require.resolve`
reported `tesseract.js`, `@gutenye/ocr-node` and `onnxruntime-node` unavailable.
PowerShell `Get-Command tesseract` did not find native Tesseract on PATH. This is
not an exhaustive scan of every disk or application installation.

No packages were installed, no models downloaded, no dotenv loaded and no Firebase
configuration initialized by the benchmark. No cloud OCR requests or PSA calls.
Only public source/package metadata was consulted in the browser for a proposed
future engine version; no image was uploaded.

## Corpus

Generated run: `experiments/document-ocr/run-2026-11-03T17-13-30-747Z/`.
The directory uses the runtime's UTC timestamp, not Philippine local time.

| Category | Samples |
| --- | ---: |
| PhilID-style abstract resident card | 22 |
| Digital National ID-style abstract digital resident | 22 |
| Driver-style fictional travel permit | 22 |
| Passport-style fictional journey book | 22 |
| UMID-style fictional member card | 22 |
| Postal-style fictional delivery card | 22 |
| Voter-style fictional civic card | 22 |
| Unrelated game-club card | 22 |
| Generic practice paper | 22 |
| Geometric portrait/avatar | 22 |
| Procedural landscape | 22 |
| Generic task-board screenshot-style drawing | 22 |
| Fabricated unknown ID-like card | 22 |
| Blank-content image | 22 |
| **Total** | **308** |

Each category has two base records and eleven conditions: clear, blur, low light,
overexposure, rotation, crop, approximate perspective, compression, glare/shadow,
partial visibility, small document. All 308 images are 1000×700 PNGs.

All artwork/text is procedural. No actual ID templates, real names/addresses/ID
numbers, seals, signatures, logos, security features or functional QR codes.
ORBIT headings and DEMO-ALPHA/BETA are fictional. Portrait placeholders and avatars
are not biometric photographs. Passport-like lines explicitly say INVALID/TEST;
they are not valid MRZs and cannot validate real passport syntax.

Every image contains a visible warning footer, including blank-content fixtures.
The clear resident-card fixture was visually inspected; all condition variants
were decoded and checked for visible warning pixels in automated harness tests.
Every corpus file was checked against its PNG dimensions, byte limit and digest.

Ground truth: manifest stores category, supported-style flag, expected disposition,
base ID, source, condition, split and text. These are experiment labels, not official
document classifications. Text references for degraded images explicitly describe
base text rather than visible-text transcripts. Do not score them as CER/WER truth.

Base 0 and its augmentations are development; base 1 and its augmentations are test
(154 samples each). Splits prevent augmentation leakage; same-family template logic
is shared across splits. A later independent template/capture holdout is required.

## Execution and outcomes

**OCR engine/version: UNAVAILABLE. Actual OCR inference: NOT RUN. Classifier: NOT RUN.**
The harness deliberately does not substitute reference text for OCR output or use
category labels to generate decisions. No fake confidence or accuracy is reported.

For this complete generated run, all 308 fixture rows return
`DOCUMENT_REVIEW_REQUIRED`, predicted category `unknown`, reason
`OCR_ENGINE_UNAVAILABLE`. These are safety fallback records, not evidence that the
system recognized documents or rejected unrelated images.

| Measurement | Result |
| --- | --- |
| Per-class precision/recall and confusion matrix | NOT MEASURED |
| False acceptance / false rejection | NOT MEASURED |
| Unknown / unreadable recognition accuracy | NOT MEASURED |
| OCR character / word error rate | NOT MEASURED |
| Manual-review/abstention rate from inference | NOT MEASURED |
| Mean / p50 / p95 OCR or classifier latency | NOT MEASURED |
| Peak OCR memory and CPU consumption | NOT MEASURED |
| Accuracy by category and condition | NOT MEASURED |

The harness detects corrupt/oversized/mismatched fixtures and emits experimental
`DOCUMENT_UNREADABLE`, then continues to later records. This is integrity behavior,
not unreadable-document classification. `DOCUMENT_ACCEPTED_FOR_REVIEW` and
`DOCUMENT_REJECTED` remain reserved for a separately approved actual experiment;
neither is emitted without evidence. No outcome is written to human review records.

## Tests and commands actually executed

From `swiftserve-backend`:

```powershell
node --test experiments/document-ocr/harness.test.js
node --test test/documentSuitability.test.js test/faceDescriptorValidation.test.js
```

Both default process-isolated commands failed before test execution with Windows
`spawn EPERM`. They are runner/environment failures, not assertions or passing runs.
Reran without child-process isolation:

```powershell
node --test --test-isolation=none experiments/document-ocr/harness.test.js
node --test --test-isolation=none test/documentSuitability.test.js test/faceDescriptorValidation.test.js
node experiments/document-ocr/benchmark.js --prepare
node --check experiments/document-ocr/corpus.js
node --check experiments/document-ocr/harness.js
node --check experiments/document-ocr/benchmark.js
node --check experiments/document-ocr/harness.test.js
```

- Harness: **5 passed, 0 failed, 0 skipped**. Fictional text constraints, visible
  footer under all conditions, missing-engine abstention, CLI external-path refusal,
  full corpus size/labels, split leakage, duplicates, traversal, manifest/sample
  limits, byte/pixel/hash checks, malformed-record continuation, exclusive creation.
- Existing document suitability + descriptor validation: **31 passed, 0 failed,
  0 skipped**. Tests use in-memory Firebase stubs/synthetic buffers, not live data.
- Generator: completed **308 fixtures** plus manifest and report; no OCR inference.
- Four Node syntax checks passed.
- Libjpeg warned about intentionally coarse compression tables; fixture checks passed.
- No Flutter/admin build or tests, emulator suite, real-face inference or device test
  was run: no application code was changed in this phase.

## Missing engine and separate approval

Candidate for a reproducible first experiment: **tesseract.js 6.0.1**, pinned in a
separate experiment package/lockfile, not application production dependencies.
This is an identified baseline candidate, not a claim that it is the latest,
security-audited or compatible with this environment.

References:
- https://github.com/naptha/tesseract.js/blob/v6.0.1/package.json
- https://github.com/naptha/tesseract.js/blob/master/docs/local-installation.md
- https://github.com/tesseract-ocr/tessdata_fast/blob/main/eng.traineddata

Approval would cover package/transitive dependency inspection and installation,
matching Tesseract core WASM/worker assets and one English traineddata file.
The official fast English file is approximately **3.92 MB**; additional runtime,
WASM, dependencies and caches require more space. Reserve **50 MB as an initial
planning allowance**, not a measured or guaranteed installation size. Verify exact
resolved files, compatibility, licences, checksums, audit results and disk usage
before using them. No asset has been downloaded by this phase. Configure all asset
paths locally and prohibit inference-time CDN/model/network fallback.

Before inference: add isolated worker timeout/termination, bounded concurrency,
bounding-box output validation and output-size caps; mask/exclude warning footers;
measure clear-image CER/WER with reviewed reading order; document thresholds as
experimental; then evaluate layout combinations and unknown/contradictory evidence.
Do not accept only headings, a rectangle, portrait, QR pattern or readable text.

## Limitations and next phase

These are abstract layouts, not representative Philippine ID samples. Many families
share geometry; any success based on invented headings would be template memorization,
not demonstrated document recognition. Augmentations do not reproduce all real glare,
camera, printing or display artifacts. Blank fixtures still contain the watermark.
Warning text is a confound. Portrait/landscape drawings do not test photographic
distribution. No trained/downloaded classifier or real OCR was evaluated.

The result justifies only finishing a controlled local benchmark after separate
dependency/model approval. It does not justify OCR integration, automatic acceptance,
worker approval, hosted use, PSA authentication or production activation.

Test artifacts remain under `%TEMP%/swiftserve-ocr-synthetic-*`; generated corpus
runs remain local and untracked. No scheduled cleanup or deletion was added.

## Exact created files and preservation

Six source/documentation files:
- `experiments/document-ocr/corpus.js`
- `experiments/document-ocr/harness.js`
- `experiments/document-ocr/benchmark.js`
- `experiments/document-ocr/harness.test.js`
- `experiments/document-ocr/README.md`
- `docs/ocr-benchmark-phase63.md`

Generated files: the run directory above contains exactly 308 `.png` files,
`manifest.json`, and `report.json`. Every exact image filename and digest is listed
in that run's `manifest.json` (the file inventory; no hidden input images).

Existing files were not edited. Phase 6.1A review code/tests/docs, application
dependencies/lockfile, TensorFlow weights/preprocessing/thresholds, capture-quality
rules, worker policy, Firebase rules/configuration, production and staging services
were preserved. No deployment, cloud access, Git staging, commit, push or history
operation was performed. This implementation remains an isolated local preparation.
