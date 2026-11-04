# Phase 6.3 synthetic OCR experiment

Local corpus and fail-closed harness only. **OCR inference is blocked: no approved
OCR engine is installed.** No classifier, application integration, or authenticity
assessment runs. Nothing here imports Firebase, application routes, face matching,
or worker policy. Run from `swiftserve-backend`:

```powershell
node --test --test-isolation=none experiments/document-ocr/harness.test.js
node experiments/document-ocr/benchmark.js --prepare
```

`--prepare` generates a fresh `run-<UTC timestamp>/` directory beside these files.
It takes no external image/path arguments and never overwrites a previous run.
The run contains 308 PNGs, `manifest.json` and `report.json`. The manifest enumerates
every filename, SHA-256 digest, source, base ID, dataset split, condition and label.
Reports explicitly say `ocrInferenceExecuted: false`; all recognition/performance
metrics are `NOT MEASURED`. Fallback rows are not classifier predictions.

No actual official layout is reproduced. Seven abstract document families plus
seven negative/unknown categories use invented ORBIT headings and DEMO subjects.
Portraits/landscapes are geometric drawings, not photographs. Pattern stripes have
no encoded data. Every image, including blank-content and degraded images, has an
untransformed `SYNTHETIC TEST DOCUMENT — NOT VALID ID` footer. The footer is a
known experimental confound and must be excluded from future document-area metrics.

There are two base records per family, each with 11 variants. All variants of base
0 belong to development; all variants of base 1 belong to test. These bases share
layout logic: this split prevents augmentation leakage but does NOT establish
generalization to unseen templates, people or real IDs. There is no training.

Conditions: clear, blur, low light, overexposure, 10-degree rotation, crop,
row-wise trapezoid approximation, JPEG compression, glare/shadow, partial visibility,
and small document in background. Perspective is an approximation, not a physical
camera model. The intentional low-quality JPEG intermediate can emit a libjpeg
coarse-quantization warning; resulting PNGs are validated.

Only clear fixtures have rendered-text references intended for future CER/WER.
Degraded fixtures retain base text for provenance, explicitly NOT a transcription
of visible text. Even clear text references need OCR reading-order normalization
and visual ground-truth review before measuring CER/WER. Blank means blank interior;
the mandatory watermark remains present.

Limits: 400 samples, 2 MB manifest, 5 MB per PNG, 16M pixels, regular nonsymlink
image files, safe basenames, exact hashes and dimensions. This is a fixture-integrity
check, not a general-purpose untrusted image ingestion service. No OCR execution
timeout or worker pool is implemented while OCR is blocked. Tests leave synthetic
temporary artifacts under `%TEMP%/swiftserve-ocr-synthetic-*`; no cleanup is scheduled.
Run directories also accumulate; generation is explicit and never scheduled.

See `../../docs/ocr-benchmark-phase63.md` for results, limitations and the required
separate installation approval. Do not point this experiment at real documents.
