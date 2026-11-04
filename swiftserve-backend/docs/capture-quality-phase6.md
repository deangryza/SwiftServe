# Phase 6 — capture quality (local review only)

This phase adds usability checks, not proof of identity or improved biometric
accuracy. No real IDs, face datasets, PSA calls, Firebase writes/configuration,
deployment, dependency installation, Git staging/commit/push or mock activation
were performed. Existing user work and the verification policy were preserved.

## Inspection findings

- Flutter document capture already required exactly one ML Kit face. Selfie
  preview ran the existing blink/turn challenge, but the separately captured photo
  was returned without a final image check.
- The backend already decoded images and detected faces, handled right-angle
  rotations, chose the largest document portrait, rejected multiple selfie faces,
  and applied Phase 5 descriptor validation. It did not inspect face-region quality.
- The mock identity workflow already had basic whole-image exposure/contrast
  checks. These remain intact; no mock provider or flag was enabled.
- Flutter and backend disagree about IDs with multiple portraits: Flutter rejects
  them; backend selects the largest (including ghost-portrait cases). This phase
  deliberately preserves both policies. Changing selection needs separate approval.

## Implemented checks

Backend `captureQualityService.js` checks the existing selected face on the
unchanged recognition canvas. It only reads pixels. The original detection,
landmark, descriptor chain and selected descriptor are retained. To avoid changing
the recognition path, this gate runs after descriptor extraction but **before
descriptor comparison and submission/image writes**. It does not save quality
results as official evidence or emit biometric measurements into logs.

Flutter checks the **actual saved file** using its existing ML Kit package and
`dart:ui` image decoding. It checks face count, box/landmark geometry and face-region
pixels. Selfie final detection uses a separate accurate detector, avoiding reuse
of the active preview detector. Existing challenge calculations remain unchanged.
An unusable final selfie offers **Retake selfie**, restarting the existing challenge.
Rejected/cancelled camera-owned temporary files are removed best-effort. A file
cannot be returned after validation if its capture page is no longer active.
Native captures also require the app to remain resumed at these boundaries.

Gallery uploads retain their existing flow; they receive the authoritative backend
quality checks. Local capture verdicts are never accepted as backend evidence.
The existing upload field allowlist rejects `quality` and `qualityVerdict` fields.

### Provisional quality limits

These are conservative engineering cutoffs tested on generated image patterns and
numeric boundaries, **not empirically calibrated face-quality or accuracy limits**.
Recognition thresholds and their configuration are unchanged.

| Check | Initial limit | Rationale / evidence boundary |
| --- | --- | --- |
| Face size | Both box sides >=64 pixels | Reject gross undersampling. Synthetic 63.99/64 boundary checks; 64 pixels does not guarantee sufficient real recognition detail. |
| Framing | Box must be strictly inside the image | A detected box touching/clipped at an edge triggers a retake. Synthetic outside/edge cases cover this conservative heuristic; a real fully visible face may still need reframing. |
| Landmark visibility | Backend: 68 finite, in-image landmarks. Flutter: four available in-image eye/nose/mouth landmarks | Missing/unusable geometry prompts a retake. No accessory, skin-tone or facial-characteristic classifier is used. |
| Exposure | Face-region mean luminance 15–240 inclusive, on 0–255 scale | Extreme dark/bright endpoints, approximately 6% headroom at each end. Synthetic dark/white fixtures and exact boundaries tested. |
| Sharpness | Laplacian variance >=4 inclusive | Standard deviation of 2 luminance levels; intended to reject nearly flat/smooth regions, not discriminate fine real-face quality. Flat and smooth-ramp fixtures fail; textured fixtures pass. |
| Sampling | At most 128×128 nearest samples from the face region | Bounds metric work to approximately 16k samples. Same luminance weights and Laplacian formula on both sides; native decoder/detector results can differ. |

Luminance uses `0.2126 R + 0.7152 G + 0.0722 B`; sharpness uses the variance of
`4*center - left - right - top - bottom` on interior samples. Quality sampling
does not alter, sharpen, normalize or replace the recognition image. Quality checks
are not a reason to lower similarity thresholds.

## Retake and failure behavior

- Too small: move closer and show clear facial detail.
- Too dark: improve lighting and avoid deep shadows.
- Too bright: reduce bright light/glare.
- Too blurry: hold steady and focus before retaking.
- Cropped/outside: keep the entire face inside the image.
- Missing usable landmarks: keep the face visible; remove glare from the ID portrait.
- No face/multiple faces: retain their separate existing detection failures.

Backend quality rejection is HTTP **422**, code **IMAGE_QUALITY**, with a bounded
reason, affected image (`document`/`selfie`) and instruction. It contains no match,
similarity, government, liveness or eligibility success. It remains distinct from
face mismatch, borderline comparison and generic processing failure. Request buffers
are cleared. Flutter maps it to `FaceVerificationFailure.quality` and opens the
corresponding retake step. Consent, review, upload and other retry flows remain intact.

Quality failures create neither failed-match scores nor image/submission/trust
writes. Existing policy tests continue to block face-only worker approval and
preserve existing/legacy worker records. Requesters receive no worker privileges.

## Validation performed

From `swiftserve-backend`:

```powershell
node --test test/captureQualityService.test.js test/faceVerificationService.test.js test/faceDescriptorValidation.test.js test/verificationRoutes.test.js
node --test test/captureQualityService.test.js test/faceDescriptorValidation.test.js test/faceVerificationService.test.js test/verificationRoutes.test.js test/verificationDecisionService.test.js test/workerVerificationReview.test.js test/nationalIdIdentity.test.js
node --test test/verificationRoutes.test.js
node --check src/services/captureQualityService.js
node --check src/services/faceVerificationService.js
node --check src/routes/verificationRoutes.js
```

Initial focused run: **47 passed**. Final expanded relevant backend run: **78
passed**, 0 failed/skipped. After extending forged-quality field coverage, route
tests: **11 passed**. Syntax checks passed. Native canvas operated on generated
patterns, with injected detections; these tests did not execute genuine-face
TensorFlow inference. The final 78-test rerun also passed after isolating the
route-test Firebase module with a fail-closed synthetic adapter, preventing ADC
initialization and unexpected database/authentication access in those HTTP unit
tests. Legacy mocked extraction tests explicitly inject a no-op
quality seam; new canvas integration tests exercise the default quality gate.

From `mobile/my_app` (existing SDK `C:\flutter\bin\flutter.bat`):

```powershell
flutter test --no-pub test/capture_quality_test.dart test/liveness_tracker_test.dart test/worker_verification_test.dart test/verification_experience_test.dart test/national_id_mock_test.dart
flutter analyze --no-pub
```

Focused Flutter suite: **49 passed**, 0 failed. Tests exercise generated PNG decode,
quality boundaries, missing/multiple detections, pixel immutability, final-file
validation before return, cancellation cleanup, retake routing and existing liveness,
consent, mock labels and worker/requester UI. ML Kit detections and camera hardware
are not executed by these tests. Analyzer initially reported two brace-style infos;
after fixing them, **no issues found**. Relevant suites were rerun after final edits.

No React admin changes; admin tests were not run. No full Flutter/backend or emulator
suite was run in this phase. Tests do not establish production or physical-device
behavior, semantic occlusion detection, genuine-face accuracy, FAR/FRR/TAR/EER.

## Preserved behavior and remaining limits

- All TensorFlow models, weights, descriptor dimensions, normalization/alignment,
  Euclidean comparison, score anchors, thresholds, and worker policy remain unchanged.
  Existing comparator/descriptor boundary and policy tests pass.
- A quality-passing fixture reaches the same descriptor; pixel immutability is tested.
  Some previously accepted poor-quality images are intentionally rejected by this gate.
- Landmark presence is not reliable semantic occlusion detection. Masks, hands,
  glare, normal glasses, facial differences and severe pose need representative QA.
  Sharpness can be fooled by noise or background/print texture; it is not authenticity
  or trusted liveness. Sampling can alias and cannot guarantee usable facial detail.
- Pixel limits were measured synthetically only. Real retake burden, device differences,
  skin-tone/lighting effects and false quality rejections remain unmeasured.
- Backend uses its rotated/scaled canvas; Flutter uses native decoded pixels and ML
  Kit geometry. Verify EXIF coordinate agreement and mirrored/rotated photos on devices.
  Passing Flutter does not guarantee the backend will pass the image.
- Full image decoding still has the existing memory/resource risks. Sampling limits
  the quality calculation, not decoder/inference memory. Temp-file deletion is
  best-effort and process termination may leave files needing existing cache cleanup.
- This is ready for **local human review**, not a claim of deployment readiness or
  improved biometric accuracy. Physical Android/iOS checks should include final-photo
  changes after a challenge, background/back navigation, denied camera permission,
  glare, ordinary eyeglasses, cropped/sideways photos, ghost portraits and repeated
  retakes. Use synthetic/approved non-ID material; no real National IDs.

## Files changed in Phase 6

Backend (relative to repository root):

- `swiftserve-backend/src/services/captureQualityService.js` (new)
- `swiftserve-backend/src/services/faceVerificationService.js`
- `swiftserve-backend/src/routes/verificationRoutes.js`
- `swiftserve-backend/test/captureQualityService.test.js` (new)
- `swiftserve-backend/test/faceVerificationService.test.js`
- `swiftserve-backend/test/verificationRoutes.test.js`

Flutter:

- `mobile/my_app/lib/features/worker/domain/capture_quality.dart` (new)
- `mobile/my_app/lib/features/worker/presentation/screens/face_capture_screens.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart`
- `mobile/my_app/lib/shared/repositories/verification_repository.dart`
- `mobile/my_app/test/capture_quality_test.dart` (new)
- `mobile/my_app/test/worker_verification_test.dart`

Documentation:

- `swiftserve-backend/docs/capture-quality-phase6.md` (new)

No portrait-policy change, calibration, model replacement, PSA integration or
production activation is approved by this phase. Stop here for review.
