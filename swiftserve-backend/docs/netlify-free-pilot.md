# Netlify Free Admin Management pilot — LOCAL ONLY

This implementation is not deployed or approved for production. No Netlify site,
cloud storage, account, billing method, IAM binding, rule or Firebase production
record was created or changed. Existing `.env`, staging configuration, production
API URL, Super Admin allowlist and claims remain untouched. Keep all push and
expiration gates disabled. No scheduled function is installed by this pilot.

## Scope and boundaries

`netlify.toml` serves the existing React/Vite frontend through Netlify Dev on
http://localhost:8888 and wraps the existing Express app with `serverless-http`.
The `/api/*` routes and existing authorization middleware remain in use. In pilot
mode the shared authentication middleware checks revocation/disabled status for
all authenticated user/profile/role/photo, route, SOS, verification, test and admin
requests. Registration availability remains public when no token is supplied;
supplying a token requires verification. Admin permission/Super Admin checks remain
additional requirements. Non-pilot authentication behavior is preserved. Only
bounded error codes are logged by the shared authentication middleware. Original
`npm start`, the staging launcher, and the earlier admin demo remain separate.

The new handler refuses to run outside `NETLIFY_DEV=true` and exact project
`demo-swiftserve-netlify`, `(default)` database, loopback Auth/Firestore emulators,
and explicit disabled gates. It rejects credential files, Firebase config overrides,
Netlify login tokens and Super Admin allowlists. Blobs network requests are limited
to loopback HTTP with redirects rejected; there is no cloud fallback. These guards
intentionally make this version NOT DEPLOYABLE. The Netlify cloud build command
also fails intentionally. A future hosted version needs a separate reviewed change.

For local gateway invocation, client-IP metadata is normalized to a shared loopback
rate-limit bucket and caller X-Forwarded-For is removed. This is deliberately not
a production proxy policy. Admin requests are limited to 120/minute per process.
Pilot uploads have a 5/15-minute per-process limit and a durable 5/day/worker attempt limit.
Worker eligibility and quota reservation happen before multipart buffering/native
decoding. Invalid uploads consume an attempt. Decoded dimensions must match the
validated header. Quota days use UTC; service scheduling is unaffected.
All origins except the documented local frontend origins are rejected by CORS.
No-Origin native/tool requests still need authentication and authorization.

Netlify CLI 27.16.1 is a devDependency. The launcher uses `--offline`, disables
telemetry, preserves TLS verification with the Windows trust store, and disables
the unused Edge Functions runtime through the CLI's internal flag. That flag is
version-sensitive; recheck it when upgrading CLI. No `netlify login`, `link`,
`deploy`, `init` or resource-creation command is part of local setup.

## Run locally (three PowerShell terminals)

Use Node 24 and Java 21. Dependencies are in `swiftserve-backend/package-lock.json`.
Do not replace `.env` with demo values or run any cloud deployment command.

Terminal 1, from a temporary logging directory:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:DEBUG = ''
node --use-system-ca C:/Users/User/Documents/SwiftServe/mobile/my_app/rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:start --project demo-swiftserve-netlify --config C:/Users/User/Documents/SwiftServe/firebase.netlify-emulators.json --only auth,firestore
```

This uses Auth 9599, Firestore 8288, hub 4498 and logging 4598, separate from the
existing staging and admin-demo environments. Data is synthetic and emulator-local.
Emulator persistence/export is not configured; keep it running during review.

Terminal 2:

```powershell
cd C:\Users\User\Documents\SwiftServe\swiftserve-backend
npm run pilot:seed
npm run pilot:dev
```

Wait for Netlify Dev's ready banner AND `Loaded function api` before testing.
Open http://localhost:8888. Synthetic Super Admin login:
`super-netlify@example.test` / `LocalTestOnly-Password123!`.
The worker fixture is `worker-netlify@example.test` with the same disposable
password. Never reuse these fixture credentials for real accounts. The seed creates
only absent synthetic accounts; existing fixtures are retained, not reset.

The launcher injects only local public web SDK settings into the Vite child process.
The original admin `.env` is not edited. UI emulator guards allow only known demo
project IDs and development builds. Never enter production credentials here.

Terminal 3, from `swiftserve-backend`:

```powershell
npm run pilot:test:http
```

This actual HTTP smoke test signs into local Auth, checks the protected session,
creates a new synthetic worker, uploads two generated PNGs, fetches both images
through authorized routes, compares the exact bytes, verifies denied worker access,
and calls manual reconciliation. It never reads credentials or application records
from a cloud project. Browser DOM interaction remains a separate manual check.

If CLI hot reload stalls, stop only this pilot terminal with Ctrl+C and restart
`npm run pilot:dev`; don't delete `.netlify`, backups or user work. Other local
Vite/backend processes are not part of this pilot. `.netlify/` is ignored.

## Verification images and retention

The existing `/api/verify` returns a specific 503 in this pilot because hosted
face verification is unverified. Its normal local Express behavior is retained.
An additional LOCAL-ONLY endpoint, `POST /api/pilot/verification-images`, accepts
multipart `idType`, `idNumber`, `document`, and `selfie` from an authenticated worker.
Use synthetic documents only. It creates a **pending manual review** with
`faceVerified:false`; it never fabricates a successful face match or auto-approval.
The Flutter onboarding UI was not rerouted to this endpoint.

Each file must be JPEG/PNG, at most 1.5 MiB, 16–2048 pixels per side and at most
4,000,000 pixels. Headers are checked before native image decoding. Exactly one
document and one selfie are allowed. Originals never enter static publish assets.
The function rejects decoded request bodies above 4 MiB, below the platform's
approximately 4.5 MB binary payload budget. JSON/multipart envelopes still add
overhead; this is not permission to upload a 6 MB binary request.

Netlify Blobs uses a site-scoped store; do not use deploy-scoped stores for records
that must survive redeployment. All object keys are generated server-side and
contain a version, demo project, local environment, owner hash, submission UUID
and fixed image kind. There is no arbitrary-key download endpoint. Journal and
quota documents are server-only under current default-deny Firestore rules.

The private image route remains `/api/admin/verifications/:workerId/image`, with
optional `kind=selfie`. Current `verification.view` authorization is required every
time. The route obtains the key from the worker verification record, then checks
the asset's owner, submission, kind, state and deadline. Responses use
`Cache-Control: private, no-store` and `nosniff`. Frontend protected fetching now
handles both local and Blobs assets and preserves the selfie query parameter.
Images are base64-encoded in Lambda responses and decoded by the gateway; tests
assert byte equality, not merely nonempty responses.

Before an object write, Firestore records an `uploading` journal entry. Object
write completion changes it to `stored`. A transaction links both assets and the
verification record, rechecks worker/submission eligibility, and marks assets
`active`. Cleanup and attachment contend on the same journal documents.
An interrupted/unattached upload becomes cleanup-eligible after one hour. Each
image has a maximum retention deadline of 30 days from upload, including pending
reviews; authorization/expiry are checked both before and after object retrieval,
before returning bytes. Already downloaded images cannot be recalled. This
pilot maximum can be earlier than 30 days after a later admin decision. Do not
claim it is the existing GCS lifecycle policy.

Manual `POST /api/pilot/verification-images/reconcile` is Super Admin-only. It scans
at most 25 assets and 25 quotas per call in document-ID order, including records
with missing/malformed timestamps. Fenced maintenance leases and per-candidate
durable cursors preserve progress across calls/restarts; a stale lease cannot
overwrite progress. Calls also process one bounded orphan-inventory prefix.
It stops at candidate boundaries after 45 seconds and reports `failed`,
`interrupted`, `lostOwnership`, `quarantined`, `possiblyMore`, and acknowledgment
outcomes. It does not claim a complete sweep. Individual SDK operations can still
outlast the boundary budget; no hosted timeout guarantee is claimed.
Repeat until no more work is indicated. Errors return a failure HTTP status.
Use `npm run pilot:images:reconcile` with `PILOT_ADMIN_TOKEN` from the local Auth
emulator set privately in your terminal; never print or commit the token.

Cleanup transactions check current verification references, claim a fenced
60-second lease, and prevent attachment after deletion begins. An acknowledgment
commits only with the matching, unexpired lease; stale owners cannot count deletion
as successful. Retryable failures retain compact recovery metadata, bounded error
codes, and exponential backoff capped at one day. Transient candidate failures are
reported and revisited on the next complete sweep rather than pinning its cursor.

Malformed journals are replaced by bounded quarantine diagnostics (no raw exception
or arbitrary original fields), retaining a valid scoped key when recoverable. A
30-day quarantine grace protects possibly linked images before recovery deletion.
Unrecoverable quarantine metadata is purged after that grace. Timestamp validation
happens before timestamp methods are invoked. Quarantine counts remain visible;
an operator must investigate them rather than treating quarantine as proof of deletion.

Successful deletions keep compact tombstones for 7 days, re-delete daily during
that window, and receive a final acknowledged delete before journal removal.
Daily quota records expire 2 days after the UTC day's start. Legacy quotas derive
expiry from updatedAt; malformed quota dates get a one-day fail-closed grace.
Actual removal happens only when manual reconciliation runs. Pending/active image
journals survive until their 30-day maximum; failed deletions retain minimal recovery
records until acknowledged, even beyond these windows. Never age out unacknowledged
deletion work just to meet a storage target.

An SDK Blobs inventory sweep recovers generated objects with missing journals,
including writes that arrive after tombstone removal. It reserves a recovery journal
transactionally before deletion; new uploads journal before writing objects, so
attachment cannot race orphan cleanup. The SDK lacks an exposed continuation cursor;
the inventory uses a durable bounded prefix tree, at most two list pages per call,
and subdivides large leaves. Complete small leaves compact their shared owner hash.
New objects behind a completed prefix are recovered in the next sweep. Repeated
manual calls are required to drain large trees; monitor inventory progress and
costs. Unknown/non-generated keys are counted and left untouched. If a supplied
test store lacks listing support, `inventoryUnavailable` is explicit; the real
pilot SDK store supports listing.

Interrupted deletion is safe to retry; object storage and Firestore are not atomic.
No fixed physical deletion deadline is guaranteed during outages or suspension.

No automatic cleanup schedule is enabled. Free-plan suspension or an offline local
machine can delay physical deletion; exact-time deletion and uptime are NOT
guaranteed. Do not collect real identity documents until retention operations,
access controls, outage handling and the privacy policy have been separately approved.
No existing production image was migrated or read.

## Automated validation

Focused unit tests (no cloud credentials):

```powershell
# From swiftserve-backend. Both emulator variables must refer to local listeners.
$env:GOOGLE_CLOUD_PROJECT='demo-swiftserve-netlify'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9599'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8288'
$env:GOOGLE_APPLICATION_CREDENTIALS=''
node --test test/netlifyPilot.test.js test/verificationStorageService.test.js test/verificationRoutes.test.js test/faceVerificationService.test.js
```

Pilot integration tests (actual adapter + SDK Blobs local server + Firebase):

```powershell
$env:RUN_NETLIFY_EMULATOR_TESTS='true'
node --test test/netlifyPilot.emulator.test.js
Remove-Item Env:RUN_NETLIFY_EMULATOR_TESTS
```

Existing admin security tests need a separately started Auth/Firestore emulator pair
whose CLI project is `demo-swiftserve-admin-management`; don't point that suite at
the pilot project's default Auth emulator namespace. Use `ADMIN_MANAGEMENT.md`
with fresh available ports if the older demo is running. The suite's synthetic
Auth fixtures must start absent; don't reset an existing user's demo to rerun it.

Other checks:

```powershell
# backend (opt-in emulator suite flags unset)
node --test --test-reporter=tap
node scripts/probeNetlifyPilot.js
# admin
node --test test/*.test.js
npm run build -- --outDir <fresh-temporary-output-directory>
```

No Dart files changed for this pilot; Flutter analyzer/tests and unrelated existing
rules/date-picker failures are not represented as revalidated or fixed. Existing
admin security emulator tests and the pilot's default-deny rules checks are separate
from the complete Firestore/Storage rules suite.

## Findings and deployment prerequisites

- Local Windows/Node 24 can load canvas/WASM/models and reject a blank synthetic
  image. This does not prove Linux native-module packaging, real-document accuracy,
  hosted memory/timeout behavior or physical-device integration. Keep hosted face
  verification disabled. `probeNetlifyPilot.js` prints local startup/RSS measurements.
- Netlify CLI requires an unused Edge runtime unless disabled; the local launcher
  avoids it. CLI hot-reload can stall; clean restarts were needed during verification.
- Compatible security updates resolve body-parser 2.4.0, Multer 2.5.0,
  ip-address 10.7.5 and qs 6.17.1. Runtime audit now reports 6 moderate / 0 high
  affected packages. Remaining Google Storage gaxios/uuid and Firestore API
  google-gax/rimraf/glob/minimatch chains require separate reviewed remediation.
  Firestore still constrains firestore-api to 0.2.x; do not force newer major
  APIs or blanket overrides. No broad audit-fix was used. Dev dependencies have
  additional findings; runtime-only audit is not a clean full-graph audit.
- Netlify Free has a shared 300-credit hard limit; suspension affects availability,
  not just new deployments. Plan limits and actual account eligibility need checking
  at future signup. No card or paid add-on is authorized. Blobs usage has no standalone
  published byte/operation price; don't promise a fixed number of retained documents.
- Existing non-pilot ADC initialization is preserved, not production-hardened here.
  A future hosted version needs explicit project/default-DB checks, least-privilege
  credential handling, configured trusted ingress/origins, MFA/email-verification
  decisions, and reviewed Super Admin identity activation. No live UID was allowlisted.
- Strong storage isolation for this version means rejecting all production/staging
  targets and remote transports. Real hosted staging/production site isolation,
  secret scoping and provider account access remain unverified. Use separate sites,
  not merely deploy contexts sharing one Blobs store, in any future design.

Approval is still required before cloud accounts/resources, credentials/IAM changes,
deployment, API URL changes, rules/index deployment, real administrator creation,
real-document collection or production Admin Management activation. Billing,
push delivery and scheduled expiration remain outside this pilot.

## Original local implementation results (before second-stage hardening)

- Focused storage/verification/pilot unit command above: **30 passed, 0 failed**.
- Final backend `node --test --test-reporter=tap`: **183 passed, 0 failed**.
  Opt-in integration suites were not enabled in that command; run them separately.
- Pilot integration command above: **8 passed, 0 failed**, with actual
  `serverless-http`, SDK local Blobs server, Auth/Firestore emulators, exact binary
  checks, expired/invalid token rejection, private-journal rule checks, interruption,
  deletion retry, retention and concurrent cleanup fencing.
- Existing admin Auth/Firestore emulator suite: **11 passed, 0 failed** on a fresh
  correctly named demo emulator pair (Auth 9699, Firestore 8388). An initial attempt
  incorrectly paired that suite's project with the pilot Auth namespace; fixture
  sign-in failed and 11 tests were cancelled. No unrelated fixture was changed.
- Frontend `node --test test/*.test.js`: **8 passed, 0 failed**.
- Frontend Vite build to a fresh temporary directory: **passed**. Existing large
  bundle warning remains. No static output was published or overwritten.
- Existing backend `npm run check` syntax checks and `git diff --check`: **passed**.
- `npm run pilot:test:http`: **passed** through actual offline Netlify Dev on 8888,
  including synthetic upload and both private image variants. Initial gateway tests
  exposed missing IP metadata, missing strong-consistency context, and binary output
  encoding; these were corrected. A proxy crash also left a task-owned Vite process;
  only that verified PID was stopped before a clean restart. One repeated integration
  test collided with old synthetic journal history; tests now use per-run namespaces
  without clearing existing data.
- Windows Node 24 probe: application load **2262 ms**, **108 MiB RSS**, canvas not
  loaded; model load **1275 ms**, **224 MiB RSS**; blank synthetic inference returned
  expected `FACE_NOT_DETECTED`, **401 MiB RSS**. These are one-machine observations,
  not guarantees or measured peak memory on Netlify/Linux. The reusable probe can
  produce different timings under load. No real-face matching was validated here.
  A final execution of the reusable probe measured **1426 ms / 95 MiB** for app
  load (canvas absent), **581 ms / 259 MiB** for models, and **396 MiB** after the
  expected blank-image rejection. Both runs were local Windows measurements.
- Runtime audit: **8 moderate / 2 high** advisories; full dependency installation
  reported **27** including dev dependencies. Existing package versions at unchanged
  lockfile paths were compared to HEAD and did not change. Lockfile growth is mainly
  the CLI/dev dependency graph. No `npm audit fix` was used.
- No Flutter analyzer/suite, full Storage-rule suite, browser DOM tests, real-device
  push tests, cloud quotas, hosted secrets or production readiness is claimed.

## Second-stage local security hardening

Only compatible dependency resolutions changed: Multer ^2.5.0 (installed 2.5.0),
body-parser 2.4.0, ip-address 10.7.5, qs 6.17.1. Lifecycle scripts were disabled
during installation/update. Express, Firebase Admin, Netlify CLI and face dependency
major versions were not forced. Runtime audit: **6 moderate, 0 high/critical**.
Remaining runtime paths:

- Firebase Admin -> Storage 8.2.0 -> gaxios 6.7.1 -> uuid 9.0.1 (including its
  older Google Auth branch). Storage 8.4.0 uses newer auth/gaxios, but this separate
  SDK-chain update is deferred for focused compatibility/security review.
- Firebase Admin -> Firestore 9.2.0 -> firestore-api 0.2.0 -> google-gax 5.0.8 ->
  rimraf 5.0.10 -> glob 10.5.0 -> minimatch 9.0.9. Registry inspection during the
  audit found current Firestore still constrains firestore-api to ^0.2.0; newer
  firestore-api 0.7.x/gax 6 are outside that range. Updating rimraf alone also does
  not solve the current glob advisory. No cross-major override was applied.

Full backend audit (including CLI/dev tooling): **21 moderate + 2 low = 23 affected
package entries; 0 high/critical**. These include inherited advisory entries, not
23 independent exploitable bugs. Moderate entries: @fastify/static, @netlify/build,
@netlify/build-info, @netlify/dev, @netlify/functions-dev, @netlify/functions-utils,
@netlify/zip-it-and-ship-it, @typescript-eslint/typescript-estree, @vercel/nft,
archiver, detective-typescript, detective-vue2, gaxios, glob, google-gax, minimatch,
netlify-cli, precinct, readdir-glob, rimraf, uuid. Low: @netlify/config, deepmerge.
The first full audit attempt failed with a registry socket hang-up; a bounded
retry succeeded. Audit exits nonzero while vulnerabilities remain.

Focused tests (backend):

```powershell
node --test test/netlifyStorageReliability.test.js test/netlifyAuthentication.test.js test/netlifyUploadHardening.test.js test/netlifyPilot.test.js
```

**24 passed, 0 failed.** Covers malformed keys/timestamps, bounded quarantine,
expiry during retrieval, stale deletion acknowledgments, retries, actual overlapping
takeover with an advancing clock, interrupted cursor recovery, tombstone/quota
removal, late orphan/backlog recovery, empty intermediate list pages, pre-decode
eligibility/quota checks, valid manual uploads, and revoked/disabled authentication.
Four storage defect assertions were demonstrated failing before the implementation
change (malformed key, missing/numeric timestamps, expiry during read, stale ack).
Retry behavior was existing coverage, not a newly reproduced defect. An initial
test fixture lacked the old query API; that harness was corrected before comparing
old behavior. An added backlog test exposed prefix-walk inefficiency during this
implementation; shared-prefix compaction corrected it. Initial isolated test
execution hit sandbox spawn EPERM; isolated execution with approval succeeded.

The dedicated emulator suite now includes real quarantine/purge/orphan recovery
and expiry-during-Blobs-read tests. Run only with synthetic data and the existing
dedicated demo listeners:

```powershell
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9599'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8288'
$env:RUN_NETLIFY_EMULATOR_TESTS='true'
node --test test/netlifyPilot.emulator.test.js
Remove-Item Env:RUN_NETLIFY_EMULATOR_TESTS
```

Final dedicated suite: **10 passed, 0 failed**. Final full backend suite:
**203 passed, 0 failed** with demo-only Firebase targets and disabled feature gates;
this included the 9 existing expiration emulator cases. Admin Management and Netlify
integration suites are opt-in in that command; Netlify's 10 cases ran separately.
Expected permission-denied messages in negative emulator cases are passing assertions.

This creates only disposable synthetic emulator fixtures; never run seed/integration
commands against cloud projects. Existing fixtures and unrelated user work are not
cleared. Auth/Firestore emulator and private-journal denial checks cannot prove
hosted IAM, actual Blobs consistency, Linux native packaging or real-device behavior.
The broader Admin Management emulator suite is opt-in and was not rerun in this
hardening task; existing adapter management cases were rerun. No Flutter sources
changed; Flutter and the unrelated complete Storage/rules/date-picker suites were
not rerun or repaired. Frontend unit suite: **8 passed**; Vite build to a fresh temp
directory passed with the existing >500 kB bundle warning. Backend syntax checks
and git diff whitespace checks passed (existing CRLF warnings remain).

Files changed by this hardening task, relative to the existing local pilot:

- package.json; package-lock.json
- src/services/netlifyVerificationStorage.js
- src/routes/netlifyPilotRoutes.js
- src/middleware/authMiddleware.js
- test/netlifyStorageReliability.test.js (new)
- test/netlifyAuthentication.test.js (new)
- test/netlifyUploadHardening.test.js (new)
- test/netlifyPilot.emulator.test.js
- docs/netlify-free-pilot.md

Failed deletion recovery metadata has no age-only purge: permanently losing that
record could orphan an identity image. Counts/backlog/invalidObjects/quarantine
must be monitored and unresolved failures investigated. This is a deliberate
exception to finite successful-history retention, not a guarantee of bounded total
storage under endless failures. Inventory scans add reads/list operations and can
take many manual calls with very large inventories. No automated cleanup, cloud
hosting, production access, push, expiry scheduling or real-image collection is
enabled or approved. Production deployment remains blocked.

## Exact files modified or created for the original pilot

This list excludes unrelated pre-existing work already present before this task.

Modified:

- `.gitignore` (ignore local `.netlify/` state)
- `admin/src/lib/firebase.js`
- `admin/src/lib/firebaseTarget.js`
- `admin/test/firebaseTarget.test.js`
- `admin/src/components/verification/WorkerVerificationModal.jsx`
- `swiftserve-backend/package.json`
- `swiftserve-backend/package-lock.json`
- `swiftserve-backend/src/app.js`
- `swiftserve-backend/src/config/firebase.js`
- `swiftserve-backend/src/controllers/adminVerificationController.js`
- `swiftserve-backend/src/routes/verificationRoutes.js`
- `swiftserve-backend/src/services/faceVerificationService.js`
- `swiftserve-backend/src/services/profilePhotoService.js`
- `swiftserve-backend/src/services/verificationStorageService.js`

Created:

- `netlify.toml`
- `firebase.netlify-emulators.json`
- `admin/src/lib/verificationImages.js`
- `admin/test/verificationImages.test.js`
- `swiftserve-backend/netlify/functions/api.js`
- `swiftserve-backend/src/config/netlifyPilot.js`
- `swiftserve-backend/src/routes/netlifyPilotRoutes.js`
- `swiftserve-backend/src/services/netlifyVerificationStorage.js`
- `swiftserve-backend/src/services/verificationImagePolicy.js`
- `swiftserve-backend/scripts/startNetlifyPilot.js`
- `swiftserve-backend/scripts/seedNetlifyPilot.js`
- `swiftserve-backend/scripts/testNetlifyPilotHttp.js`
- `swiftserve-backend/scripts/reconcileNetlifyPilotImages.js`
- `swiftserve-backend/scripts/probeNetlifyPilot.js`
- `swiftserve-backend/test/netlifyPilot.test.js`
- `swiftserve-backend/test/netlifyPilot.emulator.test.js`
- `swiftserve-backend/docs/netlify-free-pilot.md`
