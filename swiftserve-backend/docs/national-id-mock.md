# Philippine National ID integration preparation — local mock only

**MOCK / NOT OFFICIALLY VERIFIED. No PSA approval, credentials or live API integration.**
No deployment or production changes are authorized by this implementation.

## Architecture and existing-flow conflicts

Existing registration (email and Google; client and worker) remains the source of
the account and its required adult birthday. An opt-in debug-only `AuthGate` step
opens the mock screen after the private profile exists. This is not a second signup
flow. Production/default builds do not show it. Existing accounts are not migrated.
The mock screen can be left without gaining any account/worker privileges.

The historical `/api/verify` worker pipeline auto-approved a strong face match.
The subsequent local Phase 1/2 separation removes that approval for new submissions;
see [worker-verification-policy.md](worker-verification-policy.md). Historical records
remain unchanged. A face match does **not** establish government document authenticity.
This mock pipeline uses
only its read-only `verifyFaces` adapter, never `compareAndCreateSubmission` or its
trust/status writers. The isolated mock backend refuses the legacy `/api/verify`
route while the mock gate is on. Ordinary non-mock behavior is unchanged.

Flow: Firebase emulator token → server-owned birthday/role → deterministic session
→ versioned consent → bounded synthetic image pair → MockPSAProvider → independent
face adapter → server liveness adapter → fenced final decision → metadata-only
Firestore emulator record → user status screen → optional restricted admin review.

### Checks and explicit limitations

- `IdentityProvider.authenticate` is an **internal** seam, not a representation of
  an official PSA request, response, authentication method or protocol.
- `MockPSAProvider`: success, failed, unavailable, expired, manual_review. The scenario
  is trusted server configuration, never a mobile request field. It receives only a
  synthetic session reference; no National ID number or real identity is requested.
- Default TensorFlow inference is **disabled**. `NATIONAL_ID_FACE_COMPARISON_ENABLED`
  can select the existing local read-only WASM model comparison, but actual model
  execution with real faces was not exercised here. No model is downloaded by this feature.
- Existing camera-side ML Kit blink/turn challenges are reused for capture UX.
  They are not trusted server liveness evidence and cannot be passed as a boolean
  to this API. The default server liveness result is `UNSUPPORTED`.
- Therefore default outcomes require `MANUAL_REVIEW` and **cannot be approved**
  without required check evidence. A face match alone never makes an ID genuine.
- For fully synthetic local UI demonstrations, explicitly select server fixture
  checks. These simulate face/liveness outcomes and are labeled `SYNTHETIC_FIXTURE`.
  They are not TensorFlow inference or live-person verification. Fixture and real
  TensorFlow modes cannot be enabled together.
- `VERIFIED` in a mock session means only a simulated outcome. `providerType=MOCK`,
  `officiallyVerified=false`, and the mock label are mandatory. No `users`,
  `public_profiles`, `worker_profiles` verification statuses or claims are updated.

## State, consistency and authorization

States: NOT_STARTED, CONSENT_REQUIRED, PENDING, PROCESSING, GOVERNMENT_VERIFIED,
FACE_VERIFIED, VERIFIED, REJECTED, MANUAL_REVIEW, EXPIRED, FAILED. The intermediate
check milestones are retained in bounded history; final status and check verdicts
are committed together. Unknown or unavailable checks fail closed.

Session IDs hash the complete JSON tuple `(namespace, uid, requestId)` with SHA-256.
Mobile request IDs are retained per project/UID for restart/idempotent retries.
Creating the same session does not reset consent, TTL or attempts. Recoverable
provider failures and interrupted processing reuse the same record. Three processing
attempts maximum; expired/nonrecoverable sessions require an explicit new request ID.

The processing lease is two minutes and uses an owner UUID and monotonically
increasing fence. Finishing rechecks ownership, fence, lease and session expiration
transactionally. A stale process cannot overwrite a takeover. Refreshing an expired
processing claim exposes a recoverable interruption if attempts remain. Session TTL
is ten minutes. No periodic renewal is implemented: an inference exceeding the lease
must fail closed and be retried; the real integration must define its timeout/SLA.

User endpoints verify Firebase ID tokens **with revocation checking**, use UID only
from the token, and read server-owned birthday/role. A self-declared birthday still
does not prove actual age. Unknown fields, client verdicts, ID numbers and ownership
overrides are rejected. JPEG/PNG only, maximum 1.5 MB each, two files, one bounded
format field. Headers/dimensions are checked before full decoding, then minimum
dimensions, exposure and contrast are checked. These heuristics do not certify
readability, blur, tampering, QR authenticity or a genuine ID.

Writes are limited to `_identityVerificationSessions` and `_identityVerificationAudit`.
Records contain UID/account type, mock provider/source, statuses, notice version and
server timestamp, reference, submission/completion/expiry timestamps, attempts/fence,
bounded reason codes and reviewer metadata. No raw ID image, number, portrait, face
descriptor or template is written to Firestore. These new collections have no client
allow rule, so existing rules deny direct client reads/writes, including owners.
The HTTP API returns a restricted projection. No rules were edited or deployed.

Manual review uses the existing `verification.view` / `verification.manage` backend
permissions and current/revoked/disabled-account checks. Self-review is rejected.
Approval requires acceptable mock government evidence plus passed face and server
liveness checks; failed/missing checks cannot be overridden. Approval is still mock
only. Reviewer UID/time/reason and the verdict commit atomically with a backend-only
audit record. List pages are limited to 25 with an explicit cursor; expired records
do not trap later pages. No new administrator permissions or live accounts are granted.

All identity responses are no-store. New routes reject non-loopback browser origins.
Mutation rate limit: 15 per UID/IP per 15 minutes, in process. This is appropriate only
for the single local demo; a deployed service needs durable/global quotas and abuse
controls. No token/image/biometric payload is logged by this feature.

Images exist briefly in process memory and are cleared from upload buffers after
the HTTP request. Camera files created by the reused screens are deleted best effort;
system photo-picker caches are OS-managed and are not proof of secure deletion or
device encryption. No backend image storage is used. Metadata remains until the
operator stops/clears its isolated emulator or chooses an explicit export policy.
No retention sweeper, production TTL, encryption-at-rest guarantee or deletion of
existing data is introduced. Sensitive real documents are prohibited in this pilot.

## Local testing (no billing, real IDs, PSA requests or cloud resources)

Use new PowerShell terminals. Do not load production `.env` files or credentials.
Use the installed Firebase CLI; no install/upgrade is needed. If ports are in use,
inspect the existing processes instead of killing them or deleting locks/data.

Terminal 1 — existing Auth/Firestore configuration only:

```powershell
cd C:\Users\User\Documents\SwiftServe\mobile\my_app
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
node --use-system-ca rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:start --project demo-swiftserve-cleanup --config firebase.local.json --only auth,firestore
```

Terminal 2 — dedicated loopback mock backend. These flags apply only to this process:

```powershell
cd C:\Users\User\Documents\SwiftServe\swiftserve-backend
$env:GCLOUD_PROJECT = 'demo-swiftserve-cleanup'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8187'
$env:NATIONAL_ID_MOCK_ENABLED = 'true'
$env:NATIONAL_ID_MOCK_SCENARIO = 'manual_review'
$env:NATIONAL_ID_SYNTHETIC_CHECKS = 'true'
$env:NATIONAL_ID_FACE_COMPARISON_ENABLED = 'false'
node scripts/startNationalIdMock.js --seed-synthetic
```

Launcher refuses non-demo projects, non-default databases, missing/remote emulator
hosts, credential/FIREBASE_CONFIG overrides, cloud-host flags and mixed live/pilot
modes. It binds `127.0.0.1:5007`, never port 5000/5002. It does not load dotenv, start
scheduled jobs, send FCM, modify a live allowlist, or initialize a production app.
The optional seed creates only absent synthetic emulator accounts and refuses
inconsistent existing records. Password: `SyntheticIdentityOnly123!` (test only).

- `identity-client@example.test`
- `identity-worker@example.test`
- `identity-reviewer@example.test` — legacy-style demo reviewer admin claim only,
  not Super Admin; no production claim or allowlist changes.

Do not reuse real credentials in this emulator. To simulate outcomes, restart this
dedicated process with `NATIONAL_ID_MOCK_SCENARIO=success|failed|unavailable|expired|manual_review`.
Synthetic checks accept `NATIONAL_ID_SYNTHETIC_FACE=PASSED|FAILED|MANUAL_REVIEW` and
`NATIONAL_ID_SYNTHETIC_LIVENESS=PASSED|FAILED|MANUAL_REVIEW`. These are internal fixtures.
Default settings without synthetic checks cannot produce a trusted liveness pass.

### Android

Prefer the existing side-by-side demo workspace generated by
`dart run tool/prepare_android_expiry_demo.dart`; follow its printed path/commands.
It preserves the production install/native config and uses a separate demo package.
The tool's existing label still says Expiry Demo; this feature does not replace icons.
From the generated copy, after connecting the unlocked USB-debugging phone:

```powershell
adb reverse tcp:5007 tcp:5007
adb reverse tcp:9099 tcp:9099
adb reverse tcp:8187 tcp:8187
flutter run --debug --dart-define=LOCAL_FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:5007 --dart-define=ENABLE_NATIONAL_ID_MOCK=true --dart-define=NATIONAL_ID_SYNTHETIC_CAPTURE=true --dart-define=ENABLE_PUSH_NOTIFICATIONS=false --dart-define=ENABLE_EXPIRY_PUSH=false
```

Register a synthetic adult in the normal existing registration flow, or sign in as
a seeded synthetic client/worker. After the profile exists, the opt-in mock step
opens. Read/accept its dedicated notice, use **generated synthetic test pair**, and
submit. This generates geometric patterns, not a person's face or ID. With default
manual-review provider plus synthetic server checks, status becomes MANUAL_REVIEW.
Refresh after an authorized demo review. Try failure/unavailable/expired scenarios;
unavailable recovery uses the same reference/record. Neither success nor review
changes the real worker badge. Permission denial/capture cancellation should leave
the account usable. The existing live-camera capture interface is reused but must
not be used with real IDs or real biometric data for these mock tests.

### Admin review

Use an additional isolated terminal, not the production admin launcher:

```powershell
cd C:\Users\User\Documents\SwiftServe\admin
$env:VITE_ENABLE_NATIONAL_ID_MOCK = 'true'
$env:VITE_USE_FIREBASE_EMULATORS = 'true'
$env:VITE_FIREBASE_PROJECT_ID = 'demo-swiftserve-cleanup'
$env:VITE_FIRESTORE_DATABASE_ID = '(default)'
$env:VITE_FIREBASE_API_KEY = 'synthetic-key'
$env:VITE_FIREBASE_AUTH_DOMAIN = 'demo-swiftserve-cleanup.firebaseapp.com'
$env:VITE_FIREBASE_APP_ID = 'synthetic-identity-admin'
$env:VITE_API_BASE_URL = 'http://127.0.0.1:5007'
npm run dev -- --host 127.0.0.1 --port 5183
```

The mock-only frontend mode explicitly accepts this demo project and port 5007;
existing production and other demo configurations are unchanged. Sign in with the
synthetic reviewer, open the existing Worker Verification page and its National ID
mock panel. Select a bounded reason and approve/reject. Default missing checks cannot
be approved. Use Next review batch if earlier pages are expired/full. A view-only
administrator must be denied review writes even if calling the API directly.

### Automated commands

Backend directory:

```powershell
node --test test/nationalIdIdentity.test.js test/registrationBirthday.test.js test/verificationRoutes.test.js test/faceVerificationService.test.js test/verificationDecisionService.test.js
```

For isolated emulator integration, set Java as above and run from a fresh temporary
log directory. The CLI config path must be absolute; no rules deployment occurs:

```powershell
$env:RUN_NATIONAL_ID_EMULATOR_TESTS = 'true'
node --use-system-ca C:/Users/User/Documents/SwiftServe/mobile/my_app/rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-swiftserve-cleanup --config C:/Users/User/Documents/SwiftServe/mobile/my_app/firebase.local.json --only auth,firestore "node --test C:/Users/User/Documents/SwiftServe/swiftserve-backend/test/nationalIdIdentity.emulator.test.js"
```

Flutter directory:

```powershell
flutter test --no-pub test/national_id_mock_test.dart test/liveness_tracker_test.dart test/registration_birthday_test.dart test/worker_verification_test.dart
flutter analyze --no-pub
```

Admin directory: `node --test test/*.test.js`, then `npm run build`.
No live project, real identity image, production account or paid service is needed.

## Replacement with official PSA integration — not yet implemented

Public onboarding references reviewed:

- https://everify.gov.ph/faqs
- https://everify.gov.ph/terms-of-use
- https://psa.gov.ph/system/files/citizens-charter/5-PSA-2025-Citizens-Charter-Philippine-Identification-System-Registry%20Office-External-Services.pdf

These describe relying-party onboarding. They do not establish SwiftServe approval
or a confirmed technical contract for this implementation. No authentication endpoint
or sandbox request was called. Obtain approval and the actual current documentation
before implementing `PSAProvider`. Confirm all of the following with PSA:

1. Eligible relying-party organization, signed agreements, lawful basis, privacy
   impact assessment, consent wording/versioning and information/retention obligations.
2. Approved physical/digital formats and capture requirements. This pilot accepts only
   image uploads; it does not validate a signed QR code, PDF, PSN token or genuine card.
3. Approved sandbox/live URLs, authentication protocol, credentials/certificates,
   required identifiers, response fields, rate limits, timeouts and billing/fees.
4. Whether signatures/tokens are required: issuer, audience, nonce, replay protection,
   expiration, key discovery/rotation and authoritative verification algorithms.
5. Server-side anti-spoof/liveness evidence and binding between the consented user,
   government session, document and live capture. Do not trust mobile boolean verdicts.
6. Which pending/manual/error outcomes can be retried, how to reuse remote sessions
   idempotently, and how revocation/credential expiry/unavailable services fail closed.

Keep credentials in an approved server secret store; never Dart/Vite configuration,
Firestore records, source, logs or client requests. Names such as a future internal
`PSA_CREDENTIALS_SECRET_REFERENCE` are placeholders, not official PSA field names.
Map **confirmed, validated** official outcomes into an explicit non-mock state machine,
retaining independent face/liveness results and human-review audit boundaries. Unknown
or unverifiable responses must not approve. Build contract tests from PSA-provided
sanitized sandbox fixtures, then separate sandbox end-to-end and physical-device tests.

Production target validation, secure transport, private encrypted temporary storage
if required, durable rate limiting, long-call lease renewal/worker recovery, metadata
retention/TTL, encryption/key handling and a reviewed age/identity enforcement policy
need separate design and approval. Do not simply remove the emulator guard or relabel
MOCK as PSA. Existing legacy face-only trust semantics also need an approved migration.

## Approval boundary

Still requires explicit approval: contacting/onboarding with PSA, using any real
document/biometric, cloud credentials/resources, non-demo configuration/IAM, private
storage or retention services, rules/index changes, deployment, claims/allowlists,
billing, production enablement or changing production API URLs. Nothing in this mock
implementation authorizes those actions. No deployment readiness is claimed.

## Local validation performed (November 3, 2026)

Final commands and observed results:

| Scope | Command | Result |
| --- | --- | --- |
| Backend, from `swiftserve-backend` | `node --test test/nationalIdIdentity.test.js test/registrationBirthday.test.js test/verificationRoutes.test.js test/faceVerificationService.test.js test/verificationDecisionService.test.js` | 43 passed, 0 failed |
| Auth/Firestore integration | Existing CLI `emulators:exec --project demo-swiftserve-cleanup --config mobile/my_app/firebase.local.json --only auth,firestore "node --test swiftserve-backend/test/nationalIdIdentity.emulator.test.js"`, with absolute paths and `RUN_NATIONAL_ID_EMULATOR_TESTS=true` | 1 passed, 0 failed; fresh local emulators stopped afterward |
| Flutter, from `mobile/my_app` | `flutter analyze --no-pub` | No issues |
| Flutter focused and existing verification tests | `flutter test --no-pub test/national_id_mock_test.dart test/liveness_tracker_test.dart test/registration_birthday_test.dart test/worker_verification_test.dart` | 37 passed, 0 failed |
| Admin, from `admin` | `node --test test/nationalIdMock.test.js test/firebaseTarget.test.js test/adminAccess.test.js` | 8 passed, 0 failed |
| Admin bundle | `npm run build` | Passed; warning about JavaScript chunks larger than 500 kB |

The emulator test uses real emulator-issued tokens and transactions: synthetic image
upload, scoped review access, atomic approval/audit, disabled-account rejection,
lease takeover, stale completion rejection, and direct client write/read denials.
Expected PERMISSION_DENIED logs come from negative authorization assertions.
The TensorFlow adapter contract test stubs comparator results; existing model unit
tests also use controlled runtimes. These are not real model-inference benchmarks.
The generated Flutter test pattern is decoded as a bounded 320 x 320 PNG.
After the final synthetic-image error-handling change, analysis was rerun with no
issues and `flutter test --no-pub test/national_id_mock_test.dart` passed all 6 tests.

Not performed: PSA calls, production/staging access, full application test suites,
physical Android/iOS capture, actual face inference, trusted server-side liveness,
browser-driven admin testing, Linux/hosted validation, or manual launcher/seed UI
end-to-end testing. Do not infer these passed from unit/emulator/build results.

## Exact source/document/test changes for this task

Existing files changed (earlier unrelated work in these files is retained):

- `swiftserve-backend/.env.example`
- `swiftserve-backend/src/app.js`
- `swiftserve-backend/src/routes/verificationRoutes.js`
- `mobile/my_app/lib/app/auth_gate.dart`
- `admin/src/lib/firebase.js`
- `admin/src/lib/firebaseTarget.js`
- `admin/src/page/verification/WorkerVerification.jsx`

New files:

- `swiftserve-backend/src/identity/provider.js`
- `swiftserve-backend/src/identity/policy.js`
- `swiftserve-backend/src/identity/service.js`
- `swiftserve-backend/src/routes/nationalIdRoutes.js`
- `swiftserve-backend/scripts/startNationalIdMock.js`
- `swiftserve-backend/test/nationalIdIdentity.test.js`
- `swiftserve-backend/test/nationalIdIdentity.emulator.test.js`
- `swiftserve-backend/docs/national-id-mock.md`
- `mobile/my_app/lib/shared/services/national_id_mock_client.dart`
- `mobile/my_app/lib/shared/utils/synthetic_identity_image.dart`
- `mobile/my_app/lib/features/auth/presentation/screens/national_id_mock_screen.dart`
- `mobile/my_app/test/national_id_mock_test.dart`
- `admin/src/lib/nationalIdMockReview.js`
- `admin/src/components/verification/NationalIdMockReviews.jsx`
- `admin/test/nationalIdMock.test.js`

No dependency, lockfile, platform configuration, Firestore rule, index, production
API URL, production account/claim/allowlist, or existing birthday/registration field
was changed for this task. Build outputs and test artifacts are local generated
outputs, not deployment or staged source changes.
