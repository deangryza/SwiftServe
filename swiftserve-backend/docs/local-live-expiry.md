# Owner-approved live expiration on this computer

Target: **swiftserve-production**, Firestore **(default)**, Standard edition.
This is a local outbound Node process, not a deployed Firebase Function, paid
host, Windows service or scheduled task. Production expiration/notification
writes were explicitly approved by the owner. No real test jobs are created.

## Cost boundary

Startup and each scan verify that the project's Cloud Billing `billingEnabled`
is exactly false. Failure to verify or a true value blocks further scanning.
Nothing links billing or upgrades a plan. Firestore's existing free quota is
shared by the app, admin dashboard and this worker; the process is not a way to
bypass it. Standard free allowances include 50,000 document reads and 20,000
document writes per day: https://firebase.google.com/docs/firestore/quotas.
Quota exhaustion can interrupt the app and worker. Scan retries, backlog size,
other users and repeated manual previews affect usage. No availability guarantee
or independent per-worker quota reservation exists.

Scans are spaced **30 minutes after the previous scan finishes**, with an initial
scan at startup. Current small pending-job counts are suitable for a limited
pilot; monitor Firestore Usage before increasing frequency or expanding use.
This is not exact-second notification delivery. Applications/discovery in the
updated mobile source use the service deadline independently of cleanup.

## Preview (default; no business or checkpoint writes)

From a fresh PowerShell terminal:

```powershell
Set-Location C:\Users\User\Documents\SwiftServe\swiftserve-backend
node --use-system-ca scripts/runLocalLiveExpiry.js --preview
```

An existing Firebase CLI operator login with access to this project is required.
No service-account private key is created or exported. The launcher rejects
emulator hosts, credential-file/config overrides, another project/database,
inherited Super Admin allowlists and global activation flags. It never loads .env.
The CLI login is privileged server-side operator access, not a browser credential
or a newly provisioned least-privilege service identity. Keep it on a trusted PC.

The preview finishes the pending scan, reports counts/reasons, and fails if
incomplete or too large for the bounded preview. It reuses the same transactional
eligibility checks but writes neither jobs nor notifications/leases/outboxes.

## Start the approved live worker

```powershell
node --use-system-ca scripts/runLocalLiveExpiry.js --run-live --confirm-project=swiftserve-production
```

This first completes a read-only preview and then enables only
`_jobExpiryControl/localComputerSettings.expirationEnabled`. Each sweep uses
Firestore's authoritative snapshot read time, advanced with a monotonic clock,
for deadlines and leases rather than trusting the PC wall clock.

It preserves the shared `_jobExpiryControl/expiration` fenced checkpoint and
existing transaction protections, bounded scan continuation and deterministic
notification identifiers. More than 1,000 candidates require later invocations;
`continuation_required`, `busy`, and failed/interrupted scans are reported as such.
There is no claim that a partial scan finished. Restart resumes durable progress;
an interrupted claim recovers after its lease expires. Concurrent runners share
the lease, but do not intentionally start duplicate processes: they waste quota.

Only eligible pending jobs are marked expired. No application, booking/history,
private location, review, job, or existing notification is deleted or overwritten.
Any application in any status protects its original. Legacy schedule-only and
ambiguous PHT-midnight jobs remain retained. Original job details remain available
and owner-only reposting creates a new job ID with a fresh future schedule.

Each eligible transaction writes an in-app notification and the existing inert
push-outbox entry atomically. No FCM sender, token registration, chat/activity
handler or cloud scheduler is started. `_jobExpiryControl/settings` and all
cloud-function environment defaults remain untouched.

Keep the computer powered on, awake, online, and this process running. The phone
does not need to stay connected by USB for production Firestore notifications.
The worker stops doing useful work when the computer/network/process is offline;
eligible overdue jobs are processed after it resumes. The app reads the in-app
notification when online; no lock-screen push is promised.

## Stop, emergency disable and rollback

Prefer Ctrl+C in the worker terminal to drain active work. To disable future
local expiration transactionally, from a separate fresh terminal:

```powershell
node --use-system-ca scripts/runLocalLiveExpiry.js --stop-live --confirm-project=swiftserve-production
```

This changes only the local switch to false. An already running process then
fails its gate check; it never re-enables that switch automatically. A deliberate
new `--run-live` command re-enables it. Do not delete lease/checkpoint documents.
Force termination may leave a two-minute lease, but checkpoint fencing and
deterministic notifications protect recovery.

Stopping does not restore expired posts, delete notifications, or change existing
accounts. Use the app's owner-only Repost flow for a new valid schedule. Any
exceptional manual rollback of a job needs a separately reviewed record-specific
plan; never blanket-reset statuses or remove audit/history documents.

## Mobile use

Use the **regular SwiftServe production build**, not SwiftServe Expiry Demo. If
running from Flutter source, omit LOCAL_FIREBASE_EMULATOR_HOST and rebuild/restart
normally using the existing production Firebase options. Existing local backend
requirements for signup and other API features are unchanged. No Firebase native
configuration, app API URL, rules, claims, allowlist or user account is changed by
this runner. Physical production-account notification receipt must be confirmed
by the actual owner; no password or owner ID token should be shared with the agent.

## Tests

```powershell
# swiftserve-backend
node --test test/localLiveExpiry.test.js test/expiredJobCleanup.test.js
# mobile/my_app/functions
node --test test/*.test.js
```

The additional `computer-only` test in functions/test/runtime.emulator.js uses
isolated demo Firestore records to verify local/cloud switch isolation, atomic
expiration, notification ownership and emergency stop. No production test
fixtures, account promotions, cloud resources, deployment, Git staging or commit
are part of this activation.

## Activation verified November 1, 2026

The no-write preview scanned 12 pending jobs and identified 4 eligible posts.
The explicitly approved first live sweep completed and expired those 4 posts.
Read-back verified all 4 original jobs still exist with the same owner and a
matching in-app notification; all 4 outboxes remain pending at zero attempts.
The shared expiration checkpoint reports complete. Cloud Billing remained
disabled, the global cloud settings document was not created, and no cloud
expiration/push switch was enabled.

The remaining 8 posts were intentionally retained: 6 ambiguous PHT-midnight
records, 1 with application history, and 1 without a valid explicit start.
Do not manually force-expire these as a cleanup shortcut. A legacy-data policy
or migration requires separate review. Actual production-account mobile receipt
and notification taps were not performed by the agent during activation.

Validation completed: 54 shared backend policy/recovery tests, 5 local live-runner
safety tests, 16 Functions unit tests, and 1 focused Firestore emulator gate test.
The real write verification used existing eligible posts, never synthetic
production fixtures. The prior physical-device walkthrough used only the
isolated demo app and is not production receipt verification.
