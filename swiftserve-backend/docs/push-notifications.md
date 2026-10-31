# Device push notifications: local implementation, not activated

No cloud resources, rules, production settings or records were changed. Physical
Android/iOS delivery is unverified. No new package is needed.

## Implementation

- `queueChatPush` observes new conversation messages. It reloads the message and
  two distinct conversation members, checks both block directions and queues only
  the recipient, never the sender. Chat storage and the existing shared chat screen
  are unchanged.
- `queueActivityPush` bridges existing in-app notifications. It reloads ownership
  and the job/application relationship. Admin-authored verification events are
  account updates. Expiration events are excluded because their existing atomic
  outbox already handles them.
- `recordApplicationRejection` and `recordBookingUpdate` fill only existing gaps:
  rejected applications and ongoing/completed/cancelled bookings. Accepted and
  application-created notifications already exist and are reused. These new
  in-app records have a separate gate; push preferences never suppress in-app data.
  Obsolete/out-of-order transitions are skipped after checking current state.
  Private `_jobExpiryControl/activityEvents/records/{eventId}` journals commit
  with these notifications so retries cannot resurrect a user-deleted record.
  These small journals add reads/writes and require a future retention policy;
  none are deleted automatically.
- Activity outboxes use `activity.v1.<SHA-256(JSON-encoded namespace/source/recipient)>`.
  Structured JSON prevents ambiguous concatenation. Original source IDs remain
  fields. Expiration IDs/compatibility, checkpoints, leases and reposting remain
  unchanged.
- The existing private outbox, claimed delivery, eight-attempt ceiling, per-token
  accepted journals, invalid-token pruning, dead letters and five-minute retries
  are reused. Due queries select enabled event types so paused expiration events
  cannot starve activity retries. A local `type,status,dueAt` composite index was
  added; emulator success does not prove production index availability.
- FCM acceptance and Firestore acknowledgement are not atomic. An interrupted
  send can still duplicate an alert; exactly-once delivery is not guaranteed.
  Full-event APNs collapse hashes and Android tags are retained.
- FCM never includes raw message text, addresses, job titles, verification reasons
  or arbitrary notification bodies. Chat shows the public sender name and
  **“Sent you a message.”** Actual message-text previews are deliberately omitted
  because they may contain private data. Other alerts use generic text.
- Taps reload an owned notification or participant conversation before opening
  the existing chat/job/booking/verification/review screen. Cold opens wait for
  profile readiness; account changes fence asynchronous work. No automatic role
  switch occurs. Foreground uses a deduplicated SnackBar with View; background
  and terminated delivery use the OS payload without a second local notification.

## Consent and tokens

`ENABLE_PUSH_NOTIFICATIONS` defaults off; the old `ENABLE_EXPIRY_PUSH` flag remains
compatible. Demo Firebase builds explicitly skip FCM. In an enabled mobile build,
profile completion presents an explanation once per account/install. Not now
never requests native permission. Continue invokes native permission; denial
never blocks using the app. Auto-init remains off until consent.

Settings → Notifications controls all push, messages and job/account updates for
this account **on this device**, plus a link to system notification settings.
Other devices retain independent choices. OS permission is rechecked on resume
and registration. In-app notifications remain available regardless of push choices.

`registerPushDevice` still requires Auth and App Check. It takes UID exclusively
from auth and stores tokens/preferences in private
`users/{uid}/push_devices/{installationId}`. `_pushTokenOwners/{tokenHash}` prevents
old accounts targeting a newly bound token. Token refresh replaces the installation
token and removes its obsolete ownership binding. Invalid tokens and matching
bindings are removed. Registration writes are serialized/session-fenced. Sign-out
revokes the device and invalidates its token, with an offline invalidation fallback.
The existing rules deny client access to tokens, bindings, outboxes and controls;
no rule change is needed.

Every send rechecks ownership and enabled/category preferences. Already accepted
or in-flight FCM messages cannot be recalled. Offline preference changes cannot
instantly reach the server; token invalidation and OS permission remain fallbacks.
Registration errors do not block login and retry on resume/token refresh. A UI
preference is not proof of successful registration. Existing limit: 20 installations
per account; abandoned devices reaching that cap need approved support cleanup.

## Defaults and activation gates

No live configuration was edited; `.env.example` remains disabled/dry.

| Purpose | Environment defaults | Private settings gate |
| --- | --- | --- |
| Activity outbox and delivery | ACTIVITY_PUSH_ENABLED=false; ACTIVITY_PUSH_DRY_RUN=true | activityPushEnabled absent/false |
| New in-app rejection/booking records | ACTIVITY_EVENTS_ENABLED=false | activityEventsEnabled absent/false |
| Device registration/preferences | EXPIRY_TOKEN_REGISTRATION_ENABLED=false | registrationEnabled absent/false |
| Expiration and its pushes | Existing disabled/dry-run gates unchanged | Existing expiration/preview/push gates unchanged |

Activity delivery has its **own** dry-run gate, independent of expiration dry-run.
Its dry run creates no outbox/notification/checkpoint/lease and sends nothing.
Token registration and new in-app activity records are separate gated writes.
The shared retry-metadata audit can checkpoint/quarantine malformed shared events
when either push pipeline is approved/enabled. Valid paused events are not sent.
No old chat/notification backfill runs when activated; only new source events
produce outboxes. Source deletions, blocks and ownership changes fail closed.

## Local reproduction

Use an isolated temporary copy with installed dependencies, Node 22 and Java 21
(Android Studio JBR). Logs stay in that copy. Never import production data/keys.

```powershell
node --test functions/test/*.test.js
node rules-tests/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec `
  --config firebase.local.json --project demo-swiftserve-cleanup --only firestore `
  "node --test --test-concurrency=1 functions/test/*.emulator.js"
flutter analyze --no-pub
flutter test --no-pub test/activity_push_router_test.dart `
  test/push_permission_explanation_test.dart test/expiry_push_test.dart `
  test/notification_repository_test.dart test/verification_notification_navigation_test.dart
```

Tests explicitly inject gates only into loopback demo namespaces and fake **all**
FCM sends. They test persisted authorization/delivery state, not OS delivery or
real App Check acceptance. Existing expiration/repost demo instructions remain in
`firebase-expired-job-activation.md`.

## Physical devices: approval and platform setup required first

Do not execute against production until cloud setup, deployment/index creation,
configuration and test-account use are separately approved. There is no FCM
delivery emulator. Current target validation accepts only
`swiftserve-production/(default)` outside demo emulators. A separate real staging
project first needs approved matching native/Dart configuration and explicit
target-validation adaptation. Firebase CLI project selection alone does not
change the app/Admin SDK target.

1. Approve Node 22 Functions runtime, correct region (placeholder us-central1),
   default database, least-privilege runtime identity, FCM HTTP v1 access,
   Functions/Eventarc/Scheduler APIs, Blaze billing and the new composite index.
   Configure only reviewed gates. Keep expiration disabled while testing chat.
   No deployment or cloud configuration command was executed here.
2. Configure App Check for Play Integrity and App Attest/DeviceCheck fallback.
   Development builds may require an approved debug-provider setup; never disable
   callable enforcement or commit debug tokens. The optional
   `--dart-define=PUSH_APP_CHECK_DEBUG=true` selects debug providers **only in a
   debug build**; release always uses the real providers. Register each debug
   secret privately through an approved Firebase setup before testing; never
   publish logs containing it. No debug secret was generated or registered here.
3. Android: verify the existing google-services.json matches the package/project,
   Google Play services and Android 13+ POST_NOTIFICATIONS permission. The existing
   swiftserve_jobs channel is created natively; its display name is “Job updates.”
4. iOS requires macOS/Xcode and Apple signing. **GoogleService-Info.plist is absent
   from this checkout.** Obtain the correct Firebase config through approved setup
   and include it in Runner resources. Verify actual bundle ID/provisioning
   (currently com.example.myApp), Push Notifications, Background Modes/Remote
   notifications, APNs key in Firebase, and matching APS_ENVIRONMENT signing.
   Existing entitlements use development for Debug and production for Release.
   Keep Firebase method swizzling enabled. Never commit an APNs private key.
5. After approvals/setup, install enabled builds using two test accounts/devices:

   ```powershell
   adb devices
   adb reverse tcp:5000 tcp:5000
   cd C:\Users\User\Documents\SwiftServe\mobile\my_app
   flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://127.0.0.1:5000 --dart-define=ENABLE_PUSH_NOTIFICATIONS=true --dart-define=EXPIRY_FUNCTIONS_REGION=us-central1
   ```

   ```sh
   # macOS, signed physical iPhone, approved reachable HTTPS backend
   cd /path/to/SwiftServe/mobile/my_app
   flutter run -d <iphone-device-id> --dart-define=API_BASE_URL=https://<approved-test-backend> --dart-define=ENABLE_PUSH_NOTIFICATIONS=true --dart-define=EXPIRY_FUNCTIONS_REGION=us-central1
   ```

   Port 5000/adb reverse serve the HTTP backend, not FCM. Do not set
   LOCAL_FIREBASE_EMULATOR_HOST for real push. A native reinstall/rebuild is needed
   for platform changes; preserve local user data instead of uninstalling casually.
6. Sign in → explanation → Continue → Allow. Inspect registration through approved
   server-side diagnostics without printing tokens. Send one message from the
   other account: recipient only, safe preview, exactly the intended conversation
   on tap. Test foreground View, background tap and terminated cold tap. Android
   force-stop/iOS swipe-away restrictions require reopening before reliable receipt.
7. Repeat with Not now, native denial, app preferences off, and OS permission off.
   The app remains usable; in-app notifications still arrive. Re-enable through
   Settings. Test application received/accepted/rejected, booking status,
   verification and review routes. Expiration→original details→repost needs its
   separate approved test activation; do not enable it merely to test chat.
8. Test a second recipient device, different category preferences, sign-out,
   token refresh and account switching. Only currently bound permitted devices
   should receive pushes. Do not copy tokens into screenshots or Git.
9. Inspect approved Functions logs, retry status, per-device journals and
   dead-letter reasons. Never log raw text/tokens. FCM acceptance is not physical
   display; verify devices directly and investigate repeated pending/dead letters.

Rollback requires separate approval: close activityPushEnabled/activityEventsEnabled
and corresponding environment gates; ship a build without the push flag. Retain
outboxes/journals/in-app data for diagnosis. Do not delete jobs/history, deploy
rules or reset Git.

Official setup: [Flutter FCM](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
and [permissions/foreground/notification taps](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

## Changed files in this task

Validation actually run on 2026-10-31 (Asia/Manila):

- Functions unit command above: **10 passed, 0 failed**.
- Full four-file Functions Firestore emulator suite: **47 passed, 0 failed**.
  After the last notification deletion-journal adjustment, the focused eight
  activity emulator tests were rerun: **8 passed, 0 failed**. These eight overlap
  the 47; they are not 55 distinct tests. Current implementation files were
  byte-compared with the isolated tested copy.
- Flutter analyzer: **no issues**. Five focused Flutter files above: **25 passed,
  0 failed**, including four explanation/native-consent callback combinations.
  Native OS prompts and delivery were not exercised by those widget callbacks.
- Index JSON and existing iOS plist/entitlements parsed successfully; scoped
  `git diff --check` passed.
- Initial attempts encountered sandbox child-process EPERM, an export-list
  expected-order assertion, analyzer lint findings, and a focused retry after
  the emulator had shut down (eight setup-hook connection failures). These were
  corrected/rerun; no unresolved failures remain in the final focused runs.
- Full Flutter suite, standalone Firestore/Storage rules suite, Android APK/iOS
  native builds, real App Check transport and physical-device delivery were
  **not run**. Previously reported unrelated rules/date-picker failures were
  not modified or reclassified as passing.
- Branch stayed main, zero staged paths and zero unmerged paths at final review.
  Existing unrelated local work remains; no Git mutation/deployment occurred.

Under `mobile/my_app/`:

- functions/.env.example
- functions/src/activityPush.js (new)
- functions/src/index.js
- functions/src/runtime.js
- functions/test/activityPush.test.js (new)
- functions/test/activityPush.emulator.js (new)
- functions/test/runtime.test.js
- firestore.indexes.json (local declaration only)
- lib/shared/services/activity_push_router.dart (new)
- lib/shared/services/expiry_push_router.dart
- lib/shared/services/expiry_push_service.dart
- lib/shared/screens/swiftserve_settings_screen.dart
- lib/shared/widgets/push_notification_preferences.dart (new)
- lib/shared/widgets/push_permission_explanation.dart (new)
- test/activity_push_router_test.dart (new)
- test/push_permission_explanation_test.dart (new)
- android/app/src/main/kotlin/com/example/my_app/MainActivity.kt
- ios/Runner/AppDelegate.swift

Under `swiftserve-backend/docs/`: this guide and an appended cross-reference in
firebase-expired-job-activation.md. No package, rule, backup, archive, .metadata or
Linux configuration was changed.
