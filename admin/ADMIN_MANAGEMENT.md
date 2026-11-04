# Admin Management — local implementation and review

This extends the existing web admin panel; it does not replace Super Admin or
change production Firebase configuration/data. All newly created accounts during
validation exist only in local demo Auth/Firestore emulators. Nothing was deployed.

## Features

Super Admin can list/search/filter administrators by name, email, role and status;
create a Firebase Auth account with a temporary password; edit name/email/custom
role label/permissions; deactivate, suspend and restore managed administrators;
see Auth creation/last-sign-in dates; and inspect read-only activity history.
New forms reuse the existing admin colors, components, cards and table layout.
There is no delete-administrator endpoint. All existing Super Admin/legacy accounts
are protected from these management operations, including the last Super Admin.

A role label is descriptive, not an authority source. Permissions can be customized
across dashboard/analytics, users, workers, clients, verification, reports,
bookings, categories and SOS. Manage/edit grants corresponding view access.
Admin Management is never assignable to regular administrators.

The existing user module also supports permission-gated full-name edits, synchronized
with existing public/worker name projections. Residential information is not changed.
Account status and verification decisions remain distinct workflows.

## Trust model / configuration still required

The old system uses `admin: true` for full access and has no distinct Super Admin
marker. Existing authorized full-access accounts retain their existing modules.
They are not silently promoted to new administrator-management authority.

The user chose to supply the existing Super Admin UID later. On the trusted backend,
set the local environment variable (placeholder only):

```powershell
$env:SWIFTSERVE_SUPER_ADMIN_UIDS = '<EXISTING_SUPER_ADMIN_AUTH_UID>'
```

An allowlisted UID must still have the existing **current** Auth `admin: true` claim.
Alternatively, a trusted `superAdmin: true` custom claim plus `admin: true` is
recognized. No live claims, UID allowlist, real admin accounts or environment files
were changed by this implementation. Never put this allowlist in VITE_* variables
or accept it from a request body. No auto-bootstrap promotes the first user.

New regular admins receive only `staff: true`; they never receive `admin: true`.
Their current permissions/status live in `admin_accounts/{authUid}`. The backend
checks token revocation, current Auth claims, disabled state and current account
record on every request. Stale tokens cannot recover removed permissions. Current
email must match during synchronization. Existing full-access accounts also receive
current-claim/revocation checks; authorized existing access is preserved.

Frontend navigation, landing pages and direct URL guards use `/api/admin/session`.
They refresh every 30 seconds and on focus/token changes, while API authorization is
checked immediately on each request. Overview-only access returns aggregate fields
without names/contact data; scoped worker/client queries are filtered server-side.
Administrator identities are excluded from managed staff's user-discovery results.
Sensitive verification-image endpoints have their own permission guards.

## Schema / rules / index

- `admin_accounts/{uid}`: name, email, custom role label, permissions, status,
  version, createdBy, timestamps and synchronization metadata. No passwords.
- `admin_audit_logs/{generatedId}`: verified actor ID/name or email, action,
  target ID, server timestamp and allowlisted action details. No tokens/passwords.
- One local composite index was added to `mobile/my_app/firestore.indexes.json`:
  collection `admin_audit_logs`, actorId ASC + createdAt DESC. It supports latest
  per-actor activity. **The index has not been deployed.** All-actor history uses
  the existing automatic timestamp index. API history is limited to 100 latest
  entries per request; stored history is not deleted or truncated.

There is no destructive migration and no automatic conversion of ordinary users.
An email already belonging to any Auth account is rejected instead of promoted.
Old full-access Auth accounts remain visible in the directory. Deleted Auth users
are not active registered administrators; their audit records remain available.

No Firestore or Storage rule was changed. Existing local default-deny rules block
client reads/writes of both new collections, including staff/admin-token clients.
The browser uses authenticated backend endpoints; Admin SDK writes bypass rules
only after backend authorization. Emulator tests verify denied direct writes,
reads of authority records and audit edits/deletes. Before any future activation,
verify that the intended environment's deployed rules match this protection; this
implementation did not access production to inspect deployed rules.

## Passwords, invitations and failure recovery

Temporary passwords require 12–128 characters, uppercase/lowercase, a number and
symbol, and are sent only to Firebase Auth. They are not stored in Firestore,
audit records or API responses. The Super Admin must share credentials privately
and the recipient should change the password through existing profile settings.
Automatic invitation email is not implemented because there is no existing email
sender/invitation workflow to reuse. Do not claim that generating an invitation
sends an email or that Firebase Admin can force a first-login password change here.
Real deployment must use HTTPS and appropriate administrator authentication controls.

Auth and Firestore cannot be committed atomically:

- Creation starts with a disabled Auth account and a non-authorized provisioning
  record. Only completed setup becomes active. Incomplete recorded setup has a
  Super Admin-only Retry setup action; it cannot convert an existing ordinary user.
- If the very first Firestore write fails, a disabled Auth-only orphan can remain.
  Reconcile it manually after reviewing the failure; never auto-delete user accounts.
- Edits block access in an updating state, version-check transactions, synchronize
  Auth, then transactionally finish the desired status and audit record. Failed
  synchronization stays inactive/retryable. Interrupted updates remain blocked;
  after five minutes a Super Admin can refresh and retry with the latest version.
- Stale completions cannot overwrite newer Firestore authority. Auth remains a
  separate service: interrupted/concurrent external writes can require another
  synchronization. Status, current claim, disabled state and email checks fail
  closed while inconsistent. There is no exactly-once cross-service guarantee.
- Permission/status/report/category/booking/SOS/verification/profile actions are
  audited. Firestore record changes and their success audit share a batch or
  transaction. Auth account-status changes also record an intent before the Auth
  call; an Auth change cannot be rolled back atomically if the later database
  operation fails. No regular-admin audit mutation endpoint exists.

## Automated tests

Use the installed Node 22+ and Java 21+. From `swiftserve-backend`:

```powershell
node --test --test-reporter=tap
```

From `admin`:

```powershell
node --test test/adminAccess.test.js
npm run build -- --outDir <NEW_TEMPORARY_OUTPUT_DIRECTORY>
```

The integration suite is deliberately opt-in and rejects non-loopback emulators.
From any temporary logging directory, using absolute paths:

```powershell
$env:RUN_ADMIN_EMULATOR_TESTS = 'true'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:DEBUG = ''
node C:\Users\User\Documents\SwiftServe\mobile\my_app\rules-tests\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --project demo-swiftserve-admin-management --config C:\Users\User\Documents\SwiftServe\firebase.admin-emulators.json --only auth,firestore "node --test C:/Users/User/Documents/SwiftServe/swiftserve-backend/test/adminManagement.emulator.test.js"
```

Clear the opt-in flag in a fresh terminal before a plain backend unit-suite run;
that run does not substitute for emulator testing. Logs/builds remain outside the
repository. Earlier runs found and corrected a restricted-overview handler typo,
missing Auth/audit capabilities in existing test doubles, and expected 403 responses
where the emulator correctly returns 401 for disabled/revoked credentials.
Related SOS/admin-data test doubles were updated with audit assertions, not bypasses.

## Manual browser review using only demo emulators

1. In a temporary log directory start the same emulators with `emulators:start`
   instead of `emulators:exec` and the same project/config/--only auth,firestore.
2. In a separate PowerShell terminal:

```powershell
Set-Location C:\Users\User\Documents\SwiftServe\swiftserve-backend
$env:GOOGLE_CLOUD_PROJECT = 'demo-swiftserve-admin-management'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8188'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9499'
$env:DEBUG = ''
node scripts/startAdminDemo.js --seed-super
```

This launcher requires the exact demo project, both loopback emulators and no
credential/config/bucket overrides; it never loads dotenv, starts a worker or
uses a real Firebase project. It binds only to `127.0.0.1:5003`. The optional seed
creates only `super@example.test` with the documented disposable demo password
`LocalTestOnly-Password123!` and trusted Super Admin claims **in Auth emulator only**.
Never reuse these public fixture credentials in staging/production.

3. In a separate terminal in `admin`, override all public SDK values for the demo:

```powershell
$env:VITE_FIREBASE_PROJECT_ID = 'demo-swiftserve-admin-management'
$env:VITE_FIREBASE_API_KEY = 'demo-key'
$env:VITE_FIREBASE_AUTH_DOMAIN = 'demo-swiftserve-admin-management.localhost'
$env:VITE_FIREBASE_STORAGE_BUCKET = 'demo-swiftserve-admin-management.invalid'
$env:VITE_FIREBASE_MESSAGING_SENDER_ID = '123456789'
$env:VITE_FIREBASE_APP_ID = '1:123456789:web:0000000000000000000000'
$env:VITE_USE_FIREBASE_EMULATORS = 'true'
$env:VITE_API_BASE_URL = 'http://127.0.0.1:5003'
npm run dev -- --host 127.0.0.1 --port 5179 --strictPort
```

The emulator switch is rejected outside a development build or with any other
project. Open http://127.0.0.1:5179, sign in with the demo fixture, then test creating
an admin, restricted login/navigation/direct URLs, editing permissions, suspension,
restoration, filters and activity. Check keyboard navigation and a narrow viewport.
The backend, UI and emulators were started successfully for this review. Browser
automation itself was blocked by an unavailable browser access host, so no visual
or end-to-end browser success is claimed. Stop only these demo terminals with
Ctrl+C when finished; keep the unrelated staging backend/phone build untouched.

## Before any real activation

1. Supply/verify the existing Super Admin UID locally; preserve its full-access claim.
2. Review all local diffs and security tests. Review actual browser flows manually.
3. Review the intended environment's deployed rules, HTTPS/authentication controls,
   runtime Auth/Firestore IAM, backups and audit retention/monitoring.
4. Approve backend + web deployment together; old backends lack the new session API.
5. Separately approve the activity index deployment to the intended project.
6. Create real admin accounts only after explicit approval; do not convert users.

The existing staging port 5002 backend enforces Android-only App Check. This demo
uses 5003 and does not exempt/bypass that staging gate. A real staging web test
needs a separately configured staging web app/App Check integration and approved
app-ID validation. Never reuse an Android debug token as web authentication or
point the admin web build at production to bypass a staging restriction.
No billing, Functions, production changes or deployment are authorized by this work.

## Final validation and exact changed-file list

Actual final results:

- Backend unit suite: **170 passed, 0 failed** (`node --test --test-reporter=tap`).
  The opt-in admin emulator suite is separate from this result.
- Auth/Firestore admin integration suite: **11 passed, 0 failed**. Covers original
  full access, Super Admin-only authority, regular creation/login, permission and
  role scope, denied direct API/database access, protected Super Admin, suspension,
  restoration with a fresh token, audit integrity, failed provisioning recovery,
  failed synchronization, concurrent editors, profile-name/version synchronization,
  and removed claims with previously issued tokens.
- Frontend permission policy: **3 passed, 0 failed**.
- Web builds passed, including final guarded emulator-mode code. Vite reports a
  non-blocking >500 kB bundle-size warning; no unrelated bundle refactor was done.
- Diff whitespace check passed. Git printed LF/CRLF conversion notices for some
  existing web files; no Linux or unrelated line-ending normalization was made.
- Browser host unavailable: visual/responsive/keyboard and end-to-end browser login
  remain manual checks. No production readiness or live invitation delivery claim.
- Known prior Flutter/date-picker and three rules-fixture/policy failures were not
  modified or represented as fixed. No Flutter code changed for this admin feature.

Changed for this feature (existing staging changes are excluded from this list):

- admin/src/App.jsx
- admin/src/components/LoginForm.jsx
- admin/src/components/ProtectedRoute.jsx
- admin/src/components/Sidebar.jsx
- admin/src/components/UserDetailsModal.jsx
- admin/src/components/UserManagement.jsx
- admin/src/components/UserTable.jsx
- admin/src/layouts/DashboardLayout.jsx
- admin/src/lib/api.js
- admin/src/lib/firebase.js
- admin/src/lib/adminAccess.js (new)
- admin/src/lib/AdminAccessContext.jsx (new)
- admin/src/page/dashboard/DashboardHome.jsx
- admin/src/page/administrators/AdminManagement.jsx (new)
- admin/test/adminAccess.test.js (new)
- admin/ADMIN_MANAGEMENT.md (new)
- firebase.admin-emulators.json (new, test only)
- mobile/my_app/firestore.indexes.json (one local index; not deployed)
- swiftserve-backend/src/app.js (adds the protected management router; staging code preserved)
- swiftserve-backend/src/middleware/adminMiddleware.js
- swiftserve-backend/src/services/adminAccessService.js (new)
- swiftserve-backend/src/routes/adminManagementRoutes.js (new)
- swiftserve-backend/src/routes/adminDataRoutes.js
- swiftserve-backend/src/routes/adminVerificationRoutes.js
- swiftserve-backend/src/controllers/adminVerificationController.js
- swiftserve-backend/scripts/startAdminDemo.js (new, guarded local demo only)
- swiftserve-backend/test/adminManagement.emulator.test.js (new)
- swiftserve-backend/test/adminDataRoutes.test.js (Auth/audit-aware mock and assertion)
- swiftserve-backend/test/sos.test.js (Auth/audit-aware mock and assertion)

No existing safety backup, archive, secret, .env, lockfile, production Firebase
configuration, rule, .metadata or Linux configuration was changed. Branch main and
all prior staged/unstaged/untracked work were preserved; nothing was staged,
committed, pushed or deployed. Firebase owners and existing trusted CLI tools are
outside the web API boundary; application protections cannot restrict a project
owner's direct root access. Govern that access separately before real deployment.

Final demo handoff check also passed: UI HTTP 200 on 5179, emulator Email/Password
sign-in, trusted Super Admin session and management-list API on 5003. Tokens were
not printed. The demo services were restarted after integration tests and are
available for manual review; this HTTP/API check does not verify browser rendering.
