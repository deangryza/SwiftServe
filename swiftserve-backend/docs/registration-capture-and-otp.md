# Registration ID capture and guarded OTP preparation

Local implementation only. No deployment, Firebase configuration/rules changes,
live records, real ID fixtures, model downloads or dependency installation.

## Registration behavior

Both email/password roles and Google profile setup use the same National ID
upload cards and live-selfie capture. Tapping Front side or Back side offers
Take photo or Choose from gallery. Gallery selection first shows photo-selection
consent, then the native selected-photo picker. Gallery originals
are not modified or deleted. Private temporary copies are not saved in profile
preferences, Firestore public profiles or registration API fields.

The existing NationalIdPhotoValidator checks actual final image files:

- JPEG/PNG signature, bounded size, and at most 16 million decoded pixels.
- Front: one usable face, existing exposure/sharpness/landmark/size checks and
  portrait-left placement.
- Back: actual QR decoding and QR-right placement. Decoded QR values are neither
  retained nor treated as official government authentication.

National ID images may now exceed 5 MB, up to **20 MiB**. Bytes are preserved;
there is no resizing, recompression, descriptor/threshold/model change. The local
document-review service and normal verification route accept the same National ID
limit. Other ID documents and selfies retain 5 MiB limits. Netlify's smaller
limits and disabled hosted inference remain intact; this is not a hosted-upload
compatibility claim. The existing local review backend still rejects images over
16 megapixels. Native decoding memory and orientation need phone testing.

Rejected images are discarded, with an error and retry. A failed replacement keeps
the last accepted image. Next requires accepted evidence or explicit Skip for now.
Skipping ID clears partial sides and any selfie; skipping selfie retains the ID.
Replacing either ID side clears the prior selfie. Capture/validation/skip controls
exclude duplicate operations. Cancellation/disposal cleans owned temporary files.

Selfie capture reuses SelfieLivenessScreen (camera, blink/head movement and final
photo quality validation). This local movement check is not trusted server-side
liveness, and capturing a selfie is not a face-match verdict.

After successful authenticated profile creation, accepted front/selfie files move
to the existing shared WorkerVerificationScreen for the appropriate Client/Worker
role. The back image is deleted locally, matching existing guided-capture behavior.
The existing consent, ID-number input, authenticated document review, attempt/digest
binding and TensorFlow comparator remain required. Selected photos can continue
without recapture. Human document review must be accepted before comparison.
Requester comparison uses `/api/verify/face` and never grants worker privileges.
Worker decisions remain governed by worker-verification-v1.

**Existing limitation:** document suitability is explicitly emulator/local-only;
production/staging and Netlify review/inference remain blocked by existing guards.
These edits do not make live verification available or bypass manual review.
Registration can finish using Skip. Photos are intentionally not crash-recovery
data; after process interruption, recapture through Settings > Verification checks.

## Earlier OTP work preserved and completed

The reference OTP UI is shared by both roles: six numeric cells backed by a real
editable/autofill field, Clear, Edit mobile number, Verify, three-minute resend
deadline, loading/errors. The email-login fallback was removed.

Actual SMS preparation remains **disabled by default**. The implementation permits
only debug builds, exact `demo-swiftserve-cleanup`, and approved loopback emulator
hosts with `REGISTRATION_SMS_ENABLED=true`. Production/staging/unknown targets are
rejected. No carrier SMS, cloud provider or billing setting was enabled.

When enabled locally, email Auth is created at OTP, the phone credential links to
the SAME UID, and the profile is created at the final existing API step. Codes,
passwords and tokens are not saved in recovery preferences. Recovery binds draft
UID/project; incomplete OTP cannot complete that guarded flow. Explicit cancellation
can delete only the unfinished emulator account owned by that registration. Existing,
committed, Google and switched accounts are protected. App disposal retains the
recovery draft rather than silently deleting an account. Google setup links its
existing user. Disabled builds clearly say continuing does not verify a phone.

This guard is not a claim of server-enforced live phone verification. Any future
mandatory live SMS policy requires backend validation of authenticated phone claims,
approved platform/provider configuration, abuse controls and separate billing review.
Firebase verification SMS currently requires Blaze/pay-as-you-go:
https://firebase.google.com/docs/auth/limits

## Local validation commands

From `mobile/my_app` (use installed Flutter; do not install/upgrade packages):

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout=2m test/registration_identity_draft_test.dart test/national_id_capture_test.dart test/registration_otp_test.dart test/firebase_registration_otp_test.dart test/client_account_form_test.dart test/federated_account_form_test.dart test/registration_step_order_test.dart test/worker_verification_test.dart test/verification_experience_test.dart test/capture_quality_test.dart
```

Synthetic local Auth emulator test, no real SMS or cloud credential:

```powershell
$env:DEBUG=''
$env:RUN_REGISTRATION_SMS_EMULATOR_TESTS='true'
node --use-system-ca rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-swiftserve-cleanup --config firebase.local.json --only auth "node --test tool/registration_sms_emulator_test.mjs"
```

It creates/deletes only its own uniquely named synthetic account, rejects a wrong
code, then verifies correct-code linking without changing the UID. It does not
flush existing emulators or test real-device SMS/anti-abuse.

From `swiftserve-backend` (synthetic injected repositories, no cloud connection):

```powershell
node --test --test-isolation=none test/documentSuitability.test.js test/verificationRoutes.test.js test/faceVerificationService.test.js
node --test --test-isolation=none test/captureQualityService.test.js test/faceDescriptorValidation.test.js test/verificationDecisionService.test.js test/workerVerificationReview.test.js
```

Observed results: first backend group 49 passed; second group 32 passed; synthetic
Auth emulator 1 passed. Initial new widget test incorrectly waited for an animated
loading indicator to settle; corrected to wait only for dialog transition. Initial
analysis style findings were corrected. Final combined Flutter run: **103 passed,
zero failed** across the ten listed test files. Final `flutter analyze --no-pub`:
**No issues found**. Both Client/Worker handoffs are tested with pending review
(zero comparator calls) and accepted review (exact original front/selfie passed to
the injected submitter). These are wiring tests, not actual inference.

Fixtures validate wiring, error handling, image validation policy and authorization.
They do not measure actual biometric/QR accuracy, Android/iOS camera behavior or
production readiness. No actual TensorFlow inference with a genuine face was run.

## Phone test checklist

Use an isolated demo backend/auth/firestore configured for the **same** demo project
and database as the mobile build. Do not connect this test to the existing port 5000
unless you have verified its isolation. The mock identity launcher on 5007 sets
`NATIONAL_ID_MOCK_ENABLED=true` and intentionally refuses the real comparator; do
not use it as evidence of working TensorFlow matching. Existing Admin demo uses a
different project/ports and must not be silently mixed with mobile bootstrap.

1. Start the established local emulator configuration. Check no conflicting existing
   emulator is using the ports; reuse it only if its project identity is verified.
2. For local guarded OTP, use `LOCAL_FIREBASE_EMULATOR_HOST=127.0.0.1` and
   `REGISTRATION_SMS_ENABLED=true`, with matching isolated backend API_BASE_URL.
   Forward Auth 9099, Firestore 8187 and that backend port using adb reverse.
3. Register synthetic Client and Worker accounts separately. Deny gallery consent,
   cancel picker, select invalid/multiple-face/front and invalid/blank-QR back,
   retry valid files, and test Skip from each page. Never use a real National ID
   in development tests. Confirm original gallery photos remain untouched.
4. Test >5 MiB and <=20 MiB synthetic source files, over-limit/dimension errors,
   portrait orientation, permissions, slow validation, retake and background/resume.
5. Complete live selfie movement prompts. Finish profile, accept verification
   consent, enter a synthetic ID number and continue with selected images.
6. Submit document for authorized local review. Pending/rejected review must block
   comparison. Accept suitability using a DIFFERENT authorized synthetic reviewer
   bound to the exact attempt/image. Then compare through the existing backend.
   Result must not imply official ID authentication or worker approval.
7. Confirm retries retain files, skipped users reach the dashboard unverified,
   cancellation removes owned temporary copies and no public address/profile data
   contains document images, QR data or face descriptors.

No phone end-to-end, iOS build, live SMS, hosted upload or production verification
is asserted by the unit/emulator results. Future hosting/activation/platform changes
require separate approval. Nothing was staged, committed, pushed or deployed.

## Files changed for ID registration

- `mobile/my_app/lib/features/auth/domain/registration_identity_draft.dart` (new)
- `mobile/my_app/lib/features/auth/presentation/widgets/registration_identity_capture.dart` (new)
- `mobile/my_app/lib/features/auth/presentation/screens/client_account_form.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/worker_account_form.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/client_register_screen.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/google_profile_setup_screen.dart`
- `mobile/my_app/lib/features/worker/domain/national_id_photo_validator.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart`
- `mobile/my_app/test/registration_identity_draft_test.dart` (new)
- `mobile/my_app/test/national_id_capture_test.dart`
- `mobile/my_app/test/client_account_form_test.dart`
- `mobile/my_app/test/worker_verification_test.dart`
- `swiftserve-backend/src/routes/documentSuitabilityRoutes.js`
- `swiftserve-backend/src/routes/verificationRoutes.js`
- `swiftserve-backend/src/services/documentSuitabilityService.js`
- `swiftserve-backend/test/documentSuitability.test.js`
- `swiftserve-backend/test/verificationRoutes.test.js`
- This report.

Additional preceding OTP edits retained/tested: auth/data/firebase_registration_otp.dart,
auth/domain/registration_otp_gateway.dart, auth/presentation/widgets/registration_otp_screen.dart,
auth/presentation/widgets/registration_contact_fields.dart,
auth/presentation/screens/profile_completion_screen.dart,
shared/services/profile_draft_store.dart, test/firebase_registration_otp_test.dart,
test/registration_otp_test.dart, tool/registration_sms_emulator_test.mjs (under mobile/my_app).

## Follow-up: camera choice and visible ID previews

Both registration roles share the new source chooser. Take photo opens the existing
NationalIdCaptureScreen with an explicit single front/back side. That route validates
the final file with the unchanged portrait/QR and quality checks before returning it.
Its default two-sided mode remains compatible with Settings verification. A cancelled
capture returns no file and preserves existing accepted images. Repeated source taps
cannot pop the underlying registration page or start duplicate captures.

Accepted camera/gallery images now appear inside their respective rectangular cards,
with an accepted indicator and tap-to-replace action. The displayed thumbnail decodes
at a bounded 600-pixel width; original validation/upload bytes remain unchanged.
Preview errors offer retake/replacement. Brief Windows sharing locks during owned
temporary-file cleanup are retried at most four times, with 25/50/75 ms waits; other
file errors remain best effort. Gallery originals are never deletion targets.

Take selfie continues to navigate to the same SelfieLivenessScreen used in existing
verification. Tests check this actual widget route and cancellation/retry; there is
no substitute face-comparison engine, new model or automatic approval.

Files changed in this follow-up only:

- `mobile/my_app/lib/features/auth/presentation/widgets/registration_identity_capture.dart`
- `mobile/my_app/lib/features/auth/domain/registration_identity_draft.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/national_id_capture_screen.dart`
- `mobile/my_app/test/registration_identity_draft_test.dart`
- `mobile/my_app/test/national_id_capture_test.dart`
- This report.

New tests cover camera source routing by side, cancellation, front/back preview
binding and replacement, actual selfie-route navigation, single-side validation/file
ownership, and bounded temporary-file lock recovery. Tests mock native camera/detector
channels and use synthetic images; they do not establish physical-device detection
accuracy. Initial test failures from the ResizeImage test property, reverse-route
transition timing and fake-async image file reads were corrected before final runs.

Follow-up regression command from `mobile/my_app`:

```powershell
flutter test --no-pub --concurrency=1 --timeout=2m test/registration_identity_draft_test.dart test/national_id_capture_test.dart test/client_account_form_test.dart test/federated_account_form_test.dart test/registration_step_order_test.dart test/worker_verification_test.dart test/verification_experience_test.dart test/capture_quality_test.dart
flutter analyze --no-pub
```

No backend/Firebase configuration, dependency, model, security-rule, account, deployed
service or API URL changes were made in this follow-up. Existing live verification
limitations above still apply. Physical Android/iOS capture remains unverified.

Follow-up regression result: **87 passed, zero failed** across the eight listed
files. Initial new-test failures were corrected as described above. Final analysis
was rerun after addressing its remaining brace-style warning: **No issues found**.

### Selfie prerequisite guidance

The previous Take selfie button silently disabled itself when either accepted ID
side was missing, including after Skip for now. The button now says **Add ID photos
first** in that state and navigates back to the correct ID step (Client 4 / Worker 5).
After both sides are accepted it becomes **Take selfie** and opens the unchanged
SelfieLivenessScreen. Active capture/validation still locks duplicate actions; ID,
selfie-quality and backend approval requirements are unchanged. If used without a
parent navigation callback, the shared widget provides an explicit prerequisite
error instead of a nonresponsive button.

Focused validation: 24 Flutter tests passed using registration_identity_draft_test,
client_account_form_test, registration_step_order_test and federated_account_form_test.
This includes actionable missing/partial ID guidance, returning from the Client
selfie step to ID at four viewport sizes, and the existing actual selfie route.
No device or backend/Firebase configuration was changed.

### QR capture usability follow-up

Inspection found a source-level false rejection: a genuinely decoded QR was treated
as unreadable if its bounding rectangle crossed any edge of the small right guide.
The guide is now advisory. QR acceptance still requires a nonempty native QR decode,
finite positive geometry, a completely visible bounding rectangle, a center within
the right half of the ID frame, and bounds within a 6%-of-card-width outer margin.
Left-side, cropped and invalid boxes still fail. A decoded but misplaced QR now
reports QR_POSITION; no readable QR reports NO_QR with focus/glare guidance.
Front portrait/quality validation and worker approval rules are unchanged.

The existing ID camera requests veryHigh capture resolution, falling back to high
if initialization fails. This is a requested preset, not a measured hardware result.
Camera initialization requests automatic focus, and tapping the preview requests
focus/exposure metering at that point. Mapping reverses the exact BoxFit.cover
transform, including cropping; requests are serialized and unsupported metering
does not block capture. No stream scanning, new model, external service, dependency,
image recompression, Firebase change or official-ID authentication was introduced.

Changed files for QR usability:

- `mobile/my_app/lib/features/worker/domain/national_id_capture_geometry.dart`
- `mobile/my_app/lib/features/worker/domain/national_id_photo_validator.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/national_id_capture_screen.dart`
- `mobile/my_app/test/national_id_capture_test.dart`
- This report.

Added tests cover decoded QR boxes crossing the old guide, rejection of cropped,
misplaced/degenerate/non-finite boxes, and focus-coordinate mapping for portrait,
landscape and cropped previews. Existing empty/non-QR and front-quality checks remain.
These use injected native results and do not measure QR decoding accuracy, optical
focus, camera resolution fallback or performance on a physical phone. Test those on
supported Android/iOS devices using synthetic QR fixtures before claiming improved
real-world detection. The app still validates the captured file, not a live stream.

Final relevant test run: **81 passed, zero failed**:
Final `flutter analyze --no-pub`: **No issues found**.

```powershell
flutter test --no-pub --concurrency=1 --timeout=2m test/national_id_capture_test.dart test/registration_identity_draft_test.dart test/capture_quality_test.dart test/worker_verification_test.dart test/verification_experience_test.dart
```

The source-level false-rejection test asserts that decoded right-side QR boxes
cross the old guide and now pass; it is not a genuine-phone accuracy benchmark.
No files were staged, committed, pushed or deployed.
