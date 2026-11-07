# Worker verification separation — local Phase 1 and Phase 2

Local implementation only. No migration, production activation, PSA integration,
rules/configuration change, deployment, dependency installation or cloud operation.

## Policy

`worker-verification-v1`, evidence schema version `2`, requires all of:

1. TensorFlow face outcome MATCH from the server comparator, with its existing
   strong-band threshold. BORDERLINE cannot be approved by a manual exception.
2. Official PSA authentication evidence validated by a future backend integration.
3. Trusted server-side liveness evidence, independently validated and bound to the
   same account and submission.
4. Authorized, non-self administrative approval. Review cannot be opted out of.

Missing, unavailable, mock, invalid, unbound or expired mandatory evidence blocks
approval. Client verdicts and administrator-supplied check fields are not accepted.
Successful face comparison never proves government ID authenticity.

The policy uses the planned face/government/liveness/review/worker-decision status
vocabularies in `src/services/workerVerificationPolicy.js`. This phase stores final
comparison evidence and evaluates decisions; it does not implement a complete
asynchronous verification lifecycle, a revocation service or an expiry scheduler.

## Preserved TensorFlow behavior

The complete existing model/runtime, image preprocessing, EXIF/orientation handling,
descriptor extraction, distance calculation, similarity curve, threshold configuration
and `verifyFaces()` block are unchanged. Models and dependency/lockfiles are unchanged.
The existing `FACE_AUTO_VERIFY_MIN` name is retained for compatibility; it now only
selects the strong face band and does not authorize a worker.

`faceResultFor()` maps strong/borderline/mismatch to MATCH/BORDERLINE/NO_MATCH without
changing the calculated values. Existing face-detection errors remain supported.
Mismatch attempts retain scores and an independent face result, not uploaded images.

## Persistence and compatibility

New successful comparison submissions use the existing backend-only
`worker_verifications/{uid}` record, adding separate nested fields:

- `schemaVersion: 2`, stable `workerId`, new `submissionId`.
- `face`: outcome, provider/source, distance, similarity, band, thresholds, completion.
- `government`: initially NOT_INTEGRATED / provider NONE.
- `liveness`: initially NOT_IMPLEMENTED.
- `review`: required / PENDING.
- `workerDecision`: policy version, decision, eligibility, government-authentication
  indicator, bounded reason codes and evaluation timestamp.

Old scalar face fields remain compatibility aliases; `faceVerified` is not worker
authorization or government authentication. No raw images or descriptors are added
to Firestore. Existing private image storage behavior is reused.

`POST /api/verify` retains multipart ID type/number/document/selfie and the existing
match/similarity/confidence/distance/band fields. Strong and borderline submissions
return `verification.status=pending`, independent `faceResult` and a blocked worker
decision. Clients submitting check results/status fields get a 400 error. Additional
fields are backward-compatible for clients ignoring unknown JSON properties.

The face pipeline writes no trusted user/worker status or verification notification.
It rechecks the current worker and submission in a transaction after inference and
upload, for every storage backend. A concurrent approval/new pending submission cannot
be overwritten. Cleanup on a failed commit applies only to that request's new images.

Only `verificationDecisionService.addStatusWrites()` can write worker approval in
the affected verification paths, and it reevaluates policy evidence before scheduling
any trusted-status writes. Admin review reads current evidence/account transactionally,
checks existing review permissions and self-review, rejects evidence injection, and
commits review, decision, profile projections, notification and audit together.
An attempted approval with missing checks returns 409 VERIFICATION_REQUIREMENTS_NOT_MET
and does not commit the proposed approval or any profile/audit/notification writes.

## No official or liveness adapter exists

The evaluator's `validatedByBackend`, environment, account/attempt binding, reference
and timestamp properties are an INTERNAL future evidence contract, not a PSA protocol
or cryptographic proof by themselves. Only a separately reviewed future adapter may
produce them after validating actual trusted responses. No current route creates
these proofs, and an admin request cannot populate them. Never manually set flags to
make approval succeed. Positive unit fixtures simulate the internal evidence contract;
they are not official authentication and are never persisted to a real project.

MOCK government providers, mock environments and known synthetic/mock session labels
cannot satisfy the policy. The existing isolated mock session service is unchanged,
remains disabled by default and cannot update trusted profiles. No local mock is
enabled by these changes.

Consequently, NEW face-only workers cannot receive full approval in this phase.
That restriction is intentional. Official authentication and trusted liveness remain
separate future work requiring approval; there is no manual bypass.

## Legacy protection and deferred work

No existing account is migrated or revoked. The new pipeline refuses to rewrite
existing verification records without schema version 2, and refuses submissions from
already verified accounts. Admin mutations of legacy/already verified records return
409 LEGACY_VERIFICATION_PROTECTED without writes. This also pauses review/resubmission
of older pending or rejected records until a transition is explicitly approved.

Existing verified workers continue to use their existing compatibility status and
rules. They must not be described as having established PSA authentication. A future
migration must inventory historical decisions, preserve provenance/history, agree on
legacy eligibility and existing-booking treatment, rehearse on synthetic data, and
request separate approval before any real records or rules change.

The existing Flutter pending/verified response handling is retained. A new widget test
checks that a strong face-only pending response does not show worker approval. The
legacy verified-response test remains as backward-compatibility coverage, not a claim
that a strong match can still grant verification. Full separated status UI, discovery
and authorization-schema migration belong to a later approved phase.

Pending images still use the existing storage/retention implementation. Since new
submissions cannot finish approval, bounded retention and cleanup of indefinitely
pending records needs explicit review before any production activation. This phase
does not add a cleanup job or claim secure-device deletion. Existing storage cleanup
after final decisions is retained; cleanup is not atomic with Firestore commit.

## Changed files

New:
- `src/services/workerVerificationPolicy.js`
- `test/workerVerificationReview.test.js`
- `docs/worker-verification-policy.md`

Modified:
- `src/services/faceVerificationService.js` (submission/persistence only)
- `src/services/verificationDecisionService.js`
- `src/routes/verificationRoutes.js`
- `src/controllers/adminVerificationController.js`
- `test/faceVerificationService.test.js`
- `test/verificationDecisionService.test.js`
- `test/verificationRoutes.test.js`
- `../mobile/my_app/test/worker_verification_test.dart`
- `docs/national-id-mock.md` (architecture cross-reference)

No production, staging, rules, model, dependency, API URL, claim or allowlist files
were changed. Existing unrelated staged/unstaged/untracked work was retained.

## Validation commands

Backend directory, synthetic fixtures only, with emulator hosts as a safety boundary:

```powershell
$env:GCLOUD_PROJECT = 'demo-swiftserve-policy'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8187'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
node --test test/verificationDecisionService.test.js test/faceVerificationService.test.js test/verificationRoutes.test.js test/workerVerificationReview.test.js test/nationalIdIdentity.test.js test/verificationStorageService.test.js test/netlifyAuthentication.test.js test/netlifyUploadHardening.test.js test/adminDataRoutes.test.js
```

The suite uses in-memory database/auth fixtures and temporary synthetic image files;
it does not require a running emulator, credentials, PSA or production access.

Flutter directory:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/worker_verification_test.dart test/national_id_mock_test.dart test/liveness_tracker_test.dart
```

No real-person accuracy, physical-device, Linux/hosted, real PSA or live liveness
testing was performed in this phase. Full application and rules/emulator suites are
not claimed as tested. Prior model-inference audit results remain separate evidence.

Observed final results (November 3, 2026):

- Backend command above: **71 passed, 0 failed, 0 skipped**.
- Flutter command above: **33 passed, 0 failed**.
- Flutter analyzer: **No issues**.
- Changed JavaScript syntax checks and scoped `git diff --check`: passed.
- Read-only comparison against the pre-task staged face service confirmed the entire
  model/runtime/preprocessing/descriptor/scoring/threshold block is identical. No
  working-tree model or dependency changes were found.

An intermediate rollback test expected removal of empty directories as well as
images. It was corrected to assert the security requirement (no remaining image
files); the final run above passes. Initial sandbox subprocess restrictions required
rerunning Node tests with local subprocess permission; no application failure was
inferred from that environment error.

Further approval is required for migration, eligibility/rules rollout, full status UI,
trusted liveness integration, PSA onboarding/integration, real identity data, production
changes or deployment. Do not activate this as a complete official verification system.
