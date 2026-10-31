# Firebase-managed expired jobs: local implementation and activation gates

Status: implemented locally, disabled by default, not deployed. No production
records, project configuration, APIs, IAM or security rules were inspected or
changed during implementation. Production readiness and physical-device push
receipt are **not established**. This guide supersedes Render instructions only
for the new `expired-jobs` Functions codebase; the old runner remains preserved.

## Runtime and invariants

`mobile/my_app/functions/src/index.js` exports Node 22 second-generation handlers:

- `expireEligibleJobs`: every 30 minutes UTC, 540-second timeout, three Scheduler
  retries. A 240-second soft budget and 1,000-document invocation cap preserve a
  checkpoint for another invocation. Incomplete scans throw after checkpointing;
  retries or the next scheduled invocation resume. `busy` is a lease skip, not a
  completed sweep. Completion requires an empty pending query. More than 1,000
  jobs are covered across invocations, not silently truncated.
- `dispatchExpiredJobPush`: created-document trigger for
  `_jobExpiryPushOutbox/{eventId}`; retries enabled. No FCM in a transaction.
- `retryExpiredJobPush`: every five minutes UTC, up to 100 due pending/stale-sending
  events per invocation. It attempts other events even if one fails, then reports
  failures. A separate cursor audits up to 100 active outboxes per invocation
  for malformed timestamps. Full due batches and unfinished/busy metadata audits
  report continuation required, never successful completion of the whole pass.
- `registerPushDevice`: callable, requires Firebase Auth **and App Check**.
  Ownership comes exclusively from `request.auth.uid`, never request data. No
  client Firestore write permission is needed for token registration.

Each handler has maxInstances=1/concurrency=1. These limits do not replace leases:
triggers, independent handlers, retries and rolling revisions can overlap.
Firebase manages Cloud Scheduler resources for both schedules; this is not Render
hosting and does not require somebody's app or development PC to stay online.
Schedules are not exact-second expiration guarantees. Large backlogs and retained
fixed cutoffs can add latency; alert on repeated continuation and old cutoffs.

One maintained policy lives in `functions/src/expiredJobPolicy.js`, with SDK
adapters for Functions and the existing backend. The backend can still install
its own dependencies independently; it must be packaged with the shared source.
Do not run the legacy Render writer and Firebase expiration writer together.

Preserved policy: pending jobs only; valid non-midnight `scheduleFrom`; consistent
range/alias; no application of **any** status; no worker/acceptance/booking,
tracking, conversation, report, SOS or review history. Philippine-midnight and
legacy date-only records remain conservative skips. The original root is marked
expired, not deleted. Notifications and outboxes share a deterministic event ID:
`jobExpired_ID` for ordinary legacy IDs or `jobExpired.v2.<SHA-256(requestId)>`
for other valid IDs. The original requestId is retained. Read state and history
are preserved. An identity mismatch fails instead of replacing
somebody else's notification. Owner-only reposting uses the existing transaction,
a new job ID and fresh date/time; no old applications/assignment are copied.

## Durable state, shutdown and safety gates

`_jobExpiryControl/preview` and `/expiration` have independent versioned checkpoints:
project, database, owner UUID, increasing fence, leaseUntil, fixed cutoff, last
successfully processed candidate cursor, status and completion timestamp. Each
candidate checkpoints transactionally and renews the two-minute lease; a
30-second candidate-boundary heartbeat check also protects delayed page reads.
Every candidate transaction and checkpoint
transaction checks the gate and current owner/fence/expiry. A stale runner cannot
expire a job or advance another runner's cursor after takeover. A failed candidate
replays, while successful candidates checkpoint within the page. A crash between
job commit and checkpoint may replay that candidate safely; committed expirations
are idempotent. Budget exhaustion retains the latest successful cursor.
SIGTERM requests
cooperative interruption, waits for the current awaited operation and retains a
recoverable checkpoint. A hard kill recovers after the lease expires. Clock skew
and a single operation exceeding the remaining lease cause safe failure/retry,
not an unsafe write. Slow pages can resume inside the page on the next invocation.

Defaults in `functions/.env.example`:

| Environment setting | Default / requirement |
| --- | --- |
| EXPIRED_JOB_CLEANUP_ENABLED | false |
| EXPIRED_JOB_CLEANUP_DRY_RUN | true |
| EXPIRY_METADATA_WRITES_ENABLED | false |
| EXPIRY_PUSH_ENABLED | false |
| EXPIRY_TOKEN_REGISTRATION_ENABLED | false |
| EXPIRY_EXPECTED_PROJECT | swiftserve-production; exact runtime match required |
| EXPIRY_DATABASE | (default); named databases rejected |
| EXPIRY_REGION | us-central1 placeholder; confirm actual database region before deployment |
| EXPIRY_SERVICE_ACCOUNT | explicitly approved least-privilege runtime identity |

A second, Admin-only emergency gate document `_jobExpiryControl/settings` must
explicitly allow `previewEnabled`, `expirationEnabled`, `pushEnabled`, and/or
`registrationEnabled` independently. Missing or false fields fail closed.
Disabled handlers return before acquiring any Firestore state. Metadata-disabled
sweeps do not query jobs or create leases. **Durable dry run is not zero-write:**
when separately approved, it writes/renews preview checkpoint/lease metadata and
incurs Firestore read/write charges, but never changes jobs, notifications or
outbox. Production previews, including these operational writes, need approval.
For a strict zero-production-write preview, keep the metadata gate off and use
isolated emulator fixtures; no production preview was run here.

Preflight validates the Admin SDK's actual project and `(default)` database,
not Firebase CLI selection. Production rejects FIRESTORE_EMULATOR_HOST. Emulator
mode requires FUNCTIONS_EMULATOR=true, a demo-* project, explicit expected project
and a Firestore emulator host. `firebase.local.json` binds services to loopback.
No service-account private keys or tokens belong in source or logs.

## Outbox, devices and delivery semantics

Expiration, notification and outbox creation commit atomically. Ordinary IDs use
`jobExpired_ID`; other valid IDs use `jobExpired.v2.<SHA-256(requestId)>`. Existing expired jobs produced by the legacy runner are
not retroactively backfilled or pushed. A separate reviewed migration would be
needed for historical notifications.

Outbox records hold recipient/request/event IDs, status, attempts, dueAt and a
transactionally claimed owner. A two-minute sending lease protects concurrent
attempts. Private `deliveries/{sha256(token)}` journals record FCM acceptance or
permanent invalidation per token. Recovery skips accepted tokens after partial
failure. Backoff starts at 60 seconds, doubles, caps at one hour, and failed
claims stop at eight (`dead_letter`), including interrupted claims. No-device
events retry within that window. Every send rechecks the current claim.
Bounded `lastErrorCode` diagnostics retain SDK error codes, never raw messages or tokens.
Invalid event context is dead-lettered without sending. `no_targets` means no
eligible token was sent, **not** successful delivery. `accepted` means at least
one FCM acceptance, never proof of receipt/display/read. The original in-app
notification remains the durable fallback regardless of push outcome.

Tokens are stored only by the callable in `users/{uid}/push_devices/{installationId}`
with a 20-device bound, supported-platform/token-length checks and timestamps.
A private `_pushTokenOwners/{sha256(token)}` binding prevents an old account from
sending to a token rebound to a different account. Revocation cannot remove the
new owner's binding. Permanent FCM invalid-token errors remove only a matching
current token, never a replacement registered during a send. Current Firestore
rules deny direct client access to these new paths, including the token owner.
**No security rule was changed.** Review actual deployed default-deny behavior
before deployment; emulator rules do not establish deployed rules.

Firebase auth/account changes rotate tokens; explicit sign-out attempts bounded
server revocation before local invalidation. Registration retries on token
refresh, a new profile session or app resume. Offline revocation or in-flight
sends cannot be recalled. Therefore lock-screen push text contains no job title,
address, name or other task details, and opens revalidate the active account and
owned expired job. Token values/hashes must not be logged. Token-owner bindings,
stale-device records and delivery journals currently have no automatic TTL;
approve a retention/cleanup policy before broad rollout. Device slots from old
installations may need reviewed removal when the 20-device cap is reached.

FCM/Firestore cannot atomically commit a network send and its receipt journal. A
crash/timeout after FCM accepts but before the journal commit can resend. Stable
event IDs, Android tags, APNs collapse IDs and session-local route dedup reduce
repeats; **exactly-once push display is not promised**. Collapsing does not retract
an already displayed notification. Do not interpret an `accepted` journal as a
device delivery acknowledgement.

## Local reliability hardening (not activated)

Ordinary request IDs (`[A-Za-z0-9_-]`, up to 128 characters) retain their
`jobExpired_ID` event ID. Other valid Firestore document IDs use
`jobExpired.v2.<SHA-256 of the exact UTF-8 request ID>` for notification and outbox
IDs. The original ID remains in `requestId`; ownership/history queries use that
original ID. The separate dotted namespace cannot collide with ordinary legacy
IDs. Dispatch and Flutter routing also accept existing `jobExpired_ID` events for
unusual IDs within Firestore's 1,500-byte ID limit. No migration or rule change is
needed. Node crypto and the already resolved Dart crypto 3.0.7 (now direct) agree.

Unsupported/mismatched identities become `dead_letter` transactionally, with
bounded reason `invalid_event_context`, before sending. Original context and
journals are retained. Recovery excludes terminal events: 100 bad events may
consume one invocation but cannot monopolize subsequent batches. Alert and review;
never automatically delete or blindly replay them. Transient database failures
still fail recovery and remain retryable.

The scanner renews its 120-second fenced lease sequentially between candidates
at every successful candidate checkpoint, retaining that candidate cursor. A
30-second heartbeat check runs before candidate work if the previous operation
was delayed; no page must fit entirely within the invocation budget.
No asynchronous heartbeat races candidate work. Each eligible transaction also
rechecks the gate/lease after context reads, immediately before writes. Expired or
fenced owners cannot renew/checkpoint; failed candidates replay from the last
successful cursor. Completion still requires an empty ordered pending query.
A single operation exceeding the remaining lease fails closed and must recover
on another invocation; monitor slow operations, never revive an expired lease.

Push claims are capped transactionally at eight attempts, including interrupted
`sending` claims. An expired seventh claim can acquire attempt eight. An expired
eighth claim becomes `dead_letter` with reason `attempt_limit` without sending.
The current owner/status/attempt count is rechecked before each send. Preserve an
interrupted final claim and its journals for human reconciliation: FCM may already
have accepted it. FCM acceptance and Firestore acknowledgment are not atomic;
exactly-once push delivery cannot be guaranteed. Never automatically reset counts.

Run `functions/test/reliability.emulator.js` and
`functions/test/progressRecovery.emulator.js` with the existing emulator suite for
rule-valid long IDs, legacy dotted delivery, poisoned batches, advancing-clock
preview/resume, repeated 2.5-second candidate budget exhaustion, within-page
takeover, numeric/missing/null retry metadata, bounded metadata recovery, APNs
shared-prefix key separation and concurrent seven/eight-attempt recovery.
Test write flags are injected only into loopback demo projects; all sends are fake.
Environment-file defaults remain disabled/dry-run.

The three historical rules failures remain unresolved. A separate policy decision
must establish which professional fields should be publicly editable; then align
fixtures with that policy. Also reconcile the review fixture with the existing
`clientName` requirement. Do not widen authorization merely to make tests pass.
Neither rules nor those fixtures are changed by this hardening.

### Retry metadata discovery and APNs collapse keys

APNs collapse keys are the 64-character lowercase SHA-256 hex digest of the
complete event ID (64 ASCII bytes), never a truncated shared prefix. Retries for
the same event retain the key. This is payload-level testing, not verified APNs
or physical-device delivery. FCM acceptance and Firestore acknowledgment remain
non-atomic; exactly-once delivery cannot be guaranteed.

The dispatcher requires dueAt to be an Admin SDK Firestore Timestamp before
calling timestamp methods. Numeric, null or missing dueAt values become retained
`dead_letter` events with reason `invalid_retry_metadata`; original metadata is
not replaced. A valid future Timestamp waits; a valid due Timestamp can claim.
A finishing sender must still own the same active sending claim/attempt; it cannot
overwrite quarantine. Any acceptance journal from an already in-flight network
call remains for manual reconciliation, not automatic terminal-event replay.

Timestamp-filtered queries cannot discover every malformed value. After normal
due-event processing, recovery audits at most 100 active outboxes in document-ID
order, independently of dueAt. Its separate `_jobExpiryControl/pushMetadata`
checkpoint has target/version, owner/fence, cursor and a two-minute lease. Each
audit candidate is re-read and checkpointed transactionally; malformed active
records are quarantined in the same transaction. Busy/stale audits cannot overwrite
a replacement's progress. An empty audit page resets the cursor for another pass.
Future valid events are untouched. A backlog may require several scheduled runs;
monitor audit continuation and dead letters. Transient failures report failure
rather than successful completion, after attempting the normal due batch.

These audit/checkpoint writes require push enabled, dry-run false and the runtime
push gate; all defaults remain off. They never run in disabled/dry-run mode. The
preview metadata gate continues to govern preview expiration checkpoints; it is
not the authorization gate for explicitly enabled push recovery. No production
preview, audit or activation has been run. Candidate checkpoints and metadata
recovery add Firestore transactions/read/write costs: budget for a checkpoint per
processed candidate and up to 100 audit transactions plus claim/release per retry
invocation. Production index/IAM/cost behavior still needs approved validation.

## Flutter and platform preparation

Push is opt-in with `--dart-define=ENABLE_EXPIRY_PUSH=true`; default builds do not
initialize FCM/App Check or register devices. Native FCM auto-init defaults are
also off. When approved and enabled, App Check uses Play Integrity and Apple
App Attest with DeviceCheck fallback. Registration requires its valid attestation.
Firebase Console provider registration is not done by this code.

Android includes POST_NOTIFICATIONS, a `swiftserve_jobs` channel and its default
FCM channel metadata. iOS includes background notification modes and an
APS entitlement: Debug uses development; Profile/Release use production. macOS
plugin registration follows the resolved dependencies, but this feature is
intentionally Android/iOS only (no web VAPID/service worker implementation).

**iOS signing/capabilities cannot be validated on this Windows host.** Approve and
verify the registered bundle ID, Push Notifications capability/provisioning,
App Attest/DeviceCheck setup and APNs key in Firebase on a Mac. Adding an APS
entitlement may require provisioning-profile updates even with the Dart flag off.
Do not ship an iOS build until code signing is reviewed. Android Play Integrity,
Google Play services, Android 13+ permission and physical-device behavior also
remain manual gates.

`getInitialMessage` queues cold opens until a signed-in profile is ready;
`onMessageOpenedApp` handles warm opens. Foreground messages show an optional View
snackbar without a duplicate OS notification. Background handling never creates
another in-app record or performs expiration. Payload validation, a fresh owned
expired-job read, session checks and event dedup precede navigation to the existing
ClientRequestDetailsScreen. Sign-out during loading cancels stale navigation.
Opening in a worker session does not silently switch roles: existing owner/client
repost guards remain authoritative; switch back to Client before reposting.

## Reproducible local tests (no deployment)

Prerequisites: Node 22, npm, Java 21+, Flutter/Dart compatible with pubspec,
`functions` npm dependencies and the existing `rules-tests` npm dependencies.
Use system CA trust if the local network requires it; never disable TLS checking.
From `mobile/my_app/functions`: `npm ci`, then `npm test`.
From repository root, with Node 22 on PATH:

```
node mobile/my_app/rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-swiftserve-cleanup --only firestore --config mobile/my_app/firebase.local.json "node --test --test-concurrency=1 mobile/my_app/functions/test/progressRecovery.emulator.js mobile/my_app/functions/test/reliability.emulator.js mobile/my_app/functions/test/runtime.emulator.js swiftserve-backend/test/expiredJobCleanup.emulator.test.js"
```

Tests explicitly require a loopback Firestore emulator. Live-write values occur
only in the isolated demo fixture's injected configuration; they are not copied
to environment files or production. FCM send is a fake that records calls/fails
on demand. There is no FCM push-delivery emulator. Firestore emulator tests cover
persisted transactions and unchanged local rules; Functions unit tests cover
export loading and unauthenticated callable rejection. These do **not** validate
App Check attestation, deployed IAM/index readiness, real Scheduler/Eventarc
transport, APNs, physical devices or actual FCM delivery.

From backend: `npm test`. From mobile: `flutter analyze`, `flutter test`, or
`flutter test test/expiry_push_test.dart test/expired_job_repost_test.dart`.
The existing full Firestore/Storage rule tests require both emulators; their
fixtures use their own nonproduction test project IDs, so allow multi-project
emulation while keeping both SDK endpoints on loopback. Never run a fixture with
missing emulator host configuration against a live Firebase project.

### Notification -> original details -> repost locally

1. Start Auth, Firestore and Functions emulators using `firebase.local.json` and
   `--project demo-swiftserve-cleanup` (explicit local CLI command only; no deploy).
   Leave all function business/push flags disabled. Functions emulator does not
   simulate a real Cloud Scheduler clock or FCM delivery.
2. Launch a debug app with
   `--dart-define=LOCAL_FIREBASE_EMULATOR_HOST=10.0.2.2` for Android emulator, or
   `127.0.0.1` with appropriate USB port forwarding. This selects an explicit demo
   FirebaseOptions object and routes Auth/Firestore/Functions to local services.
   This override is Android-debug-only; Gradle disables native auto-init for this
   build so bundled production options cannot preempt the demo options. Use a
   fresh emulator install, and rebuild after changing the define. iOS emulator
   app configuration remains a separate Mac setup, not an implemented override.
   Use emulator email/password accounts, not production Google accounts. Release
   builds reject this override. Push remains off for demo projects.
3. Create a Client profile and future online job using the local app; do not
   create any worker application. Using the emulator-only fixture/Admin harness,
   set its schedule to an unambiguous past non-midnight PHT timestamp and run
   `sweep` with injected demo environment and the emulator settings gate. The
   integration test demonstrates this exact injected environment. A runnable
   fixture is `functions/test/localFlow.js`: from the mobile directory, set only
   the loopback `FIRESTORE_EMULATOR_HOST=127.0.0.1:8187`, then run
   `node functions/test/localFlow.js CLIENT_UID --demo-write` while the isolated
   demo emulator is running. Without `--demo-write` it seeds a demo job and runs
   preview only; both modes intentionally write demo fixtures/metadata. It
   requires an existing demo Client profile and never sends FCM. Never use the
   fixture environment with a production project or production credentials.
   Android native validation in this environment could not finish: required
   artifacts were absent offline and an online retry failed to initialize Java's
   trust store. Before this manual app walkthrough, resolve local Gradle trust/
   dependencies, verify the merged demo manifest disables FirebaseInitProvider,
   and confirm the default Firebase app reports `demo-swiftserve-cleanup`. Native
   app/emulator tapping was not claimed as performed by the automated tests.
4. Confirm one expired root, one `notifications/{eventId}` and one pending
   outbox with the same eventId (legacy or hashed namespace) in the emulator. The client's Notifications tab must show it;
   tap it to open the **original** expired job, not a workers-found screen.
5. Repost as the owner: editable content/locations are retained; choose a new
   future date and time. Submit and verify a **new** pending ID; original stays
   expired and unchanged; applications/assignment are not copied. Try a different
   account: it must not gain repost ownership.
6. Run push router tests for cold/warm simulated opens, duplicate suppression,
   ownership, sign-out races and network failures, plus existing repost widget
   and repository tests. Outbox tests use fake FCM acceptance. This locally tests
   the composed flow, not a real device push. Actual notification-tray tapping
   from a terminated/background app requires a separately approved device pilot.

## Future production checklist — every cloud action requires approval

1. Review the local diff/tests and token-access design; choose an owner, region,
   alert recipient, rollout population, retention policy and rollback operator.
2. Approve read-only production metadata inspection: verify swiftserve-production,
   `(default)` database, Native/Standard SDK compatibility, location, rules and
   indexes. CLI project selection does not set Admin SDK project targeting.
3. Approve Blaze billing, budget alerts (not a hard spend cap), required Functions,
   Cloud Build, Artifact Registry, Cloud Run, Scheduler, Eventarc, Pub/Sub,
   Firestore and FCM APIs. Firebase creates managed schedules on a later Functions
   deployment; no separate Render worker is needed.
4. Approve a keyless, dedicated runtime service account via ADC. Prefer custom
   roles limited to necessary Firestore entities get/list/create/update/delete
   and transactions, and `cloudmessaging.messages.create` for dispatch. Do not
   grant Owner/Editor or export a private key. Firestore IAM is broader than
   collection security rules; Admin bypasses rules. Validate exact minimum
   permissions (including transaction/query permissions) in an approved staging
   pilot; they were not tested here. Restrict settings-gate writers separately
   using operational IAM/process controls; runtime database privileges alone
   cannot express collection-level Firestore restrictions.
5. Approve App Check provider setup, Android signing identity, iOS capabilities,
   APNs credentials and device consent UX. No keys go into Git. Register a tested
   pilot build and validate token rotation/revocation and cross-account routing.
6. Approve deployment of **only** the reviewed Functions codebase and the new
   outbox index separately. Do not include security rules in this deployment.
   Start with disabled defaults; explicit expected project/default database;
   confirm runtime region/account and no emulator variable. Do not deploy the
   whole repository or accidentally activate an old Render runner. After those
   approvals only, the scoped Functions command from `mobile/my_app` is
   `firebase deploy --only functions:expired-jobs --project swiftserve-production`.
   This command is documentation for a future operator, not run during this task.
   Review the current production index diff before an approved index deployment;
   do not accept deletion of unrelated existing indexes.
7. Separately approve initialization of private settings gates and durable
   preview metadata. Keep expiration/push closed and dry-run true; assess scan
   completeness, costs, skipped legacy cases, cutoff age and transaction retries.
8. A later, explicit approval is required for expiration writes, push delivery,
   token registration, production data changes and any dry-run-to-live change.
   First enable a reviewed small pilot, inspect data/notifications and device
   delivery, then approve broader rollout. This document does not grant approval.

Billing: Blaze is required. Two Scheduler jobs are about $0.20/month before any
shared free-job allowance, using the published $0.10/job/31-day price checked during implementation; recheck
pricing before approval. Scheduled invocations alone are about
10,080/month (30 days), plus event/retry/callable invocations, compute, build and
artifact storage, logs, and Firestore operations. FCM has no per-message charge.
Firestore costs scale with pending population, eligibility/history reads, query
minimum charges, transaction retries, lease/gate reads and journals; dry-run costs
are not zero. Eligibility/history reads, repeated gate/lease checks, the scan read and the
per-candidate checkpoint transaction all contribute. Actual billing includes
empty-query minimums, transaction retries and any index-entry charges. Budget using measured pilot counts and current location/
edition prices. Neither the bill nor production index/IAM operation was verified.

## Existing unrelated rule-suite failures

The full unchanged Firestore/Storage suite currently has three failing tests:
`client-review.rules.test.js:120` omits `clientName` required by the reviews create
rule (`firestore.rules:720`); `public-profile.rules.test.js:58` and `:103` update
location/professional fields excluded by the public-profile update allowlist
(`firestore.rules:361`). No rule or existing rule test was edited to force these
checks to pass. Review the missing fixture field and intended profile-update
policy separately; any security rule modification needs a new explicit approval.
The focused expiration/token-access tests passing does not validate the entire
rule suite or deployed rules. Treat these failures as blockers to broad rollout.

## Monitoring and rollback

Use structured `expiry_sweep`, `expiry_push_attempt` and `push_recovery` logs;
function exceptions must alert. Monitor continuation/cutoff age, lease age,
no completed sweep across expected intervals, repeated failures, dead letters,
no-target rates, pending/sending dueAt lag, FCM acceptance errors, registration
failures, device counts and Firestore/compute/log charges. Logs contain status,
counts/event IDs, never tokens, names, addresses or raw request payloads. Set up
Cloud Monitoring log metrics/alerts only after approval; no resources exist yet.

Rollback (approved operator only): close `expirationEnabled` and `pushEnabled`
emergency gates first; disable environment cleanup/push/registration and keep
(or return to) dry-run true. Pause the managed schedules if needed, then deploy
the last reviewed disabled revision. Gates stop new candidate/send checks, but
cannot retract an in-flight FCM network call or already displayed notification.
Do not delete checkpoints, outbox/journals, notifications or expired jobs. Preserve
history for audit and safe recovery. Never automatically unexpire/repost records,
replay accepted deliveries or start Render concurrently. Review individual failed
or dead-letter events before any manual retry. Production rollback actions also
require explicit approval.


Official references checked during implementation:

- [Firebase managed schedules](https://firebase.google.com/docs/functions/schedule-functions)
- [Scheduler pricing](https://cloud.google.com/scheduler/pricing): $0.10/job per
  31 days; three shared free jobs per billing account; paused jobs still count.
- [Node runtime support](https://firebase.google.com/docs/functions/manage-functions)
- [FCM Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [FCM open/background handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
- [FCM server authentication](https://firebase.google.com/docs/cloud-messaging/send/v1-api)


## Chat and activity push extension (local only)

See [push-notifications.md](push-notifications.md) for the additional source
triggers, independent disabled/dry-run gates, permission/preferences, local tests,
new local outbox type/status/dueAt index, and physical-device prerequisites.
The shared dispatcher/retry schedule now also handles enabled activity events.
Expiration safeguards above remain unchanged. Nothing is deployed or activated.
