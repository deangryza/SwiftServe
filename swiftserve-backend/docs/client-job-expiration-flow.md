# Client job expiration and reposting

Local implementation only; production cleanup and push activation are not enabled.

- A pending job with an explicit, unambiguous service start becomes eligible at
  `scheduleFrom <= server sweep time`. Philippine dates/times are stored as UTC
  timestamps and shown in PHT. Worker application deadlines already reject the
  exact start instant; expiration now uses the same boundary.
- Existing application documents in any status, assignment/booking markers,
  tracking, linked conversations, reports, SOS, or reviews protect transaction
  history. Such jobs do not expire through the no-applications policy.
- Cleanup atomically sets `expired` and creates a deterministic client in-app
  notification with the job title and scheduled PHT date/time. It never deletes
  the original job or its private location. Repeated execution does not duplicate
  notifications or reset their read state.
- Worker lists and Apply use the existing deadline-aware filtering/transaction
  checks, including time-based UI refresh and app-resume handling. This does not
  depend on the cleanup status update arriving first.
- The client notification opens the original request details, where the owning
  client sees Repost Job at the bottom. The form copies editable job details but
  clears date/time selections. Both form and repost transaction require a future
  schedule. Keeping the old expired schedule is rejected. Reposting creates a new
  job ID and leaves the original expired record intact.

## Important timing and activation limits

The existing Firebase scheduled function is disabled by default and configured
every 30 minutes. The mobile app and USB API port forwarding do not run it.
Even after future activation, eligibility at exactly 3 PM does not guarantee the
notification is generated or delivered at exactly 3 PM. Scheduler timing, backlog,
retries and device connectivity can delay processing. Exact-second delivery is
not promised. Per-job scheduling or a higher-frequency scheduler would need
separate architecture, cost and activation approval.

Cloud execution requires separately approved deployment, API/billing prerequisites
and deliberate feature gates; see firebase-expired-job-activation.md. None of
those actions are part of this local change. Firebase scheduled functions require
the relevant billed Firebase/Google Cloud setup; they are not a guaranteed
zero-cost hosting replacement. Existing ambiguous midnight and schedule-only legacy
records are retained by policy until explicit-time metadata/migration is approved.

## Local checks

From swiftserve-backend:

```powershell
node --test test/expiredJobCleanup.test.js
```

From mobile/my_app/functions:

```powershell
node --test test/*.test.js
```

From mobile/my_app:

```powershell
C:\flutter\bin\flutter.bat test --no-pub test/service_schedule_test.dart test/expired_job_repost_test.dart test/expiry_push_test.dart test/service_deadline_test.dart
C:\flutter\bin\flutter.bat analyze --no-pub
```

For the emulator-only notification -> details -> repost walkthrough, use the
existing dedicated `demo-swiftserve-cleanup` instructions and `functions/test/localFlow.js`
described in firebase-expired-job-activation.md. That script refuses non-loopback
Firestore hosts and targets only the demo project. Use synthetic client records,
never a live production connection. Emulator writes to its control/settings and
checkpoint documents are separate from dry-run business-data writes.
