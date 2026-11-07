# Production Admin Management preparation — not activated

Local preparation only. No live identity, claims, rules, records, indexes or
credentials were changed or verified. The existing admin `.env` already specifies
`swiftserve-production`. The running demo overrides it with an isolated Auth
emulator; keep that demo available and never enter real credentials there.

## Identity and authorization

The Firebase CLI operator is not necessarily the app's Super Admin. Obtain the UID
from the existing authenticated production app account, then verify that same UID
in production Firebase Authentication with a read-only check approved by the owner.
Confirm project, existing `admin: true`, no `staff: true`, and enabled status. Do not
infer identity from a display name or promote an ordinary account. No UID is known
or configured by this preparation. No real account should be created for testing.

After identity confirmation and explicit activation approval, set only the trusted
backend's `SWIFTSERVE_SUPER_ADMIN_UIDS` to that verified UID. This adds access to the
new management API without rewriting the account's claims or existing privileges.
Never put the UID allowlist in browser environment variables. Existing separate
`superAdmin: true` claims are also recognized; inspect all such accounts before
claiming there is exactly one Super Admin.

Every management route uses current Auth verification plus the Super Admin check.
New regular accounts use `staff: true` and current `admin_accounts/{uid}` permissions,
status and matching email on each API request. Client-side navigation is secondary.
Existing legacy `admin: true` accounts retain full legacy access, but do not gain
Admin Management without the trusted Super Admin marker. Restricting those legacy
accounts requires a separately approved account-by-account migration; do not silently
remove existing privileges. Project owners/credential holders can bypass these API
controls through Admin SDK access; govern IAM separately.

## Approval checklist, in order

1. Confirm the real account UID and approve narrowly scoped read-only Auth and
   deployed Firestore-rule inspection. Do not export users or print tokens/keys.
2. Verify deployed rules deny all direct client access to `admin_accounts` and
   `admin_audit_logs`, including legacy admin tokens and broad wildcard matches.
   Local rules default-deny these paths; that does not prove deployed protection.
   Backend Admin SDK bypasses rules and must enforce permissions itself. Stop if
   deployed protection differs. Any rule edit/deployment needs separate approval.
3. Approve a trusted production backend runtime with explicit project ID
   `swiftserve-production`, default database, correct existing Storage bucket and
   keyless runtime credentials. Validate credential/project alignment before serving
   requests. Current general ADC initialization does not itself pin a project; do
   not start it with ambient credentials and assume the CLI selected the target.
   Keep staging port 5002 and demo port 5003 separate. Do not reuse the Android-only
   staging App Check gate for web or weaken that gate.
4. Approve deployment/startup of web and backend together, using HTTPS, approved
   origins and protected credentials. Set web API URL to that backend and remove
   emulator overrides in that separate launch environment. Web public SDK project,
   app ID, API key and Auth domain must be from the existing production web app.
   Verify authorized domains and any actual App Check enforcement separately;
   this web build currently has no App Check token integration.
5. Set the verified backend-only UID allowlist. Confirm own session reports the
   expected UID and `isSuperAdmin`, without logging bearer tokens. This production
   sign-in and session verification has not been performed here.
6. Review/approve the `admin_audit_logs` actorId/createdAt index separately if absent.
   No index deployment is included. Review audit retention, backups and monitoring.
7. Obtain separate explicit approval before creating any real regular admin or
   exercising write/status-management actions. Validate restricted-account denial,
   immediate permission changes, revocation, and immutable audit history in demo first.

Do not enable push delivery, cleanup schedules, billing, or deploy Firebase Functions.
No Firestore-rule change is required by the local design if deployed rules already
match the local deny protection; this remains unverified. Roll back activation by
stopping the new web/backend runtime or reverting its deployment and removing the
new allowlist configuration; never delete users/audit records or rewrite claims as
an automatic rollback. Existing management-created staff need reviewed access
handling if returning to an older backend that lacks staff support.

## Local checks and palette

`node --test test/*.test.js` from `admin` checks navigation permissions and target
configuration. `npm run build -- --outDir <fresh-temp-path>` compiles locally only.
Use `ADMIN_MANAGEMENT.md` for isolated Auth/Firestore emulator tests and launch steps.
Build success is not a production connection, deployed-rule or identity check.

Palette follows mobile `lib/shared/theme/app_theme.dart`: yellow `#FFC72C`, soft yellow
`#FFF3CC`, charcoal `#242424`, muted `#666666`, borders `#E5E5E5`, and white surfaces.
Yellow primary buttons use charcoal text; legacy blue action utilities are neutral.
Existing semantic warning/error/success colors and chart data are preserved. No
layout, record fields, account privileges or workflows were redesigned.
