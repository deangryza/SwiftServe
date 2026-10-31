# Job expiration, client notification and reposting

This is an opt-in Node backend task. It is **not enabled or deployed** by adding
this code. No Firebase function, Cloud Scheduler job, rules or index is deployed.

## Firebase-managed alternative under review

The [Firebase Functions / Firestore / FCM migration proposal](firebase-expired-job-plan.md)
evaluates managed schedules, fenced Firestore checkpoints, push delivery, billing,
required tests and approval gates. The [Firebase implementation guide](firebase-expired-job-activation.md) describes
the new disabled local runtime. It is not an activated replacement. This guide continues to describe the existing Render
preparation; its runtime, disk checkpoints and all prior work remain intact.

## Eligibility and records

The dedicated worker scans pending `service_requests` in document-ID order in
pages of 100 and batches of at most 1,000. It immediately continues each partial
batch until the pending sweep is exhausted; the 30-minute interval begins only
after that sweep finishes or fails. Durable local checkpoints resume a sweep
after process restart without writing operational state to Firestore. The same
cutoff timestamp is retained for that sweep. New or newly eligible posts behind
the cursor are considered by the next sweep.

Each candidate is read again in an Admin SDK read/write transaction. Expiration
requires all of the following:

- `status` is still exactly `pending`.
- No worker ID/name, acceptance, ongoing, completion, cancellation or errand-stage
  marker is present. SwiftServe stores bookings in this same document; there is
  no separate bookings/payments/transactions collection in the inspected code.
- `scheduleFrom` is a Firestore Timestamp strictly before the run's fixed UTC
  cutoff. If present, `schedule` must agree, and `scheduleTo` must be valid and
  not precede the start. A date range expires at its requested **FROM/start** time.
- No application document exists under `service_requests/{id}/applications`,
  regardless of pending, accepted or rejected status.
- No `private/rider_location`, linked conversation, report, SOS alert or review
  exists. Inconsistent historical records are conservatively retained.

The task compares timestamp instants, not creation dates or the server timezone.
Philippine time is UTC+8. Missing/malformed start times, schedule-only legacy
records and **all PHT midnight selections** are retained. Midnight cannot be
distinguished from legacy date-only data without a schema change; explicit
midnight jobs therefore do not currently expire automatically. Old data created
under other timezone conventions cannot be reliably classified from timestamps
alone: review the dry-run log before enabling expiration.

The transaction preserves the root and all subcollections. It changes only
`status` to `expired` and adds `expiredAt` (server timestamp), then creates
`notifications/jobExpired_{requestId}` atomically. The event uses the existing
notification shape with `recipientId=clientId`, `recipientRole=client`,
`senderId=system`, `type=jobExpired`, `requestId`, title/body, `read=false` and
server `createdAt`. Missing owners are skipped. A pre-existing event is retained,
including its read state. The status transition and deterministic event ID make
retries/concurrent processes idempotent. Failure of either write rolls back both;
the still-pending job is retried by a later scan. Deleting the notification later
does not recreate it because the original is already expired.

The current worker Apply transaction reads the parent, then writes its application
and notification together. If Apply commits first, expiration retains the job;
if expiration commits first, Apply retries/fails against the non-pending parent.
Current security rules independently require a pending parent for new applications.
Do not replace these transactional rechecks with scan-then-batch writes.
This relies on [Firestore serializable transactions](https://firebase.google.com/docs/firestore/transaction-data-contention).

Worker discovery queries select `pending`; the mobile model recognizes `expired`
and never decodes it as pending. Client Past bookings and expiration notifications
open the existing request details with the original ID. Missing records show the
existing graceful error state. The expired status and owner-only Repost Job action
are visible there. The existing form preloads editable details and exact private
pickup/drop-off coordinates but clears dates/time. A valid new future schedule
and explicit submission are required. The repository rechecks source ownership
and expired status in a transaction, creates a new pending ID and optional
private/location document, and leaves the original untouched. No applications,
worker assignment, conversation, notification or review is copied. No origin-link
field is added to new posts, preserving the existing create schema.

No security rules change: expiration uses the trusted backend Admin SDK. Clients
cannot manufacture expired states or system expiration events through the existing
rules. Reposts use normal authorized pending-job creation. The schema extension is
the backend-written `expired` status and optional `expiredAt` field. There is no
migration or deletion of existing data.

## Render preparation: not deployed or activated

Only local implementation and tests have run. No worker, disk, IAM identity,
federation provider or cloud resource has been created. No production documents,
credentials, IAM bindings, indexes or deployed rules were accessed by these tests.

### Runtime and startup guards

Use **one dedicated Linux background worker** with `npm run jobs:cleanup`.
The API (`npm start`) now rejects cleanup-enabled configuration: API replicas must
not bypass the dedicated worker's project checks, persistent checkpoint or lock.
All unrelated API behavior remains unchanged when cleanup is disabled.

`runExpiredJobCleanup.js` validates local environment settings and requires an
actual non-memory, non-overlay mount at `EXPIRED_JOB_CLEANUP_DISK_MOUNT`. Its state
directory must be beneath that mount, with no symlink escape. It launches the
internal Node entry point through `flock --exclusive --nonblock --no-fork`, using
`worker.lock` in that directory. The internal worker checks `/proc/self/fdinfo`
for the inherited current-process kernel write lock before initializing Firebase.
Do not run `expiredJobCleanupWorker.js` directly. Missing `flock`, invalid mount,
lock conflict (exit 73), or a bypass attempt fails closed.

Production preflight requires `GOOGLE_CLOUD_PROJECT=swiftserve-production`, rejects
a conflicting `GCLOUD_PROJECT`, and rejects **any** `FIRESTORE_EMULATOR_HOST`
setting, including an empty string. It then checks the actual SDK's `projectId`
and `databaseId === '(default)'` before scheduling. These SDK configuration
checks do not make database RPCs or prove that the account has IAM access or the
database exists. Firebase CLI project selection does not control this target.

Disabled is the default, and an omitted dry-run setting means dry-run. An invalid
non-boolean dry-run value is rejected. A disabled command exits successfully
without opening Firebase, creating state files or spawning another process.
Keep an intentionally disabled Render service **suspended** rather than allowing
its supervisor to repeatedly restart that deliberately exiting process.

### Checkpoints, failure reporting and restart behavior

The mount stores `checkpoint-dry-run.json` separately from
`checkpoint-expiration.json`. Checkpoint identity includes version, project,
database and mode. Corrupt/mismatched files stop startup rather than being reset.
Files contain only sweep ID, cutoff, last successfully processed document ID and
last completed time, not names, addresses, credentials or job bodies.

After each successful eligibility check/transaction, write a unique temporary
file, fsync it, atomically rename it, and fsync the directory on Linux. Only then
advance the in-memory cursor. The OS lock protects this single-writer state.
The file lock coordinates only processes sharing that mounted directory; it is
not a distributed lock across separately provisioned Render services/disks. Keep
one production service. Separate accidental runners still rely on Firestore
transactions and deterministic event IDs for data safety.
The lock is released by the kernel even on SIGKILL: the lock file's mere presence
is harmless and never a reason to delete a file manually.

A crash after the Firestore commit but before checkpoint persistence replays
conservatively. The expired status and deterministic event ID prevent duplicate
notifications; notification read state is preserved. A completed sweep resets
its active cursor and records `lastCompletedAt`; restart after completion starts
a new sweep with a fresh cutoff. Disk loss requires an approved recovery/full
rescan, not silent fallback to ephemeral state. Re-scanning is idempotent but can
cost extra reads. Keep all existing backups untouched.

A transaction/read/checkpoint failure stops at the first failed document. Earlier
progress remains durable; the failed document is retried from that boundary.
A persistent failure can delay later documents, so failure/stalled-sweep alerts
are mandatory. No error, interruption, or partial 1,000-item batch is reported
as a successful full sweep. A 30-minute retry is scheduled after failure; transient
Firestore contention is also handled by the SDK's existing transaction retries.
The service stays alive after a failed sweep, so process uptime alone is not a
sufficient health signal.

### Graceful and forced shutdown

The launcher forwards SIGTERM/SIGINT to the locked Node child. Shutdown stops
future ticks and stops starting new candidates, but waits for an already-started
transaction/checkpoint before closing Firestore. The stopped event is emitted
only after drain and connection termination. Interrupted sweeps keep their
checkpoint and never emit `expired_job_sweep_complete`.

Render persistent disks restrict a service to one instance and disable
zero-downtime deployment. Render also documents that disk-backed services cannot
customize their shutdown delay. Expect its default 30-second termination window;
do not promise an in-flight transaction will always finish before forced kill.
After SIGKILL the next worker recovers the last durable cursor and rechecks any
uncheckpointed commit. Validate this on staging before activation.
Sources: [Render disks](https://render.com/docs/disks),
[Render shutdown](https://render.com/docs/deploys#graceful-shutdown).

### Exact proposed Render setup (not applied)

1. Approve the workspace/worker/disk cost and region after confirming the actual
   Firestore region. **Managed OIDC currently requires a Pro workspace or higher**;
   the earlier approximately $7 compute-only estimate was not an all-in keyless
   hosting estimate. Workspace entitlement, disk pricing and actual account
   billing remain unverified. [Render OIDC](https://render.com/docs/oidc).
2. Create a **Background Worker**, native Node runtime, repository root directory
   `swiftserve-backend`, one instance, auto-deploy OFF until reviewed.
3. Pin Node `24.18.0` (the locally tested version) after verifying availability on
   the host. Build command: `npm ci && npm run check && command -v flock`.
   Start command: `npm run jobs:cleanup`. No HTTP port, queue, Redis, face models
   or new application dependency is needed. Existing native dependencies still
   need a successful Linux build; that has not been verified here.
4. Attach a persistent disk at `/var/data`, using an approved paid size. The
   launcher creates `/var/data/expiry` at runtime; disks are unavailable during
   build/predeploy. Never put state files under the Git checkout or a secret mount.
5. Configure the following worker settings. All deployment remains approval-gated:

| Variable | Required value / source |
|---|---|
| `GOOGLE_CLOUD_PROJECT` | `swiftserve-production` |
| `EXPIRED_JOB_CLEANUP_DISK_MOUNT` | `/var/data` |
| `EXPIRED_JOB_CLEANUP_STATE_DIR` | `/var/data/expiry` |
| `EXPIRED_JOB_CLEANUP_ENABLED` | `false` until an approved read-only trial |
| `EXPIRED_JOB_CLEANUP_DRY_RUN` | `true`; keep this safeguard |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Actual Google provider resource name |
| `GCP_SERVICE_ACCOUNT_EMAIL` | Dedicated cleanup account email |
| `GOOGLE_APPLICATION_CREDENTIALS` | Render-generated external-account file; do not set manually |
| `FIRESTORE_EMULATOR_HOST` | Absent, not even an empty value |
| `GCLOUD_PROJECT` | Absent, or the same expected project |

Use host-injected environment settings; dotenv reads the working-directory `.env`
without normally overriding those settings. Do not ship a development `.env`,
service-account private key, token file or existing backup to this service.
An isolated preview/staging **host** must not use this production entry point
against a different Firebase project; use local/injected/emulator fixtures for
code validation. This production entry point intentionally has no project bypass.

### Keyless identity and least-privilege IAM

After approval, enable the required Google IAM, STS and service-account-credentials
APIs, create an OIDC federation provider for `https://oidc.render.com/WORKSPACE_ID`,
map `google.subject` to `assertion.sub`, and restrict its condition/binding to the
**exact production service subject**. Do not trust every workspace service.
Create a dedicated service account; grant that exact federated principal
`roles/iam.workloadIdentityUser` on it. Configure Render's provider and account
variables above. Render generates the ADC file and rotates short-lived tokens.
No downloaded private key is required. Validate renewal over multiple intervals
with the installed Firebase Admin SDK; live federation has not been tested here.
Follow [Render's GCP setup](https://render.com/docs/oidc#setup).

For the read-only trial, use a custom role with `datastore.databases.get`
(transaction begin/rollback), `datastore.entities.get` and
`datastore.entities.list`. Add metadata permissions only if required by an
approved preflight. The runtime configuration check itself does not query metadata.
Only a separately approved write activation needs `datastore.entities.create`
and `datastore.entities.update`; no delete, export, Firebase Auth administration,
Storage, Owner, Editor or Firebase Admin grant is needed. Validate database-scoped
IAM conditions where supported. Admin IAM does not enforce client document rules.
Checkpoints are local, so dry-run IAM needs **no Firestore write permission**.
See [Firestore IAM](https://firebase.google.com/docs/firestore/security/iam).

### Deployment and dry-run approval checklist

1. Approve hosting/Pro entitlement/disk budget, service identity and region.
2. Review these local changes and tests. Approve the Linux build/deployment and
   cloud identity/resources separately; no such action has been performed.
3. On an approved staging host, test the actual filesystem mount/fsync behavior,
   Linux flock ownership check and signal forwarding. Use a synthetic database
   or injected fixtures, never seed representative jobs into production.
4. Verify the real target project/default database, IAM, indexes and deployed
   client rules using approved access. These are not established by local tests.
5. Release the mobile app with expired/repost support before any write activation.
6. With explicit approval for production reads, enable only a **read-only trial**
   while keeping dry-run true and the identity read-only. Review a complete sweep,
   skips, oldest checkpoint cutoff, candidate IDs and zero errors. Dry runs create
   checkpoint files on disk but do not modify Firestore records.
7. Validate restart mid-sweep, forced kill during a transaction, more than 1,000
   pending records in fixtures, lock conflict and token refresh across intervals.
   Test notification/details/repost on staging devices. No production mutations
   are needed for these fixture tests.
8. Review backlog, recovery arrangements, Firestore reads and process metrics.
   Obtain **separate explicit approval** for write IAM and expiration activation.
   This guide does not configure or perform that activation.

### Logging and health checks

Logs use structured objects containing event codes, random request/sweep IDs,
cursor, counts and mode. Do not log raw SDK errors, tokens, credentials, job names
or addresses. Keep service logs access-controlled.

- `expired_job_preflight_passed`: expected project/database and actual mode.
- `expired_job_sweep_started`: sweep ID/cutoff and whether resumed.
- `expired_job_sweep_progress`: a bounded batch finished; not a completed sweep.
- `expired_job_sweep_complete`: exhausted the sweep with zero failures and saved
  completion state. Counts cover this process's portion when resuming, not all
  historical work before the restart.
- `expired_job_sweep_failed`, `expired_job_scheduler_error`, or batch-failed:
  alert; do not count as success. A successful batch is not sufficient either.
- `expired_job_sweep_interrupted`: resumable shutdown, not completion.
- `expired_job_worker_already_running`: lock conflict, exit 73; investigate.
- `expired_job_worker_stopped`: active work drained and Firestore closed.

A background worker has no HTTP health endpoint. Use process events plus an
approved log monitor/alert integration. Alarm on any scan/preflight/checkpoint
error, repeated restarts/lock conflicts, or no new full-sweep completion within
60 minutes (initial threshold; tune to a measured large sweep). An old active
cutoff or unchanged cursor with failures means stalled coverage, even if Node is
alive. Monitor disk capacity, reads, retries and all-in workspace/hosting costs.
A monitor integrated with production is a separate resource/configuration approval.

### Rollback and recovery

Suspend the dedicated service and keep cleanup disabled/dry-run true on all future
starts. Disable it in every API instance. Allow draining, but assume a forced
termination can interrupt work; inspect active processes and logs. Do not delete
`worker.lock`, checkpoints, backups, notifications or reposts as a shortcut.
Disable plus suspend avoids a supervisor restart loop for the disabled command.

Disabling does not undo committed expirations or retract their notifications.
Keep the mobile expired UI available. Inspect affected IDs and subsequent client
reposts before any separately approved, per-document transactional repair.
For corrupt/mismatched/lost checkpoints, stop the worker, retain the old files,
review the failure, and approve restoring a known checkpoint or a full rescan.
Do not silently clear state. Old valid cursors can be replayed safely, but replay
can create additional Firestore reads. Do not downgrade to a runner that ignores
this checkpoint schema or bypasses preflight/locking.

## Local validation and remaining assumptions

Policy and worker tests use an in-memory database and temporary local files.
Production preflight, mount/lock and signal behavior are dependency-injected in
Windows unit tests: **actual Linux flock, Render mount persistence, OIDC renewal,
Render supervision and the forced-kill boundary remain unverified on the host**.
Firestore emulator tests use only `demo-swiftserve-cleanup` on loopback, with the
real Admin/web SDK transactions and existing client rules. They test concurrent
expiration/Apply and notification deduplication, not production scheduling.

Final local validation on Node 24.18.0: **113 backend tests passed**, including
53 cleanup/policy/worker tests; **8 isolated Firestore emulator integration tests
passed**; `npm run check` and `git diff --check` passed. No test failed. Flutter
analysis/tests were not rerun because no Flutter file changed during this task.
No production credential, project RPC or deployment was used for validation.

From `swiftserve-backend`:

```powershell
node --test test/expiredJobCleanup.test.js
npm run check
```

The existing emulator regression file is
`test/expiredJobCleanup.emulator.test.js`; run it with the local Firebase CLI and
Java 21+, explicitly targeting the isolated demo project. No Firebase deploy is
needed. Missing emulator setup skips those cases; do not call that validation.

## Files changed for Render hardening

- `src/services/expiredJobCleanupService.js`: safe batch boundary, failure status,
  cooperative interruption and scheduler drain.
- `src/services/expiredJobCheckpoint.js`: identity-checked atomic durable file.
- `src/services/expiredJobWorker.js`: production preflight, lock verification,
  complete/resumable sweep controller and orderly database termination.
- `scripts/runExpiredJobCleanup.js`: Linux persistent-disk/flock launcher.
- `scripts/expiredJobCleanupWorker.js`: internal locked process/signal handler.
- `server.js`: API instances reject cleanup-enabled startup.
- `test/expiredJobCleanup.test.js`: policy and new worker failure/recovery tests.
- `package.json`: syntax checks include all cleanup modules; no new dependency.
- `.env.example`: disabled/read-only template plus expected project/disk paths.
- This guide: exact Render setup, verified local behavior and approval gates.

Existing mobile/repost changes, safety backups, untracked unrelated work and
Firestore rules are preserved. No staging, commit, push or deployment was done.
