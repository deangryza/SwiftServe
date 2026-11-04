# Local live-data viewer

## Approved administrator creation exception

The owner separately approved real administrator creation. To run the local API
with only creation and interrupted-setup recovery enabled:

```powershell
node --use-system-ca scripts/startLiveAdminReadOnly.js --super-admin --allow-admin-creation
```

This permits only `POST /api/admin/administrators` and
`POST /api/admin/administrators/{generatedUid}/complete-setup`. The existing
management router still checks Firebase token revocation, current administrator
status and Super Admin authorization. The boundary is not an authorization bypass.
JSON requests are capped at 100 KiB. All PATCH/PUT/DELETE requests and unrelated
POST requests remain blocked. CORS permits GET/POST only from the local frontend.

Creation writes a new Firebase Auth account, its `staff: true` claim, an
`admin_accounts` record with assigned permissions, and audit history. It does not
promote existing users, alter the Super Admin claims or enable account editing.
The owner enters actual account details and submits the form; automated checks
use synthetic local/emulator accounts, never production test accounts.

If creation is interrupted, refresh the administrator list before retrying. Use
Retry setup for a provisioning record; do not create another account blindly.
The existing workflow rejects duplicate email addresses rather than overwriting
an existing user. Audit history and failed-setup records are retained.

Rollback: stop this local launcher and restart without `--allow-admin-creation`.
This blocks future creation and recovery requests without deleting any accounts or
audit records. The default launcher always resets this gate to false unless the
explicit flag is supplied. Push, cleanup, billing, deployment and all other
production operations remain outside this approval.

The read-only sections below describe operation **without** this explicit exception.

This is a separate local connection to `swiftserve-production`, database `(default)`.
It does not deploy anything or alter the existing demo or production configuration.

From `swiftserve-backend`:

```powershell
node --use-system-ca scripts/startLiveAdminReadOnly.js
```

The owner approved local Super Admin recognition for the verified account
`admin@swiftserve.com`, UID `n4n7wxbWo6OkRmlEsrlk3V7mJhy1`. To enable it in this
local viewer, use:

```powershell
node --use-system-ca scripts/startLiveAdminReadOnly.js --super-admin
```

This sets the backend-only UID allowlist in the process environment. It does not
write claims, account records, or a browser variable. Startup still verifies the
existing identity and current admin claim. Other UIDs are rejected by validation.
The Admin Management tab and authorized listing/audit reads are available, but
all creation, setup, edit and status-change requests remain blocked. Without the
flag and without an inherited approved allowlist, legacy access is unchanged.

Open **http://127.0.0.1:5182** and use the existing real administrator account.
Do not use the synthetic emulator password. API: `http://127.0.0.1:5004`.
Both processes bind only to loopback. Keep the terminal open; Ctrl+C stops them.
The original emulator viewer remains at port 5181 with API port 8888.

Startup pins the project/database and verifies the existing account's UID, email,
enabled state and legacy administrator claim. Credentials come from the local
Firebase CLI login in server memory only; no key file is created. This uses the
operator's existing privileges, not a new least-privilege hosted identity. Do not
host this launcher or copy its login credentials into a deployment.

Only GET data routes are mounted. A global middleware rejects mutation methods
before reaching those routes. Authentication, revocation and current administrator
claims are still checked by the existing middleware. This is an application-level
read-only safeguard, not an IAM restriction on the operator credential.

Read-only viewing does consume production Firestore reads. Existing overview/list
routes load entire collections and can repeat queries; avoid repeated refreshes.
Private verification-image routes are not mounted. Admin Management read routes
are mounted behind the existing Super Admin check. Existing
UI mutation controls may still appear but receive an explicit rejection. Account
creation, permission changes, verification decisions, image access and other writes
are not enabled. Push and cleanup gates remain off. No Firebase claims are
changed; Super Admin recognition is scoped to this approved local backend process.

Verified locally: live database metadata and specified Auth account read checks;
6 backend target/method/pilot tests and 12 frontend tests; HTTP health 200,
unauthenticated session 401, mutation rejection 403, and Vite HTML 200.
Actual browser sign-in, authenticated dashboard data queries, image access and
end-to-end production management were not tested. The operator must sign in and
confirm read-only viewing before further activation is considered.

Any write activation needs specific approval of the affected operations and the
Super Admin mechanism. Do not remove read-only middleware as an activation shortcut.
Review deployed rules and backend authorization, use an explicit trusted runtime
and establish backup/audit procedures first. No rules, claims, accounts, settings,
deployments, billing, or hosted resources were changed by this preparation.
