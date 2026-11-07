# Phase 3 — local verification-policy integration

Local Auth/Firestore emulators only, project `demo-swiftserve-cleanup`, database
`(default)`, existing `mobile/my_app/firebase.local.json`. No migration, deployment,
production/staging access, PSA request, dependency change or mock enablement.

## Integration findings and changes

1. **Confirmed hiring bypass, fixed in the LOCAL rules prototype.** Application
   creation checked canonical worker verification but client-side hiring of an existing
   application did not recheck it. The new emulator scenario failed against the
   pre-change rules with “Missing expected rejection”: the pending worker was hired.
   Local rules now check backend-owned worker eligibility for pending-to-accepted jobs
   and accepted applications. Ordinary clients, including admin browser SDK sessions,
   cannot change the canonical verification fields or backend verification records.
2. **Suspension-field mismatch, fixed locally.** Admin Management uses
   `users.accountStatus`, but the policy checked only `users.status`. The policy and
   new rules helper now honor suspended/disabled/inactive values in both fields.
   No account data or privileges were changed; this is source-only enforcement.
3. **Firestore Timestamp integration works.** Real emulator serialization and
   transaction reads preserve the new policy evidence, timestamps, separate face
   result and worker decision. Missing, mock, expired, wrong-owner and wrong-attempt
   evidence cannot be approved by an authorized reviewer.
4. **Public discovery and badge limitations remain for the UI phase.** Discovery
   queries `worker_profiles.verificationStatus == verified`. Admin suspension is only
   in private users data, so a suspended verified public profile can still appear.
   This is explicitly exercised; the application and hiring writes are denied.
   Public account-status projection/filtering must be designed without exposing
   private records or falsely labeling legacy workers as officially authenticated.
   Badge/action logic still consumes the compatibility status. A pending canonical
   profile cannot grant job access even if its old submission says verified; however,
   some legacy status-label fallback text can still say Verified. The UI phase must
   separate these labels rather than infer government authenticity.
5. **Other compatibility paths.** The old `ServiceRequestRepository.accept()`
   direct-worker acceptance method has no active call site found and does not match
   the client-selection rules. It was not rewritten. The active `acceptApplicant()`
   path relies on server rules for the new eligibility recheck. The Netlify pilot's
   manual-image route still writes the older submission schema and cannot be approved
   through the new policy controller; a future transition is required for that route.

## What the emulator tests actually verify

The new opt-in `test/workerVerificationPolicy.emulator.test.js` uses real emulator
Auth tokens, actual Express authentication/admin middleware and review controller,
real Admin SDK transactions, client SDK writes under the existing rules file, and
the same public-directory query used by Flutter. All users and documents are fresh,
randomly named synthetic fixtures. It neither clears nor deletes existing records.
Only its own temporary synthetic upload directory is removed afterward.

API face inference is injected with synthetic comparator outcomes. The real
comparison/submission persistence function runs. This is not a genuine-face test.
The complete-evidence case seeds an INTERNAL policy contract fixture (including LIVE
and PSA labels needed to exercise the evaluator) inside the demo emulator only.
It is not a PSA response, official authentication or live liveness proof. There is no
new API for clients/admins to submit these internal proofs.

Coverage includes:

- Strong/borderline/mismatch API outcomes never independently grant privileges.
- Missing government/liveness, MOCK government, borderline/mismatch, expired evidence,
  wrong attempt, wrong proof owner and wrong record owner block approval.
- Unauthorized and view-only reviewers cannot approve; injected check fields fail.
- Complete synthetic evidence plus authorized review atomically writes the decision,
  profile projections, notification and audit; application, hiring and discovery work.
- Direct client writes cannot forge canonical status, policy results or check evidence.
- Old-client hiring of a pending worker through an existing application is denied.
- Suspended workers cannot gain approval, apply or be hired despite a verified alias.
- Legacy verified workers continue to apply/be hired without record migration.
- Already booked work can progress without reapproval; no automatic revocation.
- Existing separate mock verification, ownership restrictions and fenced takeover
  remain isolated and tested through the prior mock emulator suite.

The rules still trust the backend-owned compatibility projection, not independently
validate PSA evidence. The Admin SDK bypasses rules by design: privileged server
credentials remain a trust boundary. Repository writers were inspected; face matching,
registration, role switching and manual uploads cannot assign new trusted status
without the decision writer. An old separately deployed backend or arbitrary privileged
Admin SDK script is outside this local validation and would require deployment review.

## Local prototype, not production activation

Only `mobile/my_app/firestore.rules` in this workspace was edited. Production rules
remain unchanged. The prototype preserves legacy verified users and existing booked
work; it does not revoke anyone or query real records. No rules deployment command
was used. Review and verify this prototype before broadly sharing the app.

Some deliberately rejected multi-document probes also emitted Firestore's 1,000-
expression evaluation-limit diagnostics. Denials and the original bypass reproduction
are verified, and valid synthetic and legacy hiring batches succeed. General rules
complexity, large acceptance batches, and request-budget profiling remain unverified;
do not infer broad production performance from these small fixtures.

## Reproduce locally

Inspect occupied ports before starting; do not kill another session or remove locks.
Use the already installed CLI and Java. Run from a fresh temporary log directory:

```powershell
$root = 'C:\Users\User\Documents\SwiftServe'
$logs = Join-Path $env:TEMP ('SwiftServePolicyEmulator-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $logs | Out-Null
Set-Location -LiteralPath $logs
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:RUN_WORKER_POLICY_EMULATOR_TESTS = 'true'
$env:RUN_NATIONAL_ID_EMULATOR_TESTS = 'true'
$env:DEBUG = ''
node --use-system-ca "$root\mobile\my_app\rules-tests\node_modules\firebase-tools\lib\bin\firebase.js" emulators:exec --project demo-swiftserve-cleanup --config "$root\mobile\my_app\firebase.local.json" --only auth,firestore "node --test --test-concurrency=1 $root/swiftserve-backend/test/workerVerificationPolicy.emulator.test.js $root/swiftserve-backend/test/nationalIdIdentity.emulator.test.js"
```

The new suite refuses the wrong project, database, emulator hosts, explicit credentials
and cloud-host flags. It does not load a production dotenv file. CLI-supplied Firebase
project hints must match the demo project. No cloud service is needed.

Backend directory (in-memory/synthetic unit fixtures, no running emulator required):

```powershell
$env:GCLOUD_PROJECT = 'demo-swiftserve-policy'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8187'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
node --test test/verificationDecisionService.test.js test/faceVerificationService.test.js test/verificationRoutes.test.js test/workerVerificationReview.test.js test/nationalIdIdentity.test.js test/verificationStorageService.test.js test/netlifyAuthentication.test.js test/netlifyUploadHardening.test.js test/adminDataRoutes.test.js
```

Flutter directory:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/worker_verification_test.dart test/worker_discovery_test.dart test/merged_worker_workflow_test.dart test/self_application_test.dart test/national_id_mock_test.dart test/liveness_tracker_test.dart
```

## Files changed in Phase 3

- `mobile/my_app/firestore.rules` — LOCAL hiring recheck/suspension prototype.
- `swiftserve-backend/src/services/workerVerificationPolicy.js` — accountStatus guard.
- `swiftserve-backend/test/verificationDecisionService.test.js` — suspension coverage.
- `swiftserve-backend/test/workerVerificationPolicy.emulator.test.js` — new integration suite.
- `mobile/my_app/test/worker_verification_test.dart` — canonical-status compatibility.
- `mobile/my_app/test/worker_discovery_test.dart` — reject untrusted face/mock aliases.
- `swiftserve-backend/docs/worker-verification-phase3.md` — this report.

## Readiness boundary

Final observed results (November 3, 2026):

| Validation | Actual result |
| --- | --- |
| Combined Auth/Firestore policy and existing mock emulator suites | 17 reported tests passed, 0 failed, 0 skipped (includes parent container) |
| Relevant backend command above | 72 passed, 0 failed |
| Flutter compatibility command above | 77 passed, 0 failed |
| Flutter analyzer | No issues |
| Scoped diff whitespace and changed-JavaScript syntax checks | Passed |

The original acceptance scenario failed before the rules patch (one failed child
scenario and its parent test container). It passed with the local prototype. Expected
PERMISSION_DENIED messages belong to negative assertions. Emulators shut down after
each run. No production connectivity or genuine identity verification was exercised.

I've set up prototype Security Rules to keep the data in Firestore safe. They are
designed to be secure for new application and hiring decisions by checking the
backend-owned eligibility status and suspension fields. However, you should review
and verify them before broadly sharing your app. If you'd like, I can help you
harden these rules.

Proceed to local verification-UI design/implementation only after approval, with
explicit separate face/government/liveness/worker outcomes, truthful legacy labels,
suspension display handling, and meaningful 409 error messages. Do not deploy or
activate official verification. Real PSA authentication and server liveness are still
absent; new face-only workers remain unapproved. Legacy migration, automatic evidence
expiry/revocation, pending-image retention and full hosted/device validation remain
separate work. The full application/Storage/rules suites and their previously known
unrelated failures were not rerun or changed. No physical-device or genuine-face
accuracy claim is made.
