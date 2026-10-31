# Firebase expiry migration: local implementation review

Local implementation only. Production expiration, token registration and FCM
remain disabled by default. No cloud resources or production records were
accessed, created or changed. No security rule was edited or deployed. No staging,
commit, push, branch switch, backup modification or archive operation was performed.
Not production-ready; physical-device delivery is unverified.

## Files changed by this implementation (41)

The repository already contained substantial unfinished work before this task.
The list below identifies edits/additions from this task only; it is not an
instruction to stage all repository changes. Existing changes in shared files
were preserved. The unchanged existing repost implementation is reused.

| Path | Purpose |
| --- | --- |
| `mobile/my_app/README.md` | Link to the implemented migration and local setup. |
| `mobile/my_app/android/app/build.gradle.kts` | Select native Firebase initialization safely for the demo-only build. |
| `mobile/my_app/android/app/src/main/AndroidManifest.xml` | Notification permission/channel, disabled FCM auto-init and conditional native initialization. |
| `mobile/my_app/android/app/src/main/kotlin/com/example/my_app/MainActivity.kt` | Create the Android job-notification channel. |
| `mobile/my_app/firebase.json` | Register the dedicated Node 22 Functions codebase without deploying it. |
| `mobile/my_app/firebase.local.json` | Loopback-only demo Auth/Firestore/Functions configuration. |
| `mobile/my_app/firestore.indexes.json` | Prepare the private outbox status/dueAt composite index; no deployment. |
| `mobile/my_app/functions/.env.example` | Disabled configuration, private-file exclusions or isolated Node 22 dependency snapshot. |
| `mobile/my_app/functions/.gitignore` | Disabled configuration, private-file exclusions or isolated Node 22 dependency snapshot. |
| `mobile/my_app/functions/package-lock.json` | Disabled configuration, private-file exclusions or isolated Node 22 dependency snapshot. |
| `mobile/my_app/functions/package.json` | Disabled configuration, private-file exclusions or isolated Node 22 dependency snapshot. |
| `mobile/my_app/functions/src/expiredJobCleanupService.js` | Functions SDK adapter for the shared policy. |
| `mobile/my_app/functions/src/expiredJobPolicy.js` | One maintained eligibility/transaction policy with optional lease/outbox hooks. |
| `mobile/my_app/functions/src/index.js` | Managed schedules, created-outbox trigger and Auth/App Check callable exports. |
| `mobile/my_app/functions/src/runtime.js` | Firestore fenced leases/checkpoints, atomic outbox, device binding, delivery journals and retry recovery. |
| `mobile/my_app/functions/test/callable.transport.js` | Two HTTP Auth/Functions-emulator rejection checks. |
| `mobile/my_app/functions/test/localFlow.js` | Guarded loopback demo fixture for the in-app notification/repost walkthrough. |
| `mobile/my_app/functions/test/runtime.emulator.js` | Twenty persistence/concurrency/retry/token-access/demo-fixture tests. |
| `mobile/my_app/functions/test/runtime.test.js` | Six preflight, disabled-mode, lease and callable boundary unit tests. |
| `mobile/my_app/ios/Runner.xcodeproj/project.pbxproj` | Push/background capabilities and configuration-specific APS entitlements. |
| `mobile/my_app/ios/Runner/Info.plist` | Background modes and disabled FCM auto-initialization. |
| `mobile/my_app/ios/Runner/Runner.entitlements` | Prepare Apple push entitlement; signing still needs Mac review. |
| `mobile/my_app/lib/app/auth_gate.dart` | Wait for the authenticated profile before registering/routing push. |
| `mobile/my_app/lib/app/swiftserve_app.dart` | Shared navigator key for notification opens. |
| `mobile/my_app/lib/features/auth/presentation/screens/google_profile_setup_screen.dart` | Bounded device revocation before sign-out. |
| `mobile/my_app/lib/features/auth/presentation/screens/profile_completion_screen.dart` | Bounded device revocation before sign-out. |
| `mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart` | Revoke device before the existing default sign-out path. |
| `mobile/my_app/lib/main.dart` | Guarded Firebase bootstrap and optional push setup. |
| `mobile/my_app/lib/shared/screens/swiftserve_settings_screen.dart` | Revoke device before settings sign-out. |
| `mobile/my_app/lib/shared/services/expiry_push_router.dart` | Session-aware queue, validation, ownership checks and open deduplication. |
| `mobile/my_app/lib/shared/services/expiry_push_service.dart` | Optional FCM/App Check, permissions, token refresh/revocation, background/foreground/cold opens. |
| `mobile/my_app/lib/shared/services/firebase_bootstrap.dart` | Explicit debug-only Android demo emulator selection. |
| `mobile/my_app/macos/Flutter/GeneratedPluginRegistrant.swift` | Generated registration consistent with the resolved Firebase packages. |
| `mobile/my_app/pubspec.lock` | Resolve those packages; firebase_core patch 4.15.0 -> 4.15.2. |
| `mobile/my_app/pubspec.yaml` | Add compatible messaging, callable Functions and App Check dependencies. |
| `mobile/my_app/test/expiry_push_test.dart` | Eight routing/ownership/session/error/disabled-default tests. |
| `swiftserve-backend/docs/expired-job-cleanup.md` | Cross-link the implemented Firebase alternative; preserve Render guide. |
| `swiftserve-backend/docs/firebase-expired-job-activation.md` | Setup, gates, billing, local flow, monitoring, approval and rollback guide. |
| `swiftserve-backend/docs/firebase-expired-job-plan.md` | Mark proposal as historical with current implementation cross-link. |
| `swiftserve-backend/docs/firebase-expired-job-review.md` | This implementation inventory and validation report. |
| `swiftserve-backend/src/services/expiredJobCleanupService.js` | Compatibility adapter to the single shared policy with backend SDK types. |

## Validation results

Flutter 3.38.3 / Dart 3.10.1; Functions validation uses Node 22.23.4.
Final Functions persistence rerun after sanitized error-code journaling: all 28
passed again, with zero failures or skips. No real FCM send was performed.

| Check | Actual result |
| --- | --- |
| Full backend suite, Node 24.18.0 | 113 passed, 0 failed |
| Functions unit suite, Node 22.23.4 | 6 passed, 0 failed |
| Firestore expiry/Functions persistence tests, Node 22 | 28 passed, 0 failed (20 new Functions + 8 existing cleanup) |
| Local Auth/Functions callable HTTP transport | 2 passed, 0 failed |
| Flutter analyzer | No issues found |
| Complete Flutter suite | 376 passed, 0 failed |
| Focused final push router/repost suite | 20 passed, 0 failed after the final account-change navigation guard |
| Existing complete Firestore/Storage rules suite | 93 tests: 90 passed, 3 failed; 0 skipped |
| Android manifest | Could not complete: missing offline Firebase artifacts; online retry failed with Java SSLInitializationException / problem accessing trust store. Corrected Kotlin DSL configured successfully, but manifest merge/native build not validated |
| iOS build/signing/APNs, real FCM/device receipt | Not run; Windows host/no cloud activation allowed |
| Actual Cloud Scheduler/Eventarc/IAM/index deployment | Not run; local Functions emulator ignores scheduled triggers without Pub/Sub and does not simulate cron delivery |

The three existing rule-suite failures are unchanged by this task:

- `mobile/my_app/rules-tests/client-review.rules.test.js:120`: positive review
  fixture omits `clientName`, required by `mobile/my_app/firestore.rules:720`.
- `mobile/my_app/rules-tests/public-profile.rules.test.js:58`: updating `location`
  exceeds `mobile/my_app/firestore.rules:361`'s update allowlist.
- `mobile/my_app/rules-tests/public-profile.rules.test.js:103`: professional-field
  updates exceed that same existing allowlist.

Do not call the complete rules suite green. Fix the missing fixture field and
review intended public-profile authorization separately, without weakening rules.
Rule changes remain outside this task's permission. Early iteration failures
included lint/import issues and an overly strict legacy fixture check; these were
corrected before the passing focused/backend runs. An initial sandbox-only Node
spawn denial was resolved by rerunning authorized tests with subprocess permission.
Node certificate trust used system roots; TLS validation was never disabled.

## Dependency and feature boundary

Functions package lock resolves firebase-admin 14.5.0 and firebase-functions 7.4.0
under Node 22. Flutter resolves firebase_messaging 16.7.1, cloud_functions 6.5.1 and
firebase_app_check 0.4.9, plus firebase_core 4.15.2. Existing package constraints
were retained; no major Firebase family upgrade was introduced. macOS generated
plugin registration matches the resolution. The new iOS pods require 15.0 and the
existing project/Podfile already target 15.5; no deployment-target change was made.

This feature also relies on **existing, preserved uncommitted work** in the job
model/repository, client notifications/details/post form and expired-job repost
and schedule tests. The 41-file inventory is this task's edit set, not a complete
independent staging recipe. Review those existing dependencies before any commit
or rollout. The full Git snapshot below includes other contributors' work and
must not be staged wholesale on the strength of this report.

## Remaining risks and required approvals

- Review/resolve the three existing rule-suite mismatches before broad rollout.
- Production project/database edition/location, deployed default-deny rules,
  indexes, API status, billing, least-privilege ADC identity and service-agent IAM
  are unverified. They require separately approved inspection/configuration.
- App Check attestation/provider enrollment, Android native build, Play services
  and permissions, iOS APS/profile/capabilities/APNs need platform/device review.
- A send acknowledged by FCM but not journaled before a crash can be resent.
  Stable IDs/collapse tags and route dedup reduce repeats; exactly-once display is
  not guaranteed, nor does FCM acceptance establish receipt/read.
- Token-owner mappings, device slots, outbox/delivery journals need an approved
  retention policy; no automatic TTL cleanup was activated. Token registration
  remains bounded to 20 devices/account, not a substitute for production abuse
  monitoring/rate policy. Lock-screen text is generic, and account switches fence
  both navigation and token targeting; queued/in-flight messages cannot be recalled.
- Large pending populations require multiple invocations. Checkpoint continuation
  and scheduled retries retain all work, but cutoff age and scan duration must be
  monitored; there is no exact-time notification SLA.
- Durable dry run writes operational Firestore checkpoint/lease metadata only
  after a separate explicit metadata gate. It is not zero-write and is billable.
- Two managed Scheduler jobs are approximately $0.20/31 days before shared free
  allowance, plus Functions/build/artifact/logging/Firestore usage. Blaze and APIs
  require approval; actual billing was not measured. No Render worker is needed.

Human approval is still required for all cloud/deployment/API/IAM/billing/App Check/
APNs/index changes, any production inspection or preview metadata writes, any
production expiration or push activation, and staging/committing/pushing. The
activation guide contains the step-by-step pilot, monitoring and rollback plan.

## Local complete-flow test

See `firebase-expired-job-activation.md` for the demo Android/bootstrap setup.
Run the loopback demo fixture `node functions/test/localFlow.js CLIENT_UID
--demo-write` with an existing demo Client profile and emulator host configured.
It creates an isolated expired root + deterministic notification/outbox without
sending FCM. Open Notifications -> original expired job -> Repost, choose a fresh
future schedule and confirm a new pending job ID while the original stays expired.
The 28 emulator tests cover the durable server side; the Flutter router/repost tests
cover simulated notification opens and owner-only fresh-ID reposting. This composed
local verification is not a physical-device push-delivery test. A manually driven
phone/emulator notification-tray walkthrough has not been claimed as performed.

## Git state at report generation

Branch: main. Staged paths: 0. Unstaged tracked paths: 46.
Untracked paths: 46. Unmerged paths: 0. No active merge or index lock.
Archive status paths: 0, as at initial inspection; archive was untouched.
Existing backups and Linux plugin links/CMake/.metadata were not edited.
Functions node_modules are ignored; only the example environment file is in
the proposed new configuration. No secrets or backups were staged.

```text
 M mobile/my_app/README.md
 M mobile/my_app/android/app/build.gradle.kts
 M mobile/my_app/android/app/src/main/AndroidManifest.xml
 M mobile/my_app/android/app/src/main/kotlin/com/example/my_app/MainActivity.kt
 M mobile/my_app/firebase.json
 M mobile/my_app/firestore.indexes.json
 M mobile/my_app/ios/Runner.xcodeproj/project.pbxproj
 M mobile/my_app/ios/Runner/Info.plist
 M mobile/my_app/lib/app/auth_gate.dart
 M mobile/my_app/lib/app/swiftserve_app.dart
 M mobile/my_app/lib/features/auth/presentation/screens/google_profile_setup_screen.dart
 M mobile/my_app/lib/features/auth/presentation/screens/profile_completion_screen.dart
 M mobile/my_app/lib/features/client/presentation/screens/client_booking_flow.dart
 M mobile/my_app/lib/features/client/presentation/screens/client_notifications_screen.dart
 M mobile/my_app/lib/features/client/presentation/screens/client_profile_screen.dart
 M mobile/my_app/lib/features/client/presentation/screens/client_request_details_screen.dart
 M mobile/my_app/lib/features/client/presentation/screens/client_sections.dart
 M mobile/my_app/lib/features/client/presentation/screens/post_request_screen.dart
 M mobile/my_app/lib/features/client/presentation/widgets/errand_tracking_map.dart
 M mobile/my_app/lib/features/worker/presentation/screens/worker_home_screen.dart
 M mobile/my_app/lib/features/worker/presentation/screens/worker_job_details_screen.dart
 M mobile/my_app/lib/features/worker/presentation/screens/worker_search_screen.dart
 M mobile/my_app/lib/features/worker/presentation/screens/worker_verification_screen.dart
 M mobile/my_app/lib/main.dart
 M mobile/my_app/lib/shared/models/service_request.dart
 M mobile/my_app/lib/shared/repositories/service_request_repository.dart
 M mobile/my_app/lib/shared/screens/public_profile_screen.dart
 M mobile/my_app/lib/shared/screens/reviews_screen.dart
 M mobile/my_app/lib/shared/screens/swiftserve_settings_screen.dart
 M mobile/my_app/lib/shared/services/device_location_service.dart
 M mobile/my_app/lib/shared/utils/job_location_utils.dart
 M mobile/my_app/lib/shared/utils/role_context.dart
 M mobile/my_app/lib/shared/widgets/booking_details_cards.dart
 M mobile/my_app/lib/shared/widgets/job_location_picker.dart
 M mobile/my_app/macos/Flutter/GeneratedPluginRegistrant.swift
 M mobile/my_app/pubspec.lock
 M mobile/my_app/pubspec.yaml
 M mobile/my_app/test/job_location_picker_test.dart
 M mobile/my_app/test/merged_worker_workflow_test.dart
 M mobile/my_app/test/post_request_validation_test.dart
 M mobile/my_app/test/self_application_test.dart
 M mobile/my_app/test/service_request_location_test.dart
 M mobile/my_app/test/worker_dashboard_filter_test.dart
 M swiftserve-backend/.env.example
 M swiftserve-backend/package.json
 M swiftserve-backend/server.js
?? mobile/my_app/firebase.local.json
?? mobile/my_app/functions/.env.example
?? mobile/my_app/functions/.gitignore
?? mobile/my_app/functions/package-lock.json
?? mobile/my_app/functions/package.json
?? mobile/my_app/functions/src/expiredJobCleanupService.js
?? mobile/my_app/functions/src/expiredJobPolicy.js
?? mobile/my_app/functions/src/index.js
?? mobile/my_app/functions/src/runtime.js
?? mobile/my_app/functions/test/callable.transport.js
?? mobile/my_app/functions/test/localFlow.js
?? mobile/my_app/functions/test/runtime.emulator.js
?? mobile/my_app/functions/test/runtime.test.js
?? mobile/my_app/ios/Runner/Runner.entitlements
?? mobile/my_app/lib/features/worker/presentation/widgets/worker_nearby_location_panel.dart
?? mobile/my_app/lib/shared/models/account_review.dart
?? mobile/my_app/lib/shared/repositories/account_review_repository.dart
?? mobile/my_app/lib/shared/services/expiry_push_router.dart
?? mobile/my_app/lib/shared/services/expiry_push_service.dart
?? mobile/my_app/lib/shared/services/firebase_bootstrap.dart
?? mobile/my_app/lib/shared/services/nearby_location_controller.dart
?? mobile/my_app/lib/shared/utils/errand_location_validation.dart
?? mobile/my_app/lib/shared/utils/service_schedule.dart
?? mobile/my_app/lib/shared/widgets/account_rating_summary.dart
?? mobile/my_app/lib/shared/widgets/chat_message_timeline.dart
?? mobile/my_app/rules-tests/account-reviews.rules.test.js
?? mobile/my_app/test/account_reviews_test.dart
?? mobile/my_app/test/chat_message_timeline_test.dart
?? mobile/my_app/test/device_location_permission_test.dart
?? mobile/my_app/test/errand_location_validation_test.dart
?? mobile/my_app/test/expired_job_repost_test.dart
?? mobile/my_app/test/expiry_push_test.dart
?? mobile/my_app/test/nearby_location_test.dart
?? mobile/my_app/test/post_request_schedule_test.dart
?? mobile/my_app/test/service_schedule_test.dart
?? swiftserve-backend/docs/expired-job-cleanup.md
?? swiftserve-backend/docs/firebase-expired-job-activation.md
?? swiftserve-backend/docs/firebase-expired-job-plan.md
?? swiftserve-backend/docs/firebase-expired-job-review.md
?? swiftserve-backend/scripts/expiredJobCleanupWorker.js
?? swiftserve-backend/scripts/runExpiredJobCleanup.js
?? swiftserve-backend/src/services/expiredJobCheckpoint.js
?? swiftserve-backend/src/services/expiredJobCleanupService.js
?? swiftserve-backend/src/services/expiredJobWorker.js
?? swiftserve-backend/test/expiredJobCleanup.emulator.test.js
?? swiftserve-backend/test/expiredJobCleanup.test.js
```


## Reliability hardening follow-up - 2026-10-30 (Asia/Manila)

Local implementation/testing only, not deployed or approved for deployment. No
rules, rule fixtures, production configuration, environment defaults, original
backups, archive, .metadata, Linux files or Git staging were changed.

Four confirmed defects were fixed:

1. Bounded deterministic event IDs: retain ordinary legacy IDs; other valid job
   IDs use a separate SHA-256 namespace. Preserve exact requestId in both atomic
   notification/outbox records. Existing dotted legacy events remain dispatchable.
2. Invalid outboxes: validate identity inside the transaction and retain terminal
   dead letters with bounded reasons. Retry batches exclude them on later runs;
   legitimate unusual IDs are delivered, not quarantined.
3. Lease renewal: sequential 30-second candidate-boundary renewal of the fenced
   120-second lease; conservative page checkpoints; recheck gate/lease immediately
   before transaction writes. Expired owners fail closed, never revive themselves.
4. Delivery limit: enforce eight attempts at claim time and verify the current
   attempt/owner/status before sending. Interrupted attempt eight is terminal;
   attempt seven can recover once. Journals remain for manual reconciliation.

Regression evidence: seven initial new emulator tests were run against the old
implementation: six failed and the seven-attempt boundary passed. Those same
seven passed after the fix. The six failing cases covered long IDs, invalid retry
batches/legacy dotted delivery, hashed long-ID delivery, slow preview, a candidate
crossing lease expiry, and interrupted attempt eight. A further 100-valid-dotted-ID
probe passed after the fix (additional coverage, not claimed as a separately
before/after-run regression). Both new Flutter routing tests failed against the
old router and passed against the fix. An initial const-map test syntax error was
corrected before those assertion-based comparisons.

Actual follow-up results (Node 22, Flutter 3.38.3 / Dart 3.10.1):

| Check | Result |
| --- | --- |
| Backend suite | 113 passed, 0 failed |
| Functions unit suite | 7 passed, 0 failed |
| Combined emulator suites | 36 passed, 0 failed, 0 skipped: 8 reliability + 20 existing Functions + 8 cleanup |
| Flutter router/repost focused suite | 22 passed, 0 failed |
| Flutter analyzer | No issues found |
| Full Flutter suite | 377 passed, 1 failed (schedule picker test below) |
| Final formatted router/repost + schedule tests | 25 passed, 1 failed (same schedule test) |
| Untouched before-source schedule test file | 3 passed, 1 failed (same schedule test) |
| Full unchanged Firestore/Storage rules suite | 90 passed, 3 failed, 0 skipped |
| Offline package resolution in temporary snapshot | Passed; exact same lockfile, no versions changed |

The full Flutter failure is `post_request_schedule_test.dart:150`, changing FROM
to today. At this month boundary, its future initial date is in November while
it taps day 30 assuming October 30; the required past-time warning is not found.
It reproduces in before-change source, independently of these fixes. Test/form
code was left unchanged; do not call the full Flutter suite green. A separate
approval/scope decision is needed to make this date-dependent fixture deterministic.

The three rules failures remain pre-existing and unresolved, as reproduced on
committed HEAD during the prior audit: review fixture missing clientName, and two
public-profile update fixtures rejected by the existing allowlist. Decide the
intended public professional-field editing policy before modifying authorization
or fixtures. No rules/fixtures were edited in this follow-up.

Changed files in this follow-up only (preserving all earlier edits):

- mobile/my_app/functions/src/expiryIdentifiers.js (new)
- mobile/my_app/functions/src/expiredJobPolicy.js
- mobile/my_app/functions/src/runtime.js
- mobile/my_app/functions/test/reliability.emulator.js (new)
- mobile/my_app/functions/test/runtime.test.js
- mobile/my_app/lib/shared/services/expiry_push_router.dart
- mobile/my_app/test/expiry_push_test.dart
- mobile/my_app/pubspec.yaml
- mobile/my_app/pubspec.lock
- swiftserve-backend/docs/firebase-expired-job-activation.md
- swiftserve-backend/docs/firebase-expired-job-review.md

Dart crypto 3.0.7 was already resolved transitively. It is now an explicit direct
dependency for SHA-256 verification; no package version or native plugin changed.

Reproduction (Node 22 and Java 21+ on PATH; repository root unless noted):

```powershell
node --test mobile/my_app/functions/test/runtime.test.js
$cli = 'mobile/my_app/rules-tests/node_modules/firebase-tools/lib/bin/firebase.js'
node $cli emulators:exec --project demo-swiftserve-reliability --only firestore --config mobile/my_app/firebase.local.json "node --test --test-concurrency=1 mobile/my_app/functions/test/reliability.emulator.js mobile/my_app/functions/test/runtime.emulator.js swiftserve-backend/test/expiredJobCleanup.emulator.test.js"
# Backend snapshot directory: node --test --test-concurrency=1
# Mobile snapshot directory:
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub test/expiry_push_test.dart test/expired_job_repost_test.dart
flutter test --no-pub
flutter test --no-pub test/post_request_schedule_test.dart
```

The actual emulator run used an equivalent temporary configuration pointing to
unchanged local rules, loopback Firestore 8297/hub 4497/logging 4597. The full rules
run used Firestore 8298/Storage 9298/hub 4498/logging 4598. Exact logs, before-source
snapshot, working test snapshot and configs are under:
`C:\Users\User\AppData\Local\Temp\SwiftServeReliability_es4ein89`.
Flutter and backend runs used the working temporary snapshot to preserve original
ignored build outputs. FCM was always fake; write/send flags were injected only
into isolated emulator fixtures, never environment files or production.

Remaining gates: resolve the separate test contracts, review the full local diff,
complete an isolated native/demo walkthrough and obtain explicit approval before
any cloud inspection/configuration/deployment/activation. Physical-device FCM,
App Check attestation, Android native dependencies, APNs/signing, deployed indexes,
IAM, billing and real schedules remain unverified. FCM acceptance and Firestore
acknowledgment cannot be atomic; a crash can still cause a duplicate. Terminal
attempt-eight delivery may be uncertain and requires journal/manual review; never
reset/replay it automatically. No expiry/push defaults were enabled.


## Candidate progress and retry metadata follow-up - 2026-10-30 (Asia/Manila)

Local-only hardening of the four final-audit findings. This section supersedes
older descriptions of page-only checkpoints and truncated APNs collapse IDs.
Nothing was deployed or activated. No rules, rule fixtures, date-picker test,
production configuration/data, dependencies, original backups, archive, .metadata,
Linux configuration or Git staging were changed.

Resolved findings:

1. Expiration checkpoints now advance after every successfully processed candidate,
   using the existing transactional owner/fence/lease/gate checks. Cursor ordering
   and the fixed cutoff remain unchanged. Budget/shutdown interruption retains the
   last successful candidate, not the previous page. Commit-before-checkpoint
   crashes replay safely; failed candidates are not skipped. Completion still
   requires an empty pending query. Existing version-1 page cursors remain valid.
2. APNs collapse IDs are SHA-256 of the complete event ID: 64 deterministic ASCII
   hex bytes. Tested long shared-prefix events have distinct keys; retries retain
   the same key. This does not verify APNs/device delivery.
3. dueAt must be an SDK Firestore Timestamp before timestamp methods are invoked.
   Missing/null/numeric values are retained in dead-letter records with bounded
   reason invalid_retry_metadata and unchanged event identity/attempt details.
   Normal due processing runs first. A separate, bounded, fenced metadata audit
   visits up to 100 pending/sending outboxes by document ID, using the durable
   _jobExpiryControl/pushMetadata cursor. It atomically quarantines invalid metadata
   and checkpoints each candidate, finding records omitted by timestamp queries.
   Live leases return busy; expired leases resume; failures retain progress and
   report failure. Incomplete/busy audits report continuation at the top level.
   A finishing sender cannot overwrite terminal quarantine; an acceptance journal
   from an already in-flight send is preserved for manual reconciliation.
4. Activation-guide sections now consistently describe both identifier namespaces,
   candidate checkpoints/renewal, retry metadata discovery and terminal states.

Regression proof: the initial eight new tests were run against the unchanged old
runtime: seven assertion-based cases failed and the valid-Timestamp boundary
passed. The failures covered repeated budget exhaustion, within-page takeover,
APNs shared-prefix keys, numeric/missing/null dueAt, and multi-page discovery of
malformed metadata. They all passed after the fix. Three additional tests cover
live/expired concurrent audit leases, injected audit transaction failure/resume,
and quarantine during an in-flight send; these are additional coverage, not
claimed as separate before/after-run regressions.

Final actual results (Node 22; Flutter 3.38.3 / Dart 3.10.1):

| Check | Result |
| --- | --- |
| Final focused progress/recovery emulator suite | 11 passed, 0 failed, 0 skipped |
| Final combined emulator suites | 47 passed, 0 failed, 0 skipped: 11 progress + 8 prior reliability + 20 Functions + 8 backend cleanup |
| Final Functions unit suite | 7 passed, 0 failed, 0 skipped; includes disabled/dry-run no-database-touch checks |
| Backend suite | 113 passed, 0 failed, 0 skipped |
| Flutter analyzer | No issues found |
| Focused Flutter router/repost/schedule tests | 25 passed, 1 failed: unchanged date-picker month-boundary fixture |
| Full unchanged Firestore/Storage rules suite | 90 passed, 3 failed, 0 skipped: same historical failures |
| Full Flutter suite / native builds / physical-device push | Not run in this follow-up |

An intermediate emulator run was stopped to add the quarantine/finalization race
check. It is not counted as a completed validation; the final focused and full
runs above include that guard and pass. All FCM sends were fake. Test write flags
were injected only into loopback demo projects, never environment files or live
configuration. No production record was accessed.

Changed files in this follow-up only (six):

- mobile/my_app/functions/src/runtime.js
- mobile/my_app/functions/test/progressRecovery.emulator.js (new)
- mobile/my_app/functions/test/runtime.emulator.js
- mobile/my_app/functions/test/runtime.test.js
- swiftserve-backend/docs/firebase-expired-job-activation.md
- swiftserve-backend/docs/firebase-expired-job-review.md

Exact retained test artifacts/configuration:
C:\Users\User\AppData\Local\Temp\SwiftServeProgressFix_m7dg0sbt

With Node 22 and Java 21+ configured, the final emulator command was:

```powershell
$run = "$env:TEMP\SwiftServeProgressFix_m7dg0sbt"
$cli = 'C:/Users/User/Documents/SwiftServe/mobile/my_app/rules-tests/node_modules/firebase-tools/lib/bin/firebase.js'
Set-Location $run
node $cli emulators:exec --project demo-swiftserve-progress --only firestore --config final-emulators.json "node validate.js"
```

validate.js executes node --test --test-concurrency=1 on the new progress suite
first, then all four relevant emulator files. It preserves final-focused.log and
final-emulator.log. The final Firestore/hub/logging ports were 8301/4501/4601.
The activation guide also gives the repository-relative equivalent command.
Other commands executed from the temporary work snapshot:

- Functions: node --test test/runtime.test.js (functions-unit-final.log).
- Backend: node --test --test-concurrency=1 (backend.log).
- Mobile: flutter analyze --no-pub (flutter-analyze.log).
- Mobile: flutter test --no-pub test/expiry_push_test.dart test/expired_job_repost_test.dart test/post_request_schedule_test.dart (flutter-focused.log).
- Rules: emulator-wrapped node --test --test-concurrency=1 in rules-tests,
  using rules-emulators.json on Firestore 8298/Storage 9298 (rules.log).

The three rules failures and date-picker failure are deliberately unchanged.
Reconcile the review clientName fixture and decide the public-profile professional
field update policy separately; do not widen rules to obtain green tests. The
month-boundary picker fixture needs a deterministic date-selection correction in
a separate scope. Do not call either broader suite green.

Remaining risks/approval gates: candidate checkpoints and bounded metadata audits
add billable Firestore operations. Measure backlog latency/read/write costs and
validate production indexes/IAM only after explicit approval. Missing/new records
before a cursor are revisited on the next complete audit pass; sustained backlog
requires monitoring. A single operation exceeding the lease fails closed and
recovers after expiry. FCM acceptance and Firestore acknowledgment are non-atomic;
exactly-once push delivery cannot be guaranteed, and uncertain terminal deliveries
must not be blindly replayed. Android native dependencies, real App Check/APNs,
physical-device delivery, deployed rules/indexes/IAM, billing and managed schedules
remain unverified. All defaults remain disabled/dry-run. Human local review may
proceed; this is not approval for deployment or production activation.
