# No-billing Android expiration test

This test uses only `demo-swiftserve-cleanup` with local Auth and Firestore
emulators. No deployed Firebase project, cloud Scheduler, billing, FCM or real
account is required. It tests in-app notifications, not lock-screen pushes.
Keep the computer and both service terminals running. If the phone is offline,
the computer can still expire demo jobs; the phone reads notifications after
reconnecting. Turning off the computer stops this local background service.

## Terminal 1: start the emulators

If ports 9099 and 8187 already belong to this demo, reuse them. Do not stop other
services or delete existing data to free a port. The helper's seed operation
preserves matching existing demo profiles/accounts; it does not reset passwords.

```powershell
$root = 'C:\Users\User\Documents\SwiftServe'
$logs = Join-Path $env:TEMP ('SwiftServeExpiryPhone-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $logs | Out-Null
Set-Location $logs
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
node --use-system-ca "$root\mobile\my_app\rules-tests\node_modules\firebase-tools\lib\bin\firebase.js" emulators:start --project demo-swiftserve-cleanup --config "$root\mobile\my_app\firebase.local.json" --only auth,firestore
```

## Terminal 2: seed demo accounts and start automatic local cleanup

Use a fresh terminal without production credentials or project/emulator overrides.
The helper rejects credential/config overrides, remote endpoints and real project
IDs before initializing Firebase. `--write-demo` explicitly authorizes emulator
metadata, synthetic fixtures, and expiration/notification/outbox writes. Without
that flag, the helper does not initialize Firebase or write anything.

```powershell
Set-Location C:\Users\User\Documents\SwiftServe\mobile\my_app\functions
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8187'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
node --use-system-ca scripts/localExpiryDemo.js --write-demo --seed-demo
```

The helper checks every five seconds after the previous sweep finishes. It uses
the existing durable checkpoints, fenced leases and history-protection policy.
It logs failed scans and retries without overlapping runs. Ctrl+C waits for the
active sweep, then closes its SDK connection. The in-app notification and inert
outbox are written together; no dispatcher or FCM sender is started. Emulator
settings explicitly disable push and device registration. Nothing changes the
production defaults or schedule.

Synthetic client: `client-expiry@example.test`

Synthetic worker: `worker-expiry@example.test`

Both use `LocalTestOnly-Password123!`. Use these only in the demo app. The worker
profile is synthetically marked verified in the emulator; no production account
or verification claim is modified. Existing account mismatches cause failure
rather than overwriting someone else's fixtures.
The seed also creates a synthetic active Cleaning category if missing, so the
post/repost form has a valid selection. Mismatched existing category records are
rejected rather than overwritten.

## Terminal 3: prepare a separate Android install

```powershell
Set-Location C:\Users\User\Documents\SwiftServe\mobile\my_app
C:\flutter\bin\dart.bat run tool/prepare_android_expiry_demo.dart
```

The command prints a new temporary directory. It copies current sources, gives
the app package `com.example.my_app.expiry_demo` and label **SwiftServe Expiry
Demo**, replaces Firebase options with synthetic demo-only settings, excludes
signing secrets and native alternate Firebase files, and disables cloud fallback.
Production/staging source configurations are preserved. Run from that directory:

The debug Firebase bootstrap explicitly disables FlutterFire automatic host
mapping for Auth, Firestore and Functions. Thus physical-phone `127.0.0.1` stays
USB loopback, while an explicitly selected `10.0.2.2` stays the Android-emulator
host. Without this setting, FlutterFire remaps loopback to `10.0.2.2` and a real
phone's sign-in fails even when `adb reverse` is correctly configured.

```powershell
C:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile
$adb = 'C:\Users\User\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb devices -l
# Substitute the exact device serial shown above. Unlock and accept USB debugging.
& $adb -s YOUR_DEVICE_SERIAL reverse tcp:9099 tcp:9099
& $adb -s YOUR_DEVICE_SERIAL reverse tcp:8187 tcp:8187
C:\flutter\bin\flutter.bat run -d YOUR_DEVICE_SERIAL --debug --dart-define=LOCAL_FIREBASE_EMULATOR_HOST=127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:5006 --dart-define=ENABLE_PUSH_NOTIFICATIONS=false --dart-define=ENABLE_EXPIRY_PUSH=false
```

Only existing seeded email/password login is supported by this walkthrough.
Do not use Google sign-in, register real accounts, submit identity documents or
test API-based onboarding here. Port 5006 intentionally does not point to the
production/local-live/staging backend. The post/repost flow uses Firestore
directly. Choose Online work to avoid unrelated map/API dependencies. For a
desktop Android emulator, use `LOCAL_FIREBASE_EMULATOR_HOST=10.0.2.2` instead.

## Phone walkthrough

1. Sign into **SwiftServe Expiry Demo** as the synthetic client.
2. Create an Online job with a service start at least two minutes in the future
   (PHT), a valid end date, budget, title and description. Avoid midnight because
   existing policy conservatively retains ambiguous legacy midnight records.
3. Optionally switch to the synthetic worker and confirm it appears under Recent.
   Do not apply: any application in any status protects the original from the
   no-applications expiration policy.
4. At the service deadline, worker discovery and Apply become unavailable.
   Cleanup should mark it expired on a subsequent local sweep, typically within
   five seconds plus processing time. This is not an exact-second guarantee.
5. Sign back into the client, open Notifications, and tap the expiration event.
   It opens the original expired details with Repost Job at the bottom.
6. Tap Repost. Verify the editable details remain while dates/time must be
   selected again. An unchanged expired or missing schedule must be rejected.
7. Select a future schedule and submit. Confirm the new pending post exists and
   the original expired post remains unchanged. No application/history is copied.
8. Repeat while the app is closed: the computer should still create the in-app
   notification, which appears after reopening. No system push is expected.

## Reproducible local checks

From mobile/my_app/functions, with the two emulators and helper running:

```powershell
node --test test/*.test.js
$env:RUN_LOCAL_EXPIRY_DEMO_TESTS = 'true'
node --use-system-ca --test test/localExpiryDemo.emulator.js
```

The integration test signs in through emulator Auth, creates a synthetic timed
job with the client SDK under local rules, waits for the running worker to expire
it, reads the owner's notification, and verifies late worker writes and private
notification reads are denied. It leaves synthetic records for inspection and
never clears all emulator data. Expected permission-denied logs are assertions.

From mobile/my_app:

```powershell
C:\flutter\bin\flutter.bat test --no-pub test/android_expiry_demo_test.dart test/expired_job_repost_test.dart test/service_deadline_test.dart
C:\flutter\bin\flutter.bat analyze --no-pub
```

Physical phone installation, notification taps and the full UI repost walkthrough
must be reported separately from successful automated SDK tests. No hosted or
physical-device push behavior is established by this local test.

## Verified on the connected Samsung Android phone, November 1, 2026

- Separate demo APK built successfully and installed alongside the real app.
- Native packaged ID/label verified; FirebaseInitProvider disabled in demo manifest.
- The first native login exposed automatic loopback remapping to 10.0.2.2. The
  debug bootstrap now disables automatic host mapping; physical email/password
  sign-in and client dashboard loading then succeeded through USB forwarding.
- The expiration notification appeared in the client's feed and opened the
  original expired Booking Details with Repost Job at the bottom.
- Repost preserved editable content and required new FROM/TO dates and a time.
  Submitting without a schedule showed the expected validation error.
- Selecting November 2, 2026 at 9 AM PHT saved successfully and opened a new
  Pending job. Emulator records confirmed a distinct ID, unchanged expired
  original, and the selected UTC instant `2026-11-02T01:00:00.000Z`.
- With the demo app force-stopped and its process absent, the local runner expired
  another synthetic timed job and created a notification. That notification was
  visible on the physical phone after reopening.
- The local SDK integration check also rejected a late worker application and
  another account's notification read. The physical worker UI and a manually
  selected past-time submission were not exercised in this walkthrough; automated
  deadline/repost tests cover those validations.

This is not production activation, a hosted-service test, iOS verification, or
physical FCM delivery. Keep production disabled. USB disconnection can remove port
forwarding; reapply both `adb reverse` commands after reconnecting. If local
terminals/processes stop, restart the emulators and helper before trying sign-in.
Do not clear or delete emulator records as a connection troubleshooting shortcut.
