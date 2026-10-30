# Job application deadlines — local implementation

Status: local prototype only. Nothing deployed or enabled in production.
Read alongside `firebase-expired-job-activation.md` and its approval gates.

## Availability is independent of cleanup

An application is allowed only while the latest job is `pending` and its stored
service start is strictly later than now. At equality applications close.
Flutter uses `scheduleFrom ?? schedule` as an absolute timestamp, including
Philippine midnight. Missing legacy schedules retain existing compatibility.
Malformed selected start timestamps fail closed.

`ServiceRequestRepository.apply()` reads the current job inside the transaction,
checks ownership, worker verification, status and existing application, and then
checks the clock before writing either the application or notification. Every
transaction retry repeats these checks. A stale details screen cannot bypass it.
The local Firestore rules independently compare the stored start with
`request.time`, so a slow/incorrect device clock cannot authorize late writes.
Existing authentication, ownership and notification validators still apply.
Rules are a prototype requiring human review; they have NOT been deployed.

Recent, Search and Nearby share the same availability check. A reusable deadline
builder refreshes those screens and details at the next deadline and on resume.
Existing application history remains visible in details after the deadline.

The cleanup policy is deliberately unchanged: it requires a strictly past,
explicit, consistent non-midnight start, pending status, a valid owner, no
application in any status, no assignment/booking history, no tracking record and
no linked transaction history. Ambiguous midnight/date-only posts stay intact
under that policy, even though new applications close at their stored start.
Unscheduled legacy posts remain available until a separate product policy is
approved. Cleanup marks eligible roots `expired`; it never deletes them.
The owner notification uses the existing deterministic event ID, and expiration,
notification and outbox writes remain atomic. Retries do not duplicate them.

Running Flutter or the API server does not run the scheduled cleanup. The
30-minute scheduled function and its gates remain disabled by default. Local
Functions emulators do not simulate Cloud Scheduler ticks automatically.
API_BASE_URL and `adb reverse tcp:5000 tcp:5000` do not redirect Firestore.

## Isolated local verification (PowerShell)

Use Node 22 and the project's existing installed dependencies. No credentials,
service-account keys, production project selection or deployment is needed.
If dependencies are missing, review the lockfiles before installing them.

From `mobile/my_app`, run focused Flutter tests and analysis:

```powershell
flutter test --no-pub test/self_application_test.dart test/service_deadline_test.dart test/worker_dashboard_filter_test.dart test/service_schedule_test.dart test/expired_job_repost_test.dart test/expiry_push_test.dart
flutter analyze --no-pub
```

Run the deadline/cleanup emulator suite from `mobile/my_app/rules-tests` using
the existing loopback configuration (the CLI below comes from this directory's
installed firebase-tools; it performs no deployment):

```powershell
node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-swiftserve-cleanup --config ../firebase.local.json --only firestore "node --test --test-concurrency=1 request-applications.rules.test.js ../../../swiftserve-backend/test/expiredJobCleanup.emulator.test.js ../functions/test/runtime.emulator.js ../functions/test/progressRecovery.emulator.js"
```

The rules fixtures use an isolated emulator namespace, never a live database.
Expected PERMISSION_DENIED messages from negative assertions are normal; inspect
the final test counts. The suite injects write flags only into demo test objects,
uses fake FCM senders, and never changes process-wide production configuration.
The backend suite advances its cleanup test clock after a legitimately on-time
application, testing history protection without permitting late applications.

## Manual notification → original details → repost walkthrough

1. Start only the dedicated demo emulators in a separate terminal:

   ```powershell
   # From mobile/my_app/rules-tests, with Node 22 and Java available:
   node node_modules/firebase-tools/lib/bin/firebase.js emulators:start --project demo-swiftserve-cleanup --config ../firebase.local.json --only auth,firestore,functions
   ```

2. On the USB Android phone, reverse ports 9099, 8187 and 5001 as well as 5000
   when using the existing API server. From `mobile/my_app`, run:

   ```powershell
   adb reverse tcp:9099 tcp:9099
   adb reverse tcp:8187 tcp:8187
   adb reverse tcp:5001 tcp:5001
   flutter run --dart-define=LOCAL_FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:5000
   ```

   That Firebase flag selects `demo-swiftserve-cleanup` in a debug Android build.
   Keep push disabled. The existing API server may still target production;
   do not use signup/verification/API mutations in that server for the demo.
   Use emulator Auth plus an emulator-only Client profile fixture instead.

3. With that existing demo client's UID, run the guarded fixture from
   `mobile/my_app/functions`. This creates a new demo-only job, runs one sweep
   and writes an in-app notification; it does not enable a scheduler:

   ```powershell
   $env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8187'
   node test/localFlow.js YOUR_DEMO_CLIENT_UID --demo-write
   Remove-Item Env:FIRESTORE_EMULATOR_HOST
   ```

   The script refuses a non-loopback host, uses a fixed `demo-` project, and
   passes write settings only to its emulator-bound invocation. It can process
   other eligible jobs in that dedicated demo namespace; use a disposable demo.
   Without `--demo-write` it is a preview: a fixture and operational metadata
   are still written, but jobs/notifications/outbox are not expired/created.

4. Read the printed requestId/notificationId and the emulator terminal logs.
   Verify the original root still exists with `status: expired`, the owner
   notification points to that root, and its ID occurs only once after retries.
   Open the Client notification, open original details, select Repost, choose a
   future PHT date/time and submit. Verify a NEW ID and unchanged original/history.
5. Separately create a near-future demo job. Keep Recent/Search/details open
   across its start, then background/resume. It should stop accepting new
   applications even without cleanup. An existing application should remain.

Do not use production data for these steps. Live scheduling, deployed rules,
billing/APIs/IAM and physical-device push delivery each require separate human
approval and validation. No production-ready or physical-device claim is made.

## Changed files and local verification record

This task changed exactly these files, preserving their pre-existing edits:

- `mobile/my_app/lib/shared/models/service_request.dart`
- `mobile/my_app/lib/shared/repositories/service_request_repository.dart`
- `mobile/my_app/lib/shared/widgets/service_deadline_builder.dart` (new)
- `mobile/my_app/lib/features/worker/presentation/screens/worker_home_screen.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_search_screen.dart`
- `mobile/my_app/lib/features/worker/presentation/screens/worker_job_details_screen.dart`
- `mobile/my_app/firestore.rules` (undeployed deadline prototype only)
- `mobile/my_app/rules-tests/request-applications.rules.test.js`
- `mobile/my_app/test/self_application_test.dart`
- `mobile/my_app/test/service_deadline_test.dart` (new)
- `mobile/my_app/test/worker_dashboard_filter_test.dart`
- `swiftserve-backend/test/expiredJobCleanup.emulator.test.js`
- `swiftserve-backend/docs/job-application-deadlines.md` (this new guide)

Executed on October 30, 2026, using isolated copies of the working files, the
installed Flutter/Dart toolchain, Node 22, and loopback Firestore/Storage emulators:

| Check | Actual result |
| --- | --- |
| New overdue/stale-screen and Recent regression cases against old Flutter code | Both failed as intended |
| Three deadline cases against old rules | All three failed as intended |
| Focused application/rules/cleanup emulator suite | 29 passed |
| Final Flutter analyzer, after final account-ID guard review | No issues |
| Final focused Flutter command above, including account-ID guard assertion | 67 passed |
| Broad Flutter suite (`flutter test --no-pub`) | 388 passed, 1 existing date-picker failure |
| Backend (`node --test`, without emulator hosts) | 113 passed |
| Functions (`node --test test/*.test.js`) | 7 passed |
| Broad Firestore/Storage + Functions + cleanup emulator run | 141 passed, 3 existing rules failures; 0 skipped |

The broad Flutter run preceded the final preservation of the existing empty
worker-ID guard and its added widget assertion. Analyzer and the 67 focused tests
were rerun against the final code afterward; the broad run is not represented as
a second full run of that final guard change. The broad emulator run includes
all 48 Functions/cleanup tests passing, plus 93 passing and 3 failing rules tests.
No tests were run against production or a staged snapshot.

The broad emulator command used in the isolated source snapshot was:

```text
node <installed-firebase-cli> emulators:exec --project demo-swiftserve-deadline --only firestore,storage --config emulators.json "node --test --test-concurrency=1 work/mobile/my_app/rules-tests/*.test.js work/mobile/my_app/functions/test/*.emulator.js work/swiftserve-backend/test/expiredJobCleanup.emulator.test.js"
```

That temporary config referenced copies of the established rules, with only
loopback emulator ports changed (Firestore 8307, Storage 9307, hub 4507, logging
4607). It did not modify project configuration. The executable focused command
above uses the existing `firebase.local.json` instead of requiring that snapshot.

Unresolved failures remain unchanged:

1. `rules-tests/client-review.rules.test.js`: worker-review fixture omits the
   required `clientName`. Decide the intended review schema and align its fixture;
   do not relax review identity integrity simply to make it pass.
2. `rules-tests/public-profile.rules.test.js`: public location updates exceed the
   existing update allowlist.
3. The same public-profile suite: professional updates exceed that allowlist.
   Both require an explicit decision about which public fields users may update.
4. `test/post_request_schedule_test.dart`: selecting today's day number from an
   initially future-month calendar selects the wrong month near October's end.

The initial focused run exposed the related old Nearby expectation that overdue
midnight jobs stay available; that expectation was updated to the requested
application policy. Two initial analyzer style notices were corrected. The four
unrelated failures above were not edited, and remain deployment blockers.

Baseline hashes confirmed no unrelated tracked/untracked content changed and
the Git index stayed unchanged. Branch: `main`; no merge in progress, staged
paths or unmerged paths. Existing backups, archives and production gates were
not modified. Manual Android deadline/resume checks and physical push delivery
are not claimed as verified.
