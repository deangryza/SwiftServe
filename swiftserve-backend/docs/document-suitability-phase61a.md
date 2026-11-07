# Phase 6.1A — document suitability review (local emulator pilot)

Document suitability is a human appearance decision, not PSA authentication,
trusted liveness, face identity, or worker eligibility. No classifier/OCR, model,
dependency, similarity/quality threshold, or worker-policy change was introduced.
No production operation, deployment, Git staging/commit/push or mock activation
was performed. Existing work and legacy worker records were preserved.

## Architecture and workflow

Previously, document upload checked image headers/size, camera capture checked
face usability, and TensorFlow compared portraits. None established document type.
Readable images and supplied `idType` labels are still not classified automatically.

The new private `document_suitability/{authUid}` record is separate from worker
verification evidence. Both Requesters and Workers submit through authenticated
`/api/verification/document`, and see only their own status/image through that API.
No client SDK access to this collection is needed or allowed.

States:

| State | Meaning |
| --- | --- |
| DOCUMENT_PENDING | No document has been submitted for review. |
| DOCUMENT_REVIEW_REQUIRED | Decodable upload, unclassified; human review needed. |
| DOCUMENT_ACCEPTED | Authorized reviewer marked it suitable for further checks. |
| DOCUMENT_REJECTED | Unsupported/unrelated/incomplete document; replace it. |
| DOCUMENT_UNREADABLE | Reviewer requested a clearer replacement, or session expired. |

Malformed/non-decodable uploads return a distinct `DOCUMENT_UNREADABLE` error,
without overwriting an existing record. Unsupported formats are rejected. Every
decodable image—including selfies, screenshots and synthetic cards—defaults to
review required. This is not an automatic document-appearance classifier.

Records bind owner UID, server-generated stable session UUID, fresh attempt UUID,
declared type, exact SHA-256 image digest, submission/expiry times, status and
recent history. Replacements require the current session/attempt and invalidate
prior acceptance, even for identical replacement bytes. Decisions are immutable
for a decided attempt; a replacement starts a new review. The displayed history
contains the latest 20 decisions; the existing protected audit log records all
committed submissions and decisions transactionally with their session/attempt.

Declared types reuse the current list: National ID, driver's license, passport,
UMID, postal ID and voter's ID. They are labels for human review, not certified
automated support. No physical/digital National ID variant is authenticated here.

## Flutter

The existing capture, consent, document/selfie previews and upload progress remain.
Consent copy now explains private document review as well as face comparison.
The final Submit action first submits the document for review and stops before
face comparison while pending, rejected or unreadable. Status/reason, Refresh and
Replace controls reuse the existing screen; no duplicate verification screen.

After suitability acceptance, Submit runs the original face comparison. Its request
carries session/attempt references, and the server independently checks exact bytes.
The UI never sends an authoritative verdict. A changed file/type must be reviewed.
On reopening, Refresh can restore the current private document through an authenticated
image route and verifies its digest. The camera/file is still subject to Phase 6
quality checks; camera portrait selection remains unchanged.

Consent is still the existing UI gate, not a newly implemented durable legal-consent
contract. No account registration/login fields or production URL/config were changed.

## Admin and authorization

The existing Verification page contains the new Document suitability section:
private submitted image, declared type, UID, submission time, suitability/reason,
mock label, recent history, and Accept / Reject / Unreadable actions. The list is
paged at 100 records with a timestamp-plus-document-ID cursor and Load older.
Images require authentication and return private/no-store responses. Blob preview
URLs are revoked; there are no public image links for these local records.

Backend review routes use existing admin authentication and live permission checks:
`verification.view` for metadata/images, `verification.manage` for decisions.
Self-review, mock evidence, injected government/liveness/worker fields, invalid
decisions, expired attempts, wrong owner/session and stale attempts are rejected.
Ordinary user routes verify revoked tokens and disabled accounts. Accounts must
have an active Client/Worker profile; upload eligibility is rechecked transactionally.

Normal `/api/verify` and `/api/verify/face` require an accepted document binding,
matching declared type and exact image bytes. The worker submission transaction
rechecks that binding after processing/upload, before committing. Final worker
approval also rechecks the document binding for bound records, then runs the unchanged
worker-verification-v1 policy. A pending record without a binding cannot be approved
even if it otherwise meets every policy requirement; it needs the reviewed replacement
flow first. Document acceptance alone cannot satisfy the worker policy.

Legacy and existing verified workers are neither migrated nor revoked. Older clients
that omit document references cannot submit new normal verification requests through
the updated API. This is an intentional fail-closed API change requiring coordinated
client/backend rollout if a future production phase is approved.

## Strict local-only gate and storage

The new workflow refuses production, staging and unknown projects. It requires:

- A `demo-*` Firestore project and `(default)` database.
- `GCLOUD_PROJECT` matching that project.
- Loopback Auth and Firestore emulator hosts.
- No explicit credential file, Cloud Run, Netlify or Render environment.

These checks run before new endpoint data reads. Normal mock mode remains separate;
new document review cannot be used to turn mock evidence into official evidence.
Production activation would require separate approval and reviewed configuration/code.

Private local storage reuses `saveLocalBuffer`, path confinement and authenticated
`sendLocalFile`. Upload limit remains 5 MB, JPEG/PNG only; decoded images over 16M
pixels are refused by this review path. No recognition preprocessing is changed.
Only local storage is supported in this phase; Netlify/GCS migration is not implemented.

Sessions/images become inaccessible after 30 days. Replaced images are removed
best-effort; failed transactions remove their newly written image. This is not a
durable orphan/expiry-deletion scheduler. Crashes can leave orphan files; expiry
does not physically delete them. Local cache/retention reconciliation, disk quotas,
and audit/history retention need approval before any hosted activation. No scheduled
cleanup was activated. Do not host this local-disk pilot as production storage.

## Firestore rules assessment

No rules file was changed or deployed. The new collection has no matching client
allow rule, so direct get/create/update/delete are denied, including for the owner.
Clients and reviewers use authenticated backend APIs; Admin SDK access is protected
by those APIs, not by Firestore rules. The emulator test confirms direct client
denial. Existing account field allowlists and protected audit mechanisms remain.

## Validation

All fixture images are generated geometric/text patterns, not real National IDs or
personal biometrics. They exercise review workflow behavior, not appearance-classifier
accuracy. Human recognition of real documents was not measured.

Backend command, from `swiftserve-backend`:

```powershell
node --test test/documentSuitability.test.js test/verificationRoutes.test.js test/captureQualityService.test.js test/faceDescriptorValidation.test.js test/faceVerificationService.test.js test/verificationDecisionService.test.js test/workerVerificationReview.test.js test/nationalIdIdentity.test.js
```

95 passed, zero failed/skipped. Covers pending defaults for synthetic scenes/cards,
unreadable/unsupported uploads, rejection/replacement, byte/type/session/attempt
substitution, denied reviewers and self-review, forged fields, mock isolation,
private image retrieval, expiry, fail-closed target checks, and inability to approve
a worker with suitability alone. Existing model/comparator/quality/policy tests pass.
Backend syntax checks passed. Initial test iterations found fixture syntax and auth
stub contract mistakes; those were corrected before the passing regression run.

Flutter command, from `mobile/my_app`:

```powershell
flutter test --no-pub test/worker_verification_test.dart test/verification_experience_test.dart test/capture_quality_test.dart test/liveness_tracker_test.dart test/national_id_mock_test.dart
flutter analyze --no-pub
```

New tests cover pending -> rejected -> accepted UI and unreadable-response guidance.
Existing capture/quality, Requester/Worker results, consent, retry and mock UI tests
are retained. Test reviewers are explicit injected fixtures, not production bypasses.
Final focused run: **51 passed**, zero failures. Flutter analyzer: **no issues found**
after correcting brace-style infos. The complete Flutter suite was not run.

Admin command, from `admin`:

```powershell
node --test test/documentReview.test.js test/verificationEvidence.test.js test/adminAccess.test.js test/nationalIdMock.test.js
npm run build
```

10 passed; Vite build passed with the existing large-chunk warning. These are pure
UI-decision tests and compilation, not browser end-to-end testing.

### Emulator reproduction

Use a fresh temporary log directory and the existing CLI/Java/config; do not install
dependencies or kill another session if ports are occupied:

```powershell
$root='C:\Users\User\Documents\SwiftServe'
$logs=Join-Path $env:TEMP ('SwiftServeDocumentReview-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $logs | Out-Null
Set-Location -LiteralPath $logs
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
$env:DEBUG=''
$env:RUN_DOCUMENT_EMULATOR_TESTS='true'
$env:RUN_WORKER_POLICY_EMULATOR_TESTS='true'
$env:RUN_NATIONAL_ID_EMULATOR_TESTS='true'
node --use-system-ca "$root\mobile\my_app\rules-tests\node_modules\firebase-tools\lib\bin\firebase.js" emulators:exec --project demo-swiftserve-cleanup --config "$root\mobile\my_app\firebase.local.json" --only auth,firestore "node --test --test-concurrency=1 $root/swiftserve-backend/test/documentSuitability.emulator.test.js $root/swiftserve-backend/test/workerVerificationPolicy.emulator.test.js $root/swiftserve-backend/test/nationalIdIdentity.emulator.test.js"
```

18 passed, zero failed/skipped. The new suite exercises real Firestore transaction
retries with concurrent reviewers, replacement during face processing, stale binding
rejection and direct client denial. The existing worker-policy emulator suite explicitly
isolates document checks with a test seam; the new document suite and HTTP tests cover
the gate independently. This is not physical-device or complete browser-to-phone E2E.
Existing negative hiring batches still log the prior rules evaluation-limit messages;
valid policy fixtures pass. The broader known rules/date-picker failures were not
retested or changed by this phase.

## Local human review

The existing `scripts/startAdminDemo.js` launcher can serve the complete app on port
5003 for `demo-swiftserve-admin-management` with `firebase.admin-emulators.json`
(Auth 9499 / Firestore 8188). It deliberately avoids dotenv/live credentials.
Follow `admin/ADMIN_MANAGEMENT.md` for that isolated demo frontend/auth setup.
Do not use the live admin backend or the Netlify pilot: the former is refused by
this feature; hosted inference/storage remain unsupported in the latter.

With synthetic Client/Worker profiles in the SAME demo project: upload a generated
card, observe Awaiting review, open it as an authorized demo reviewer, reject it,
refresh as the owner and replace it. Verify an old admin tab cannot approve the
replacement with old IDs. Accept the new attempt, refresh and continue face capture.
Face/government/liveness/worker results remain separate. Synthetic patterns generally
do not yield real face descriptors; a no-face error at that stage is expected.
Do not use real National IDs for this demo.

## Remaining limitations

- Human review can wrongly accept or reject appearances; no government authenticity,
  fraud resistance, automated classification accuracy or biometric accuracy is proven.
- Actual Android/iOS capture/restore, network interruption recovery and browser reviewer
  interactions need device/browser QA. Reinstalling or changing accounts must continue
  to respect backend UID ownership and the current attempt.
- Consent is UI-level; durable consent/legal retention requirements remain separate.
- Pagination UI and multi-page hosted index behavior are not deployment-verified.
- Existing legacy submissions and already verified workers require their separately
  approved transition; this phase does not retrofit historical document acceptance.
- No deploy, hosting/storage migration, PSA/liveness provider, production account/claim
  changes, or worker-policy changes are approved. Stop after local review.

## Changed-file inventory (this phase)

Backend:

- `swiftserve-backend/src/services/documentSuitabilityService.js` (new)
- `swiftserve-backend/src/routes/documentSuitabilityRoutes.js` (new)
- `swiftserve-backend/src/app.js`
- `swiftserve-backend/src/routes/verificationRoutes.js`
- `swiftserve-backend/src/services/faceVerificationService.js`
- `swiftserve-backend/src/controllers/adminVerificationController.js`
- `swiftserve-backend/test/documentSuitability.test.js` (new)
- `swiftserve-backend/test/documentSuitability.emulator.test.js` (new)
- `swiftserve-backend/test/verificationRoutes.test.js`
- `swiftserve-backend/test/workerVerificationPolicy.emulator.test.js`
- `swiftserve-backend/test/workerVerificationReview.test.js`

Flutter:

- `mobile/my_app/lib/shared/repositories/document_review_repository.dart` (new)
- `mobile/my_app/lib/shared/repositories/verification_repository.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart`
- `mobile/my_app/test/helpers/fake_document_review.dart` (new)
- `mobile/my_app/test/worker_verification_test.dart`
- `mobile/my_app/test/verification_experience_test.dart`

Admin:

- `admin/src/components/verification/DocumentSuitabilityReviews.jsx` (new)
- `admin/src/lib/documentReview.js` (new)
- `admin/src/lib/verificationEvidence.js`
- `admin/src/page/verification/WorkerVerification.jsx`
- `admin/test/documentReview.test.js` (new)

Documentation:

- `swiftserve-backend/docs/document-suitability-phase61a.md` (new)
