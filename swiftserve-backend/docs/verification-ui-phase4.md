# Phase 4: separated verification UI (local only)

This is not approval for deployment, real identity verification, or worker migration.
No Firebase configuration, rules, production data, dependencies, models, or thresholds
were changed in this phase. Existing staged work was not staged, unstaged or replaced.

## Implemented experience

- Both account roles can open Settings > Verification checks. The existing capture
  wizard is reused: explanation/consent, ID details, document capture or JPEG/PNG
  upload, selfie capture, review, loading/error/retry states, and separate results.
- Registration keeps its current steps and fields. Its existing preview pages now
  explicitly direct users to verification after registration; they do not pretend
  that those preview steps submitted identity evidence.
- Face matching, QR demonstration, government authentication, server liveness,
  administrative review and worker eligibility have separate labels.
- QR scanning is a **simulated DEMO** using an internal synthetic string format.
  The valid/invalid sample buttons do not decode camera images, implement the
  PhilSys QR specification, contact PSA, or submit authorization evidence. No QR
  decoder is installed; genuine camera decoding needs separate dependency approval.
- Requester comparison uses authenticated/rate-limited `POST /api/verify/face`.
  It calls the existing `verifyFaces()` comparator, clears request buffers, and
  makes no image-storage, submission, notification, profile or worker-trust writes.
  Results are transient; reopening the screen does not retrieve requester history.
- Worker submissions retain the existing `/api/verify` policy-controlled workflow.
  Pending submissions are not freely overwritten; legacy records remain protected.
- Consent here is a UI gate; this phase does not add durable/versioned consent to
  the legacy upload API. Do not describe it as a server-enforced consent contract.
- Admin details show evidence source, checks, current policy blockers and review
  state. Approval requires both review permission and backend readiness. The actual
  review transaction remains authoritative and reevaluates evidence. Expiry between
  viewing and clicking can still produce a safe rejection requiring refresh.
- Legacy labels describe retained access/account status, not official PSA identity.
  Existing verified workers and their stored records were not migrated or revoked.

## Files changed in this phase

Paths below are relative to the repository root; many already contained user work.

Backend:

- `swiftserve-backend/src/routes/verificationRoutes.js`
- `swiftserve-backend/src/controllers/adminVerificationController.js`
- `swiftserve-backend/test/verificationRoutes.test.js`
- `swiftserve-backend/test/workerVerificationReview.test.js`
- `swiftserve-backend/docs/verification-ui-phase4.md` (this report)

Admin:

- `admin/src/lib/verificationEvidence.js` (new)
- `admin/test/verificationEvidence.test.js` (new)
- `admin/src/components/verification/WorkerVerificationModal.jsx`
- `admin/src/data/workerVerification.js`
- `admin/src/page/verification/WorkerVerification.jsx`
- `admin/src/page/dashboard/DashboardHome.jsx`

Flutter:

- `mobile/my_app/lib/shared/models/verification_evidence.dart` (new)
- `mobile/my_app/lib/shared/widgets/verification_evidence_panel.dart` (new)
- `mobile/my_app/lib/shared/repositories/verification_repository.dart`
- `mobile/my_app/lib/shared/screens/swiftserve_settings_screen.dart`
- `mobile/my_app/lib/shared/screens/public_profile_screen.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart`
- `mobile/my_app/lib/features/worker/presentation/models/worker_verification_ui_state.dart`
- `mobile/my_app/lib/features/worker/presentation/widgets/legacy/profile_header.dart`
- `mobile/my_app/lib/features/client/presentation/screens/client_profile_screen.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/client_account_form.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/worker_account_form.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/national_id_mock_screen.dart`
- `mobile/my_app/test/verification_experience_test.dart` (new)
- `mobile/my_app/test/worker_verification_test.dart`
- `mobile/my_app/test/national_id_mock_test.dart`
- `mobile/my_app/test/client_account_form_test.dart`
- `mobile/my_app/test/worker_register_screen_test.dart`

## Validation executed

From `swiftserve-backend`, with demo-only environment hints (no real connection):

```powershell
$env:GCLOUD_PROJECT='demo-swiftserve-policy'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8187'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099'
node --test test/verificationRoutes.test.js test/workerVerificationReview.test.js test/verificationDecisionService.test.js test/faceVerificationService.test.js test/nationalIdIdentity.test.js
```

56 passed, 0 failed. Comparators use synthetic/injected fixtures; these tests do
not establish genuine-face inference accuracy. TensorFlow comparison source from
`// Euclidean distance` to `// Mismatches store` was also compared with the existing
index version and is unchanged. No model artifacts were edited.

From `mobile/my_app` (existing `C:\flutter\bin\flutter.bat`, no package install):

```powershell
flutter analyze --no-pub
flutter test --no-pub test/verification_experience_test.dart test/worker_verification_test.dart test/national_id_mock_test.dart test/client_account_form_test.dart test/worker_register_screen_test.dart test/client_register_screen_test.dart test/registration_step_order_test.dart test/federated_account_form_test.dart test/profile_identity_test.dart test/login_screen_test.dart
```

Analyzer: no issues. Combined Flutter run: 62 passed, 0 failed. Tests cover consent,
both roles, separate/mock results, synthetic QR validation, capture/submit seams,
pending approval, retry/failure paths, narrow/large-text layouts and registration/login.
Initial runs exposed outdated wording expectations, lazy-list result visibility,
and four registration test failures caused by an unstubbed contact-availability API.
Tests now scroll to results and provide an explicit synthetic availability callback;
no production registration validation was weakened. Final wording-only registration
adjustments were separately retested: 9 passed, 0 failed.

From `admin`:

```powershell
node --test test/verificationEvidence.test.js test/nationalIdMock.test.js test/adminAccess.test.js
npm run build
```

8 passed, 0 failed; Vite build passed, with the existing large-chunk warning. These
are pure presentation/authorization tests and compilation, not browser E2E tests.

The two existing emulator suites were rerun using the exact demo configuration and
commands in `worker-verification-phase3.md`: 17 passed, 0 failed, 0 skipped.
Expected denied-write logs include evaluation-limit messages for rejected complex
batches. Valid approval/application/hiring fixtures passed; this is not exhaustive
rules/performance validation. The broader three known rules failures and historical
date-picker failure were not rerun or changed.

## Remaining limitations / approval boundaries

- PSA authentication and trusted server liveness remain unavailable. A face match
  alone leaves workers blocked/pending. Admins cannot invent a manual exception.
- Mock remains opt-in, isolated and disabled by default. QR sample success never
  modifies that flag or worker eligibility.
- No physical device, real ID, genuine-face accuracy, native gallery/camera,
  browser E2E, hosted Linux inference or production behavior was verified.
- Netlify inference remains disabled by the existing pilot guard.
- Gallery selection copies to an owned temporary file; existing draft cleanup is
  reused. Platform permission behavior and app-termination cleanup need device QA.
- Existing pending/legacy submissions retain prior policy protections; a migration
  or new-attempt transition requires a separate reviewed phase.
- The Phase 3 suspended-account public-discovery projection limitation remains;
  authorization is still enforced separately. No unrelated projection was changed.
- QR decoding dependency, official provider/liveness integration, legacy transition,
  deployment or any production activation require separate approval.

All implementation remains local. No deployment, cloud resource, PSA request,
billing change, production write, Git staging, commit or push was performed.
