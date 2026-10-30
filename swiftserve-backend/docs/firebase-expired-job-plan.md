# Firebase-managed expired jobs and push notifications: migration proposal

Status: architecture implemented locally, disabled and not deployed. See the
[implementation and activation guide](firebase-expired-job-activation.md) for actual
runtime behavior, tests, safeguards and remaining approval gates. The sections
below retain the original design rationale; no production resources were accessed.

## Recommendation and the scheduling requirement

Use second-generation Cloud Functions for Firebase, Firestore and FCM for this
feature. Firebase `onSchedule` deployment creates/manages the underlying Cloud
Scheduler job and function. It satisfies the requirement to avoid a separately
managed Render server, disk or timer. It is not an architecture without Cloud
Scheduler: Google Cloud infrastructure still exists, is billed and needs IAM,
monitoring and lifecycle management through Firebase deployments.

Recommended handlers in one dedicated Firebase codebase:

1. `expireEligibleJobs`: scheduled every 30 minutes, UTC, bounded invocation.
2. `dispatchExpiredJobPush`: Firestore-created trigger on the private push outbox.
3. `retryExpiredJobPush`: scheduled every five minutes, bounded recovery of due
   retries and expired sending claims. This prevents reliance on an event retry
   window or a single successful trigger invocation for durable delivery attempts.

Firebase manages both schedules through code/deployment. Do not manually create
or independently edit the generated Scheduler jobs. A job can expire up to about
30 minutes after its requested start, plus failures/backlog and push-delivery
latency. This is not an exact-at-the-requested-second promise. Function execution
and in-app notification creation do not require an open mobile app.

Sources: [Firebase schedules](https://firebase.google.com/docs/functions/schedule-functions),
[function management](https://firebase.google.com/docs/functions/manage-functions).

## Original proposal inspection (historical; see implementation guide)

- `src/services/expiredJobCleanupService.js` already implements conservative
  eligibility, pending-only pagination, transactionally rechecked applications,
  booking/history protection, deterministic notification IDs and batch results.
- `expiredJobWorker.js`, `expiredJobCheckpoint.js` and the current script entry
  points are Render-specific: Linux flock, disk mounts, durable files and an
  indefinite timer are unsuitable for serverless invocation state.
- Existing client code recognizes expired jobs and routes in-app notifications
  to original details. Owner-only reposting uses a new pending ID, clears the
  schedule and preserves exact locations and the old document/history.
- `mobile/my_app/firebase.json` has Firestore/Storage and Flutter config, but no
  Functions source/codebase. The inspected canonical app has no firebase_messaging
  dependency, FCM device registration or push-open handlers. The canonical
  Android manifest has no explicit notification-permission declaration; iOS push
  entitlements/background configuration were not found in the inspected files.
- Production Firestore edition/native-mode compatibility, location, deployed
  rules/indexes, IAM, billing and APNs setup were not verified. Do not assume an
  emulator's edition establishes production's edition. Verify database metadata
  using separately approved access before implementing edition-specific queries.

No production Firebase configuration or security rule was changed. The local
Firebase configuration is now prepared as described in the implementation guide.

## Reuse boundary and packaging

Reuse eligibility, actual collection/field names, application/booking checks,
notification ID `jobExpired_{requestId}`, timestamp policy, batch pagination and
repost behavior. Keep the current Render runner available but disabled until a
reviewed cutover; never run both production expiration writers together.

Adapt the transaction boundary to support a fenced Firestore lease, atomic push
outbox creation, and page checkpoint commits. The existing `onProgress` callback
must not simply write an unguarded remote cursor: a stale invocation could advance
it after another invocation owns the lease. The current all-pages loop also needs
an invocation deadline and a continuation result instead of an indefinite worker.
Do not port setTimeout scheduling, process exits or per-invocation termination of
shared Firestore clients; serverless instances may serve later warm invocations.

Proposed Functions source: `mobile/my_app/functions/`, configured as a dedicated
`job-expiry` codebase in the existing mobile firebase.json. Its package should
contain only the required Firebase Admin/Functions and test dependencies, not the
Express/face-verification/canvas backend. Node runtime selection must match the
currently supported Firebase runtime and existing language syntax after checking
support at implementation time; do not assume the Render Node 24 pin is supported.

Keep one maintained copy of the shared policy/scanner inside the deployable
Functions source and make the backend module a compatibility re-export when that
extraction is approved. Firebase packaging must contain every imported file:
imports reaching outside the uploaded Functions source are not a deployment plan.
Run all existing backend regressions against that shared implementation. Do not
leave two independently maintained expiration policies or silently copy entire
backend credentials/config files into the Functions bundle.

## Durable scans, leases and duplicate execution

Proposed admin-only control document: `_jobExpiryControl/{mode}`, with independent
preview and expiration modes, containing schema version, expected project and
database, sweep ID, fixed UTC cutoff, last completed-page cursor, last completed
sweep time, lease owner, monotonically increasing fence and lease expiry.

- Claim the lease in a Firestore transaction. An unexpired lease owned by another
  invocation means this invocation records a lease-busy result and exits; it does
  not claim a completed sweep. Use unique invocation tokens and renew while
  working. Use a conservative lease duration/renewal interval and allow for clock
  skew; the exact values need fault-injection tests, not assumptions of zero skew.
- Every mutating candidate transaction reads and validates the control document's
  owner/fence/expiry as part of the transaction, in addition to the latest job and
  relevant application/history queries. A takeover changes that document and
  invalidates a stale transaction. Checkpoint updates and lease release/renewal
  must also compare owner/fence. MaxInstances/concurrency settings are additional
  limits, not a substitute for fencing.
- Use pages of 100 and bounded batches up to 1,000, then continue within the same
  invocation while time remains. The invocation has a soft deadline well before
  its configured timeout. Stop before starting work unlikely to fit; return/log
  `continuation_required`, persist progress and let the next scheduled invocation
  resume. Deadline yield is not a full sweep completion.
- Checkpoint each fully processed page in a lease-guarded transaction. This reduces
  checkpoint writes compared with one remote write per future job. A crash or
  failure mid-page replays up to one page from the last durable cursor. Existing
  job transactions/event IDs make replay safe. Never advance a page cursor past
  a failed candidate. Persistent failures alert and can delay later records.
- Store the original sweep cutoff across continuations. Query exhaustion plus
  successful final checkpoint is the only full-sweep completion. Reset the cursor
  and cutoff only then. Jobs inserted behind the cursor, or becoming eligible
  after that cutoff, are considered by the next sweep.
- Failed scans throw/report failure for platform retry/monitoring. Use bounded
  retries/backoff, release only the current owner's lease, and do not rely on
  SIGTERM being delivered before a hard timeout. Lease expiry enables recovery.
- Initially configure maxInstances=1, concurrency=1, minInstances=0. Use a finite
  function timeout (for example 540 seconds) with a shorter measured processing
  budget. A backlog unable to complete across successive intervals must alert;
  raising cadence/capacity later is a reviewed configuration change.

Validate `swiftserve-production`, resolved Admin SDK project, `(default)` database,
and the control document identity before any production-mode work. Reject an
emulator endpoint in production, and use a separate injected/emulator factory in
local tests. Firebase CLI selection does not set the Admin SDK target. Use a
function-attached dedicated service identity; choose the function region only
after database-location verification, and bind the Firestore trigger explicitly
to `(default)`; no downloaded private keys or WIF
configuration are needed inside Firebase's Google-hosted runtime.

## Atomic expiration and the push outbox

Preserve every existing eligibility check: requested FROM/start has passed,
status pending, zero applications in any status, no assigned worker/transaction
markers and no protected history/tracking/review references. Missing, inconsistent
or legacy ambiguous PHT-midnight schedules remain skipped. Expired jobs stay
stored, disappear from pending discovery and reject new applications.

For an eligible candidate, after all required reads, one Firestore transaction:

1. Changes only the job's expiration status/timestamp.
2. Creates `notifications/jobExpired_{id}` if absent, with the existing client
   recipient/role, request ID and unread state.
3. Creates `_jobExpiryPushOutbox/jobExpired_{id}` if absent, linked to that same
   event/recipient/request, with pending delivery status.

Do not send FCM inside this transaction or its retry callback. Validate a
pre-existing event/outbox identity rather than accepting a mismatched recipient
or event type. Do not overwrite its read/sent state. Page checkpoint persistence
occurs separately under the lease and can safely lag these idempotent commits.
A job with an application or booking creates neither an expiration nor an outbox.

The Firestore trigger claims an outbox delivery using a transactional sending
lease. It reads only the recipient's private registered devices, sends through the
Admin Messaging SDK outside the transaction, and records acknowledged acceptance
or per-device failures. Use event/device delivery IDs, bounded attempts/backoff,
nextAttemptAt and terminal/dead-letter status. The retry function queries due
pending deliveries and abandoned sending claims using reviewed indexes. It must
not resend successfully recorded devices or use a topic containing all clients.
Deleting or invalidating a token must compare its current version so a refresh
cannot be removed by an old response. Treat invalid payload/auth failures as
operational errors, not evidence that every recipient token is invalid.

Exactly one in-app event is enforceable. Exactly-once push delivery is **not**:
a process can stop after FCM accepts a message but before the acknowledgment is
stored. Retrying can duplicate a push; refusing that retry can lose it. Prefer
bounded at-least-once attempts, stable event IDs and client duplicate suppression.
Collapse identifiers can reduce noise but are not an exactly-once guarantee.
FCM acceptance also does not prove display or reading. A delayed/denied/missing
push must never erase the durable in-app notification.

Firestore events are at-least-once and not ordered:
[trigger guarantees](https://firebase.google.com/docs/firestore/extend-with-functions-2nd-gen).
Token cleanup guidance: [FCM token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens).

## Flutter push support and authorization

Add firebase_messaging only after compatibility resolution is reviewed. Keep the
existing in-app feed and booking/repost UI. Proposed private token documents:
`users/{uid}/push_devices/{installationId}` with token, platform and updatedAt.
Use narrow owner-only rules for token management; client access to control/outbox
collections stays denied. Existing rules do not automatically authorize a new
subcollection. This requires a reviewed rules change later, not weaker root-user
or public-profile permissions. No token belongs in public_profiles or logs.

Handle permission requests, initial token and refresh, multiple devices, logout
and account switching. Attempt to revoke the old registration before sign-out;
reconcile stale registrations and suppress wrong-account handling on the client.
Use a generic lock-screen notification without address/task details to reduce
exposure if a device registration becomes stale. Push payload includes stable
event/request IDs and recipient identity but is not an authorization grant.

On a push tap (terminated or background app), wait for Firebase initialization,
authentication and navigation readiness. Confirm the current UID matches the
recipient and read the current saved job/notification before routing. Reuse
`clientNotificationDestination` and the existing ClientRequestDetailsScreen,
including client-role context and graceful missing-record handling. Never trust
payload ownership or reopen a pending-workers screen for an expired post. Do not
create a duplicate in-app notification from the device. Deduplicate foreground,
background and cold-start event handling, and avoid a second local notification
when the OS has already displayed the notification payload.

Android 13+ notification permission/channel behavior and iOS Push Notifications,
APNs credentials, background modes and presentation options need platform setup
and physical-device tests. Upload APNs credentials only through approved secret
management/Firebase configuration, never Git. A user must have registered a
permission-enabled device before push is possible. Ordinary closed-app delivery
is supported, but offline devices, force-stop/OS restrictions and denied
permissions prevent a universal immediate-delivery guarantee. The in-app event
still appears when that client later opens the app.
Sources: [Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started),
[message reception](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

## Disabled, preview and production safeguards

Preserve disabled-by-default and dry-run true defaults; add a separate push-enable
switch defaulting off. Every sender/retry handler must check the same fail-closed
push gate before claiming/sending, including events already queued. A separate
emergency write-disable gate should be read at bounded work boundaries so rollback
does not depend solely on waiting for a code deployment or timeout.

**Firestore checkpoint tradeoff:** durable scheduled dry runs need to write only
private lease/checkpoint metadata. They must not mutate jobs, in-app events,
outbox deliveries or send FCM. This differs from Render's completely read-only
Firestore dry run, where progress was on disk. Those operational metadata writes
need explicit approval and create/update IAM permissions on their state. Do not
label this mode 'zero Firestore writes'. If zero production writes of any kind
are required, use fixture/emulator validation or a one-invocation no-write preview
without promising durable production continuation. This proposal performs neither.
Separate preview/expiration state prevents a preview cursor skipping live work.

## Billing, APIs and comparison with Render

Production Functions deployment requires Firebase **Blaze** and a linked Cloud
Billing account. The current project plan is unknown. Obtain approval before any
upgrade/API enablement. Required services include Cloud Functions, Cloud Run,
Cloud Scheduler, Cloud Build, Artifact Registry, Firestore, Eventarc/Pub/Sub for
the event trigger, and Firebase Cloud Messaging API. IAM/service-agent permissions
must be reviewed for the selected region and codebase. Firebase manages the
scheduled trigger resources; there is no separate hosting provider to operate.

Use separate least-privilege runtime identities for the scanner and sender:
Firestore reads/transaction begin and required entity create/update for control,
expiration/events/outbox; sender adds only the required FCM send permission
(`cloudmessaging.messages.create`) and relevant token/delivery access. Token
revocation may need narrowly reviewed entity-delete permission if deleting token
documents is chosen, or use version-checked invalidation updates instead. No
Owner/Editor/Firebase Admin, Auth administration, Storage or job-delete grant is
needed. IAM is not client document-level authorization; validate database-scoped
conditions and keep mobile security rules narrow. Attach identities directly,
with no service-account key download. Deployer/build identities are separate.

Illustrative monthly USD estimate, not a quote: 30 days; 1,440 expiry runs at
30 seconds each; 8,640 recovery runs at one second; 1,000 trigger runs at one
second; 1 vCPU/512 MiB, minInstances=0. Using Iowa request-based rates of
$0.000024/vCPU-second, $0.0000025/GiB-second and $0.40/million requests gives
approximately **$1.34 gross compute/requests**, potentially covered by sufficient
unused allowances. These are unmeasured durations; cold starts, extra devices,
FCM latency and retries can increase them. Function/region-specific billing must
be checked before deployment; Cloud Run Job one-minute-minimum pricing does not
apply to these event/request-based function examples.

Two schedules cost up to about **$0.20/month**, or can fit within the billing
account's shared three-schedule allowance. FCM itself has no per-message charge.
For 500 persistent pending jobs scanned each half-hour, a conservative 3 document
reads per candidate (scan, transaction, fencing control) is 2.16 million reads,
about **$0.65 gross** at illustrative Standard/Iowa $0.03/100,000 reads. At five
page checkpoints per sweep, 7,200 checkpoint writes are about **$0.0065** at
$0.09/100,000 writes, plus checkpoint reads, lease renewals, protection queries,
job/event/outbox writes, token reads and delivery bookkeeping. Expiration adds
three initial business/outbox writes per new event, not the previous two. Empty
retry queries also incur reads. Daily allowances are shared with the mobile app.

For that small illustrative workload, initial variable costs may be only a few
dollars before allowances, but this is **not a cap or a free-service promise**.
Build/artifact storage, Eventarc/PubSub, logs, network, token traffic and other app
usage are excluded from the example. Actual edition, region, free allowance and
project billing remain unverified. Set budget alerts; they are not spending caps.
Sources: [Functions Blaze requirement](https://firebase.google.com/docs/functions/get-started?gen=2nd),
[Scheduler pricing](https://cloud.google.com/scheduler/pricing),
[compute pricing](https://cloud.google.com/run/pricing),
[Firestore pricing](https://cloud.google.com/firestore/pricing),
[FCM pricing](https://firebase.google.com/pricing).

Render reuses more of the current runtime, but requires a paid always-running
worker, persistent disk, Linux lock/shutdown checks and a Pro-or-higher workspace
for managed OIDC; current all-in pricing is unverified. Its file checkpoints cost
no Firestore writes. Firebase migration is more implementation work (remote
fencing/outbox/mobile FCM), but removes the third-party host, disk and federation
operations. Both designs need the same FCM/mobile work if push is required;
Firebase's advantage should not be exaggerated by comparing push-enabled Firebase
with Render's existing in-app-only notifications. Recommend Firebase for this
user's no-separate-platform goal, conditional on Blaze/billing and migration tests.

## Proposed files and resources (not created/configured)

- New `mobile/my_app/functions/package.json` / lockfile / source entry and test
  directories for the three handlers, policy/scanner, Firestore checkpoint/lease
  adapter and outbox dispatch/recovery. Minimal dependencies only.
- Existing backend cleanup service becomes a compatibility export after an
  approved shared-policy extraction; update both test harnesses to prevent drift.
- `mobile/my_app/firebase.json`: add the explicit Functions source/codebase and
  local emulator configuration while preserving all current settings.
- `mobile/my_app/firestore.indexes.json`: reviewed due-outbox/retry query indexes.
- `mobile/my_app/firestore.rules`: deny operational collections and add narrowly
  authorized private-device registration rules; no changes made now.
- `mobile/my_app/pubspec.yaml` / lockfile and resulting platform registrants:
  compatible firebase_messaging resolution, never a blind package upgrade.
- New shared push registration/router service; app startup/auth-gate integration,
  client notification routing reuse and regression tests. Inspect sign-out paths
  before editing their cleanup behavior.
- Android manifest/channel resources and iOS entitlements/project settings/APNs
  configuration as required; preserve existing GPS permissions/navigation.
- Activation guide and this migration proposal. Keep Render files and backups
  until a verified, approved cutover; deleting them is not part of preparation.

No Functions package, dependency, schema, rule, index or platform setting has been
changed by writing this proposal. Required Firebase resources would be created
only by an explicitly approved deployment/setup, not by the current code review.

## Required tests before migration approval

1. Port existing future/applied/booked/history/legacy/timezone/self-application and
   repost regressions; >1,000 pending jobs and late-ID coverage.
2. Lease contention, renewal, expiry/takeover, stale-owner transaction abort,
   stale checkpoint/release rejection and clock-skew margin.
3. Timeout mid-page, crash after expiration commit, failed checkpoint, corrupt
   metadata, partial failures and correct non-completion/continuation logging.
4. Atomic job + in-app + outbox creation, deterministic deduplication, existing
   event read state, duplicate/out-of-order triggers and recipient mismatch.
5. Sender per-device claims, retry/backoff, invalid/rotated tokens, multiple
   devices, dead-letter/abandoned-claim recovery and FCM-accepted/ack-lost replay.
6. Disabled defaults; preview writes only metadata; no-write preview changes
   nothing; separate mode checkpoints; push gate blocks pending retries.
7. Emulator rules: no cross-user token read/write, no client operational writes,
   existing notification read/delete and owner-only repost still work.
8. Flutter permission denial, refresh/logout/account/role switching, correct UID
   and request routing, foreground duplicate suppression, background/cold start,
   missing records and fresh schedule/new ID after repost.
9. Emulator/mocked FCM tests cannot establish real APNs/Android delivery, IAM,
   Scheduler cadence or billing. Test these on an approved isolated staging
   project/devices; never seed test jobs into production.

No new Functions/FCM implementation tests ran in this architecture-only step.
Previous backend/emulator passes validate the old implementation, not this
proposed migration. Markdown/link/path review and Git diff whitespace checks are
appropriate validation for the documentation prepared here.

## Human approval gates, cutover and rollback

1. Approve Firebase over Render, the operational-metadata dry-run semantics,
   proposed private collections/token storage, push scope and variable billing.
2. Approve read-only project metadata/IAM review to establish edition, location,
   `(default)` identity, current billing and deployed compatibility. No production
   record access was performed during this proposal.
3. Local implementation, dependency resolution and tests are already within the
   authorized local-only scope. Review proposed rule/index edits separately before
   their deployment. Keep disabled defaults; do not install deployment hooks that can
   activate a codebase simply because a Git branch changes.
4. Approve Blaze/API/IAM/budget/APNs setup and a dedicated staging deployment;
   creating any such resources or uploading secrets is a separate action.
5. Pass the required tests and real-device walkthrough, including force-stop and
   denied permissions. Approve mobile release before enabling production writes.
6. Approve a production function deployment with every writer/sender disabled,
   then separately approve a durable metadata-only trial or strict no-write
   preview. Confirm complete coverage and expected candidate backlog.
7. Stop/suspend all old expiration writers before approving new write IAM and
   job-expiration activation. Do not automatically backfill push for historical
   expired posts: old events without outboxes need a separate reviewed policy.
8. Approve push activation separately, including limits on retries and historical
   queue age; starting a sender can send every eligible pending outbox item.
9. Monitor completion/continuation age, lease conflicts, scan errors, pending and
   dead-letter age, FCM acceptance/errors, delivery trends and actual charges.

Rollback first disables job mutations and push sends/retries at their gates;
allow existing invocations to settle and preserve all control/outbox records.
Pause execution through a reviewed Firebase-managed lifecycle/configuration
change if necessary; do not independently delete generated Scheduler resources.
Stopping new invocations alone does not cancel already-started transactions or
retract an accepted push. Do not reactivate Render while Firebase writers may
still be active. No automatic reopening, event deletion or repost removal.
Any document repair, historical backfill, resource deletion or return to Render
needs separate review/approval. Client in-app history remains authoritative.
