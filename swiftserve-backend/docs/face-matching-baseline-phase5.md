# Phase 5 — face-matching baseline and defensive validation

Local implementation only. This is comparator correctness work, not a biometric
accuracy measurement or approval for deployment. No images, models, thresholds,
preprocessing, verification policy, Firebase configuration or records were changed.

## Baseline instrumentation

From `swiftserve-backend`:

```powershell
node scripts/inspectFaceMatchingBaseline.js
```

This read-only command reports baseline version `swiftserve-face-baseline-v1`,
installed dependency versions, six model/manifest sizes and SHA-256 fingerprints,
descriptor dimensions, sanitized threshold inputs and effective thresholds. It
does not read dotenv files, initialize Firebase, contact a network service, run
inference, process images, or print credentials/descriptors. Run it in the same
environment as the intended process to inspect that environment; it does not
inspect the environment of a separately running server. It exits unsuccessfully
if required artifacts cannot be read. Fingerprints identify files, not accuracy,
authenticity or a cryptographic trust chain.

Installed baseline observed in this phase:

| Component | Version / artifact |
| --- | --- |
| TensorFlow.js | 4.22.0 |
| TensorFlow WASM backend | 4.22.0 |
| face-api | `@vladmandic/face-api` 1.7.15 |
| Image decoder/canvas | `canvas` 3.2.0 |
| SSD MobileNet V1 weights | `ssd_mobilenetv1_model.bin`, 5,616,957 bytes |
| Full 68-point landmark weights | `face_landmark_68_model.bin`, 356,840 bytes |
| Recognition weights | `face_recognition_model.bin`, 6,444,032 bytes |
| Recognition descriptor | 128 dimensions |

Model download source remains pinned by `scripts/downloadFaceModels.js` to the
face-api 1.7.15 package. No model downloads or package installations were run.

## Preserved pipeline

`verifyFaces()` processes document then selfie through the existing comparator.
Images are decoded by canvas, resized to at most 1,600 pixels on the longest side,
and tried at EXIF-adjusted right-angle rotations. SSD uses its existing library
defaults (512-square network input, confidence 0.5). The full landmark model and
existing landmark-based crop are unchanged. The installed descriptor path uses a
Dlib-style axis-aligned crop, not a new eye-level affine warp. Recognition input
is 150-square with the existing RGB mean subtraction and division by 255.

Descriptor distance remains `sqrt(sum((a[i] - b[i]) ** 2))`, rounded to six decimal
places. Display score remains piecewise linear across `(0,100)`, `(0.45,80)`,
`(0.6,60)`, `(1,0)`, rounded to two decimals before band selection. Distances above
1 score zero. Score/confidence is not an identity probability. Borderline retains
`match: true` for compatibility and still cannot independently approve a worker.

## Defensive behavior

Both descriptors must be numeric arrays/typed arrays of exactly 128 finite
components. Sparse/nonnumeric arrays, missing values, NaN, infinities, wrong
dimensions and exact all-zero vectors (including negative zero) throw a TypeError
with internal code `INVALID_FACE_DESCRIPTOR`. An unrepresentable squared distance
also throws instead of producing a verdict. No descriptor values are included in
the error message.

No normalization, norm bounds, near-zero cutoff or constant-vector rejection was
added. There is no measured evidence supporting those rules. Nonzero, finite
uniform/tiny descriptors remain accepted as numeric input; this is not proof they
are plausible face embeddings. Future plausibility checks require measured data.

Invalid output propagates as processing failure through `verifyFaces()`, before
submission storage or failed-match score writes. The existing HTTP error handling
returns a generic 500 `INTERNAL_ERROR`, without match/verification success fields;
upload buffers are cleared. This phase does not add a new public error contract.
The worker eligibility decision service and policy are unchanged.

## Threshold discrepancy and precedence

Sources inspected: comparator defaults, backend dotenv files, example file,
server entry point, staging/demo/mock launchers, Netlify adapter/configuration,
test overrides and caller-supplied comparator options.

1. Direct calls with an explicit `thresholds` option use that object. Tests use
   explicit fixtures. The public upload API does not accept client thresholds.
2. Otherwise `decisionThresholds()` reads the current process environment at call
   time: `FACE_AUTO_VERIFY_MIN` and `FACE_REVIEW_MIN`.
3. `server.js` calls installed dotenv 18.0.1 before loading the app. By default it
   reads `.env` relative to the working directory and preserves existing process
   variables. Dotenv 18 supports `DOTENV_PATH`/`DOTENV_CONFIG_PATH` and
   `DOTENV_OVERRIDE`/`DOTENV_CONFIG_OVERRIDE`; an explicit override can reverse
   normal environment-over-file precedence. Launcher/host/Node env-file injection
   matters only insofar as it sets that process environment. None of those dotenv
   controls was present in the audit shell.
4. Staging/demo/mock launchers deliberately do not load the normal dotenv file.
   They inherit environment values unless explicitly overridden; they do not
   assign these threshold variables. Netlify face inference remains guarded off.
5. Missing, empty, non-finite or out-of-range percentages fall back to code defaults
   **80/60**. Review minimum is clamped to the strong minimum. Existing number
   parsing and fallback semantics have not changed.

`swiftserve-backend/.env.example` specifies **75/60**. It is a template and is not
automatically loaded by `server.js`. The inspected backend `.env` and admin `.env`
had no threshold definitions. The diagnostic process had neither variable set and
reported **80/60**; a separately running backend's environment remains unverified.

At default settings, strong is nominally distance <=0.45 and borderline <=0.60;
75 moves the nominal strong boundary to 0.4875. These are subject to the preserved
rounding tolerances: 0.4500374 becomes distance 0.450037, score 80 (strong), while
0.4500376 becomes 0.450038, score 79.99 (borderline). Distance 0.60003 scores 60;
0.60004 scores 59.99. Do not treat rounded scores as raw-distance thresholds.

**Separate recommendation, not applied:** after documenting the intended runtime
settings, align the example with the existing code baseline of 80/60 and specify
reviewed values explicitly per environment. Do not change a running 75 environment
silently. Renaming the historical `AUTO_VERIFY` variable or recalibrating thresholds
also requires a separate compatibility decision. No accuracy dataset justifies a
threshold change in this phase.

## Tests and reproducibility

```powershell
# Focused comparator + existing inference/submission fixtures
node --test test/faceDescriptorValidation.test.js test/faceVerificationService.test.js

# Relevant backend regression tests (synthetic/in-memory fixtures only)
node --test test/faceDescriptorValidation.test.js test/faceVerificationService.test.js test/verificationRoutes.test.js test/verificationDecisionService.test.js test/workerVerificationReview.test.js test/nationalIdIdentity.test.js
```

Before the fix, the initial 12-case new suite produced 4 passes / 8 failures. The
valid-input characterization cases already passed; negative cases exposed unsafe
acceptance and the missing standardized processing-error contract. Zero-length
and non-finite inputs were already rejected, but lacked the new internal code.

After the comparator fix, focused tests passed 29/29. After adding diagnostic and
HTTP tests, the relevant regression command passed **71/71**, zero failures or skips.
An additional in-memory comparison against the preserved indexed comparator
produced identical output for **1,006/1,006** valid synthetic pairs (1,000 seeded
cases plus six threshold/rounding cases). All three active model binaries still
matched the installed package byte-for-byte. Syntax and targeted diff checks passed.
Existing short comparator fixtures were expanded to nonzero 128-dimensional vectors
with identical pairwise distances; extraction-only mocks were not changed.

Coverage includes dimensions 0/1/127/129, both argument positions, signed zero,
NaN/infinities, sparse/nonnumeric/missing inputs, Float32 arrays, identical valid
descriptors, different valid descriptors, exact default/custom boundaries, both
rounding stages, distance overflow, invalid inference output without submission
writes, unchanged no-face/multiple-face behavior, buffer cleanup, mock isolation,
legacy protection and policy-controlled approval.

No real IDs or face datasets were used. No physical-device, genuine-face inference,
FAR/FRR/TAR/EER, hosted or production behavior was measured. Flutter/admin were not
changed, and their suites were not rerun in this backend-only phase. Full backend
and Firestore emulator suites were not run; relevant policy tests used synthetic
repositories and do not establish deployed-rule behavior.

## Files changed in this phase

- `src/services/faceVerificationService.js`
- `test/faceVerificationService.test.js`
- `test/faceDescriptorValidation.test.js` (new)
- `test/verificationRoutes.test.js`
- `scripts/inspectFaceMatchingBaseline.js` (new)
- `docs/face-matching-baseline-phase5.md` (new)

Existing unrelated local work was preserved. No staging, commits, pushes,
deployment, mock activation, Firebase modifications or dependency changes occurred.
Capture-quality, alignment experiments, calibration and model changes remain
separate phases requiring approval.
