# Phase 6.4A — local verification performance

## Scope and inspection

Local-only audit and targeted optimization. No OCR/classifier, dependency install,
model download, Firebase connection, cloud operation or production activation.
Reviewed the Phase 5, 6, 6.1A and 6.3 reports; faceVerificationService,
verificationDecisionService, documentSuitabilityService, verificationStorageService,
verificationRoutes and documentSuitabilityRoutes; Flutter verification repositories,
shared Client/Worker wizard, document/selfie capture and quality code; admin review
page, document preview, API helper, history and decision helpers.

The user supplied the remainder of the initially truncated requirements during
inspection. This report covers those requirements as measurable locally, not a
claim of complete phone/browser/network performance profiling.

## Evidence and baseline before optimization

1. Document submission hashed exact upload bytes **inside** its transaction callback.
   A standalone synthetic benchmark invoked the callback three times and measured
   three SHA-256 operations. All account/attempt checks and commit behavior were
   retained in the benchmark's in-memory transaction model.
2. A new Flutter regression invoked the actual Submit button callback twice before
   the disabled button rebuilt. It **failed against the original code**, observing
   two verification requests instead of one. The fixture completes both futures so
   no pending test work is hidden. No actual upload/network is performed.
3. Admin review handlers relied on React's next-render `busy` state, with no immediate
   exclusion. Read/preview/decision handlers can be called again before that render.
   This is source inspection; no browser baseline request count was measured.
4. Models already use a shared initialization promise and cached runtime. Existing
   tests confirm one load per model and recovery after failed initialization.
5. Each face input is decoded once per getFaceDescriptor call, then retried at the
   existing rotations. Document review and later face comparison are separate
   authenticated operations, potentially separated by human review. Reusing decoded
   biometrics across them would require a new cache/security design and was skipped.

### Comparable synthetic retry experiment

Same CLI, procedural 300×180 PNG plus trailing synthetic bytes, 4,197,559-byte
buffer, same three callback invocations, local canvas/disk, no network:

| Measurement | Before | After run 1 | After run 2 |
| --- | ---: | ---: | ---: |
| SHA-256 calls | 3 | 1 | 1 |
| SHA-256 aggregate time | 85.93 ms | 23.19 ms | 40.08 ms |
| Standalone PNG decode | 11.15 ms | 2.93 ms | 15.64 ms |
| Document submit wall time | 230.12 ms | 104.79 ms | 251.53 ms |

The exact improvement is **66.7% fewer digest operations in a three-callback
transaction**, not a general verification speed percentage. Only single noisy runs
were recorded; machine contention, process startup and disk caching differ. The
second after-run was slower end-to-end than baseline: no stable overall latency
improvement is established. Normal one-callback submissions still hash once.

The near-limit buffer deliberately uses trailing bytes to stress hashing; it is not
a representative compressed camera photo. These synthetic retries do not measure
real Firestore contention, network latency or production transaction behavior.

### Existing installed-model inference baseline

`--inference` executed the unmodified model chain on a generated 640×480 landscape.
No personal/face/ID image was used. No Firebase initialization or records involved.

- Model initialization: **3,014.64 ms** in a fresh process.
- Image decode, three calls: **8.58 / 14.73 / 12.24 ms**.
- Full no-face descriptor attempts: **6,527.02 / 4,949.17 / 4,743.51 ms**.
- Four orientation attempts per input, 12 detection-chain calls:
  **2916.40, 1121.61, 1040.98, 1370.88, 1273.79, 1238.50,
  1346.54, 1063.57, 1281.66, 1152.51, 1219.75, 1071.29 ms**.
- All returned `FACE_NOT_DETECTED`. Landmark extraction and recognition network
  inference were not exercised on detected faces. Their duration: **NOT MEASURED**.
- These are chained-call timings, not separately instrumented SSD kernel timings.
  First-call warmup effects are not an optimization from this phase.

### Other local measurements and unavailable metrics

Synthetic microbenchmark, unchanged functions:
- 10,000 comparator calls: mean **0.01397 ms/call**.
- 100 existing quality pixel-metric/check calls on a generated 128×128 region:
  mean **1.08705 ms/call**. Not a complete capture/face-quality pipeline measurement.
- Microbenchmark process RSS/peak: **111,120,384 bytes**.
- Optimized document benchmark process RSS **70,582,272 bytes**, lifetime peak
  **70,606,848 bytes**. Peak is process-wide high-water RSS, not incremental image
  memory. Before-memory measurements unavailable, so no memory improvement claim.

| Area | Status |
| --- | --- |
| Genuine-face detection/landmarks/descriptors/full verification | NOT MEASURED |
| Real document quality validation end-to-end | NOT MEASURED |
| Phone upload duration, decoding, frame times, main-isolate stalls | NOT MEASURED |
| Widget rebuild counts and navigation performance | NOT MEASURED |
| Admin initial-page/image latency or browser request counts | NOT MEASURED |
| Human review waiting time, live API/Firestore latency | NOT MEASURED |
| Complete Client/Worker phone-to-admin workflow | NOT MEASURED |

## Implemented changes

### Backend

Compute the exact document digest once before entering the retryable transaction.
Every callback still re-reads account state and previous attempt, checks ownership,
session and attempt binding, creates only review-required evidence and writes the
audit transactionally. No stored/previous hash is trusted in place of current bytes.
No decoded-image or descriptor cache was introduced.

New tests preserve the digest under retries, reject an account suspended between
callbacks, preserve the existing record, and verify removal of a newly saved image
when its transaction fails. A dedicated instrumentation test observes one hash
across three callbacks. The original measured code produced three for that scenario.

Standalone timing instrumentation emits only numeric timings, resource usage,
synthetic fixture size and fixed outcomes. No user IDs, names, filenames of private
images, descriptors, tokens, credentials or environment dump. It is not installed
as production request logging. TEMP synthetic benchmark artifacts are retained.

### Flutter

Immediate `_submitting` guard prevents rapid callbacks from starting duplicate work,
before Flutter can rebuild the disabled button. Existing failure handling clears the
guard and preserves the draft for retry. Verified regression: **two requests before,
one after** for the same rapid-callback scenario (50% fewer requests in this case).
The fake document gateway also records one upload after the fix.

Existing loading indicator now names the current client operation: preparing,
uploading document for review, refreshing review, or uploading images/processing
face comparison. It does not claim to observe separate server upload/detection
percentages or display success before a response. Pending review, errors, retake,
cancel and independent result screens remain. Client and Worker share this wizard.

Unchanged documents already skip repeat suitability uploads within the bound local
attempt; this behavior was retained. Server byte/type/session/attempt revalidation
is still mandatory. Forced token refresh and all authentication behavior unchanged.

### Admin

Added a per-component synchronous in-flight gate around review-list loading, private
preview reads and accept/reject decisions. Concurrent calls are ignored until the
current operation finishes, including failures. Pure tests demonstrate one request
for three rapid calls and a fresh request on the next action after completion.
This is helper-level validation, not browser end-to-end timing or request counts.

There is **no completed-response cache**, no cross-user evidence reuse, no token
cache and no server authorization change. Images still use authenticated reads,
no-store server responses, and revoked object URLs. Decisions retain session/attempt
payloads, permission checks, audit records and rejection reasons. Existing list-row
updates after decisions avoid full-page refresh; no new page refresh was added.

## Validation

Backend suites were run **one file per Node process** with `--test-isolation=none`:

| Suite | Passed |
| --- | ---: |
| documentSuitability.test.js | 19 |
| faceDescriptorValidation.test.js | 14 |
| faceVerificationService.test.js | 17 |
| captureQualityService.test.js | 6 |
| verificationRoutes.test.js | 11 |
| verificationDecisionService.test.js | 8 |
| workerVerificationReview.test.js | 4 |
| verificationPerformance.test.js | 1 |
| **Total** | **80** |

Combined-process execution is **not clean**: documentSuitability and worker review
tests install different `require.cache` Firebase/route mocks. Reproduced together:
23 tests, 20 passed, 3 failed (face-only admin rejection, complete policy fixture,
legacy preservation), because the later suite receives the earlier cached mock
router/configuration. Both files pass separately. Existing shared mock isolation
needs separate test-harness work; it is not masked as a successful combined run.

Flutter regression failed before optimization with `Expected 1, Actual 2`.
After optimization: **46 passed, zero failed**, covering worker verification,
shared Requester/Worker experience, capture quality and liveness tracker suites.
No physical device tests or genuine-face accuracy evaluation.

Admin helper/evidence/permission suites: **10 passed, zero failed**. Vite build
passed (3,058 modules), retaining the existing >500 KB chunk warning. No browser E2E.
Initial sandbox build failed with `spawn EPERM`; the approved local build rerun
with normal process permissions passed. Initial Flutter batch launch stalled and
was stopped; direct installed Flutter tooling ran the tests successfully. Dart
format changed the two intended Dart files, then reported a denied telemetry-file
timestamp write; formatting itself completed. No dependency fetch was performed.

Flutter analyzer completed: **No issues found** (116.6 seconds). This is static
analysis of working files, not performance profiling or validation of a staged build.

## Commands

From `swiftserve-backend`:
```powershell
node scripts/benchmarkVerificationPerformance.js --document
node scripts/benchmarkVerificationPerformance.js --inference
node scripts/benchmarkVerificationPerformance.js --micro
node --check scripts/benchmarkVerificationPerformance.js
# Repeat for each backend file listed above, in separate processes:
node --test --test-isolation=none test/documentSuitability.test.js
node --test --test-isolation=none test/verificationPerformance.test.js
```
From `admin`:
```powershell
node --test --test-isolation=none test/requestGate.test.js test/documentReview.test.js test/verificationEvidence.test.js test/adminAccess.test.js
npm run build
```
From `mobile/my_app` (installed SDK, no pub/dependency fetch):
```powershell
C:\flutter\bin\cache\dart-sdk\bin\dart.exe C:\flutter\bin\cache\flutter_tools.snapshot --suppress-analytics test --no-pub test/worker_verification_test.dart --plain-name "rapid callbacks send only one verification request"
C:\flutter\bin\cache\dart-sdk\bin\dart.exe C:\flutter\bin\cache\flutter_tools.snapshot --suppress-analytics test --no-pub test/worker_verification_test.dart test/verification_experience_test.dart test/capture_quality_test.dart test/liveness_tracker_test.dart
C:\flutter\bin\cache\dart-sdk\bin\dart.exe C:\flutter\bin\cache\flutter_tools.snapshot --suppress-analytics analyze --no-pub
```

## Integrity and deferred work

TensorFlow models/versions, preprocessing, rotations, 128 dimensions, descriptor
calculations, distance/score/band thresholds, capture-quality thresholds and worker
policy were not modified. Strong face matches and document acceptance still cannot
satisfy official government authentication, trusted liveness or worker approval.

Skipped reducing resolution, pruning rotation retries, changing detectors, parallel
face pipelines, persistent biometrics caching, private image response caching,
removing transaction validations, and compressing/re-encoding accepted images.
Those changes need accuracy/security/memory evidence; some are explicitly prohibited.
No needless widget memoization or broad bundle refactor without profiling evidence.

Remaining bottlenecks: cold model initialization, repeated orientation inference on
no-face input, slow/unavailable network, required human review, unprofiled Android
capture/main-isolate work, and the admin's large bundle. No unsupported promise of
faster full verification or physical-device responsiveness is made.

Next: separately approved synthetic browser E2E and physical-device profiling;
properly licensed/approved synthetic face fixtures for successful-stage timing;
test-process mock isolation; controlled repeated latency runs on an idle machine.
No dependency or protected-pipeline change is authorized by this report.

## Exact source/documentation files changed

1. `swiftserve-backend/scripts/benchmarkVerificationPerformance.js` (new)
2. `swiftserve-backend/src/services/documentSuitabilityService.js`
3. `swiftserve-backend/test/documentSuitability.test.js`
4. `swiftserve-backend/test/verificationPerformance.test.js` (new)
5. `mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart`
6. `mobile/my_app/test/worker_verification_test.dart`
7. `admin/src/lib/requestGate.js` (new)
8. `admin/src/components/verification/DocumentSuitabilityReviews.jsx`
9. `admin/test/requestGate.test.js` (new)
10. `swiftserve-backend/docs/verification-performance-phase64a.md` (new)

Local checks also generate normal ignored Flutter/build artifacts and admin/dist
output; synthetic benchmark/test artifacts remain under TEMP. No production API
URL, dependencies/lockfile, rules/indexes, accounts/claims, Firebase configuration,
OCR experiment, existing backups or archives were edited. Production/staging were
not contacted. No deployment, staging, commit, push, reset or history rewrite.
