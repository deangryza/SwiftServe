# SwiftServe isolated Android staging environment

Status (2026-10-31, Asia/Manila): staging backend/profile API testing works.
Physical-device fresh App Check and complete onboarding/dashboard verification
remain pending because the phone was unavailable for this round.

## Fixed target and safety boundary

- Firebase project: `swiftserve-staging-2026`, number `856393660184`.
- Database: `(default)`, Standard/Native mode, Singapore `asia-southeast1`.
- Android package: `com.example.my_app.staging`, label `SwiftServe Staging`.
- Android Firebase app: `1:856393660184:android:5ab53b8630b20d3e47d06d`.
- Backend: **http://127.0.0.1:5002**, loopback only; USB reverse forwarding is
  required on the phone. Port 5000 and the original app remain separate.

No production Firebase settings/data/configuration were accessed or changed.
No Functions deployment, rule/index deployment, billing, IAM changes, scheduling
or push delivery was enabled in this round. No Git staging/commit/push occurred.
Existing rules, SDK dependency snapshots, archives, backups, .metadata and Linux
configuration were preserved.

Previously approved staging setup enabled Email/Password and Google providers,
created the database with deletion protection (PITR disabled), deployed existing
staging rules/indexes, and registered the Android debug signing fingerprints.
All four staging composite indexes reached READY. Play Integrity is configured
with strict recognition/licensing checks and a one-hour TTL; service enforcement
was not changed. A debug-device token was privately registered in the earlier
phone session. Google sign-in was verified on that phone in the earlier session.

## Start the isolated backend

Use the existing CLI login; no service-account private key or ADC file is needed.
These are the installed Node/CLI locations verified on this computer:

```powershell
$swiftServeNode = 'C:\Users\User\AppData\Local\npm-cache\_npx\52027bd8fc0022aa\node_modules\node\bin\node.exe'
$firebaseToolsDirectory = 'C:\Users\User\AppData\Local\npm-cache\_npx\ba4f1959e38407b5\node_modules\firebase-tools'
Set-Location C:\Users\User\Documents\SwiftServe\swiftserve-backend
& $swiftServeNode --use-system-ca scripts/startStaging.js $firebaseToolsDirectory
```

Keep this terminal running. If the agent-started staging backend is already
healthy, use it rather than starting a second server on the same port. If npm
cache cleanup removes the CLI package, locate/reinstall the CLI outside the
repository and supply its actual package directory; do not substitute a key file.
The launcher requires an existing Firebase CLI account with staging access.

The launcher deliberately does **not** load `.env`, `server.js`, ADC or a cleanup
worker. It pins all Auth/Firestore clients to staging, pins the default database,
sets push/cleanup gates false and cleanup dry-run true, and rejects conflicting
project/port/database settings, Firebase config/bucket overrides, credential-file
variables, emulator endpoints and enabled delivery/cleanup gates. It reads staging
Firestore and Auth before listening. Storage uses the existing local verification
mode with uploads isolated under `%TEMP%\SwiftServeStagingUploads`; a Cloud Storage
bucket call fails explicitly. No paid bucket is created or needed for profiles.

The CLI account is a developer identity which may have access to other projects;
this launcher constrains resource targets, not that identity's IAM privileges.
Use only on this developer computer, never expose it on a LAN/public server or
share CLI credentials. A hosted runtime would require a separately approved,
staging-scoped least-privilege identity. Stop on a preflight rejection rather
than clearing credential/project safeguards blindly.

Check readiness in another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:5002/api/health
```

Expected: ok=true, environment=staging, projectId=swiftserve-staging-2026,
databaseId=(default). Production health responses cannot satisfy this check.
This public health endpoint does not test a user's permissions; the staging
session/profile endpoints require both valid App Check and Firebase Auth tokens.

## Build and run the separate Android app

From the repository app directory:

```powershell
Set-Location C:\Users\User\Documents\SwiftServe\mobile\my_app
dart tool/prepare_android_staging.dart
```

Change to the **new temporary directory printed by the tool**, then run:

```powershell
flutter pub get --offline --enforce-lockfile
adb devices
adb reverse tcp:5002 tcp:5002
flutter run --debug --dart-define=ENABLE_PUSH_NOTIFICATIONS=false --dart-define=ENABLE_EXPIRY_PUSH=false --dart-define=STAGING_APP_CHECK_DEBUG=true --dart-define=STAGING_BACKEND=true --dart-define=API_BASE_URL=http://127.0.0.1:5002
```

For a saved APK, substitute `flutter build apk --debug --no-pub` for `flutter run`
with the same defines, then `adb install -r build\app\outputs\flutter-apk\app-debug.apk`.
Do not build from the original production directory with these instructions.
The preparation tool validates the real public staging SDK config and changes
only a temporary copy's package, label, native config, Dart options and startup.
It excludes environment files, signing secrets, service-account-named files,
caches and symlinks; original native/Dart Firebase configuration stays unchanged.

`STAGING_BACKEND=true` selects an HTTP wrapper which refuses a non-staging
Firebase project or any API target except `http://127.0.0.1:5002/api/`. It adds
`X-Firebase-AppCheck` without changing Authorization. Token failure blocks writes;
health remains available to diagnose a disconnected backend. The original build
keeps its existing HTTP client and API defaults when this flag is absent.

The previous installed staging APK predates these backend headers: install the
new build before testing the stricter backend. Both push flags stay false.

## App Check and physical-device acceptance

Startup activates the Android debug provider only for the exact staging project
in an Android debug build, then calls `getToken(true)` directly on the device.
It has a 15-second diagnostic timeout and allows the UI to continue after failure.
The existing private device registration should survive an `adb install -r`.
If app data was cleared or the debug secret changed, register the new device
secret privately under the staging Android app. Never paste secrets into chat,
source, issue reports or documentation. Initial throttling can require backoff.
Do not relax Play Integrity or enable service enforcement as a workaround.

Safe Dart status filtering:

```powershell
adb logcat -v brief -s flutter:I | Select-String 'SwiftServe staging:'
```

Look for `fresh on-device App Check token acquired`, then successful backend
HTTP 201/200 activity. A valid token reaching the staging backend is verified
there against the staging Android app ID. A startup message alone proves token
retrieval, not an authorized profile write. Debug-provider success does not
verify Play Integrity release attestation or Play Store distribution.

Manual acceptance for **each** role:

1. Unlock/authorize the USB phone; verify the installed app says SwiftServe Staging.
2. Confirm health, reverse port 5002 and fresh on-device token diagnostics.
3. Create a staging Email/Password account (or use the Google setup flow), fill
   required address/contact fields, and select multiple services for a worker.
4. Continue to the dashboard. Confirm the correct role dashboard actually renders,
   not just Firebase sign-in. Check backend profile HTTP 201 and subsequent reads.
5. Sign out/in again. Verify profile data and worker services persist; verification
   remains pending and is not falsely promoted by this setup.
6. Test network disconnection and denied/invalid credentials; errors must be
   understandable and must not create a partially authorized profile.
7. Repeat for the other role using a separate staging account. Never use or copy
   production accounts, addresses, messages, tokens or job records for the pilot.

Phone unavailable this round: no fresh on-device token, USB forwarding, updated
APK installation, dashboard loading or complete physical onboarding is claimed.

## API-only onboarding smoke test (explicit synthetic writes)

With the staging backend running:

```powershell
Set-Location C:\Users\User\Documents\SwiftServe\swiftserve-backend
& $swiftServeNode --use-system-ca scripts/testStagingOnboarding.js --write-synthetic-staging-records $firebaseToolsDirectory
```

This explicitly creates two synthetic staging Auth accounts and retains their
private/public/worker profiles and hashed phone claims. It uses reserved fictional
202-555-01xx numbers and sends no SMS. Each run creates fresh test identities;
do not run repeatedly without a reason (the reserved phone pool is finite).
Credentials exist only in memory and are not printed/saved. The test temporarily
registers a distinct host-only App Check debug token and revokes **only that new
registration** in finally; existing phone registrations are untouched.

Passed this round: real staging Email/Password signup/sign-in, Auth verification,
App Check verification, client/worker profile transactions and session loading,
worker service/pending-verification persistence, and public location redaction.
Missing App Check, missing Auth and invalid Auth were rejected. This verifies the
backend flow; it does not operate Flutter pickers/forms or render either dashboard.
No existing production or staging account records were overwritten by these tests.

## Diagnostics and automated results

- Startup reports a generic failure plus a sanitized code on credential/project,
  Firestore/Auth preflight or port errors; it never falls back to ADC/production.
- Backend staging logs category, method, HTTP status and sanitized SDK error code.
  They do not log bearer/App Check tokens, bodies, email, address or UID.
- Flutter reports backend status/connection failure or App Check availability,
  not tokens or request bodies. Auth/profile SDK failures use redacted staging
  logging. Existing production behavior is preserved.

Commands actually run:

```powershell
# Backend (Node 22)
& $swiftServeNode --test test/staging.test.js test/health.test.js test/userProfile.test.js test/registrationAvailability.test.js
& $swiftServeNode --test --test-reporter=tap

# Flutter: isolated source copy, existing resolved lockfile
flutter test --no-pub test/staging_api_client_test.dart test/staging_app_check_test.dart test/android_staging_config_test.dart test/client_register_screen_test.dart test/worker_register_screen_test.dart test/registration_availability_flow_test.dart test/profile_address_api_test.dart test/dual_role_test.dart
flutter analyze --no-pub
flutter test --no-pub test/staging_api_client_test.dart test/staging_app_check_test.dart test/android_staging_config_test.dart test/federated_account_form_test.dart test/worker_dashboard_filter_test.dart test/worker_dashboard_asset_test.dart test/client_dashboard_hero_asset_test.dart
```

Results:

- Focused backend: **39 passed**. Full backend: **170 passed, 0 failed**.
  No emulator integration is inferred from those unit tests.
- Initial sandbox Node run failed to spawn test workers (EPERM); approved rerun
  with child-process support passed. Dart formatter wrote files successfully but
  initially could not update telemetry in its sandbox; Flutter analyzer is clean.
- Flutter registration/staging/profile/role selection: **32 passed, 4 failed**.
  All four failures are in unchanged `dual_role_test.dart` settings-role widget
  expectations (account rows below viewport/lazy list). Reproduced in a separate
  temporary copy with committed HEAD API service: **4 passed, same 4 failed**.
  No unrelated test or settings UI was changed. Initial baseline harness lacked
  package_graph.json; copying the existing resolved graph enabled the actual run.
- Separate focused staging/federated/dashboard run: **29 passed, 0 failed**.
  These runs overlap; do not add the counts as unique tests.
- Flutter analyzer: **no issues**.
- Firestore/Storage security demo emulators: **99 tests, 96 passed, 3 failed**.
  `client-review.rules.test.js:120` lacks required clientName; public-profile
  tests at lines 58 and 103 expect location/professional updates denied by the
  current allowlist. Rules/fixtures were unchanged. Policy must decide whether
  public fields stay backend-owned or become safely client-editable separately.

Emulator reproduction uses the established loopback demo config with Firestore
8188, Storage 9298, hub 4488, logging 4588, UI disabled, singleProjectMode false;
Java 21+ and the installed CLI. Run in a temporary copy retaining backend-helper
relative paths (or resolve that one unchanged helper path in the temporary copy):

```powershell
firebase emulators:exec --project demo-swiftserve-staging-check --config firebase.rules-test.json --only firestore,storage "node --test --test-reporter=tap --test-concurrency=1 rules-tests/*.test.js"
```

No Storage service was provisioned in staging; Storage emulator success is not
proof of a live Storage bucket. No known date-picker test was changed or claimed
passed. No full Flutter-suite pass is claimed in this round.

## Stop and future approvals

Stop the staging backend with Ctrl+C in its terminal. Remove only the staging
forwarding rule when finished: `adb reverse --remove tcp:5002`. Keep all profiles,
logs and prior APK backups for review. Production and its port 5000 are untouched.
No cloud rollback, account/data deletion or Git action is part of stopping locally.

Physical phone acceptance above remains necessary. Push registration/delivery,
Functions deployment, runtime APIs, any billing/Blaze upgrade, schedules, hosted
IAM and any security-rule change outside staging each require new approval.
The Functions target allowlist still needs a separately reviewed staging change
before a future push deployment. Do not run `firebase deploy` for this setup.

## Prepared APK and changed files in this continuation

The updated staging debug APK built successfully (`assembleDebug`, 407.3 seconds):
`C:\Users\User\AppData\Local\Temp\SwiftServeAndroidStaging_cccd6ec4\build\app\outputs\flutter-apk\app-debug.apk`.
SHA-256: `D9B8F59C9A8E3ABD5EC6DD3D5561A413A4575FE6FED0227135C7140B44C8647C`.
AAPT2 confirmed the staging package/launcher, and generated native resources
confirmed staging project/app/sender IDs. Prior APKs were retained under distinct
backup filenames. This updated APK was not installed because no phone was attached.
The final startup-diagnostics safety tests were rerun: **3 passed**.

Files changed in this continuation (16):

- `mobile/my_app/lib/shared/services/api_service.dart`
- `mobile/my_app/lib/shared/services/staging_api_client.dart` (new)
- `mobile/my_app/lib/shared/services/staging_app_check.dart`
- `mobile/my_app/test/staging_api_client_test.dart` (new)
- `mobile/my_app/test/staging_app_check_test.dart`
- `mobile/my_app/tool/prepare_android_staging.dart`
- `swiftserve-backend/src/config/firebase.js`
- `swiftserve-backend/src/config/stagingFirebase.js` (new)
- `swiftserve-backend/src/middleware/stagingDiagnostics.js` (new)
- `swiftserve-backend/src/middleware/authMiddleware.js`
- `swiftserve-backend/src/controllers/userController.js`
- `swiftserve-backend/src/app.js`
- `swiftserve-backend/scripts/startStaging.js` (new)
- `swiftserve-backend/scripts/testStagingOnboarding.js` (new)
- `swiftserve-backend/test/staging.test.js` (new)
- `swiftserve-backend/docs/android-staging-push-checklist.md`

Existing untracked staging SDK config, firebase.staging.json and Android config
isolation tests were preserved. No dependency, rule, index, production native
config, branch or Git index changes were made. Final diff whitespace check passed.
