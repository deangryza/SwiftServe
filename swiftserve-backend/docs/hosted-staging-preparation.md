# Hosted staging preparation — inactive, local only

This is a design and test checklist, not deployment authorization. No system
components, cloud resources, credentials, accounts, claims, IAM bindings, rules,
API URLs or billing settings were created or changed. No production/staging data
was accessed. Keep the current Netlify build failure and demo-only runtime guards.
Push, scheduled cleanup and automated face verification remain disabled.

## Current local evidence

- Windows x64 / Node 24; Chrome and Edge installed.
- Docker/Podman are not on PATH. WSL executable exists but reports WSL is not installed.
- VirtualBox 7.2.6 exists. Registered guests include Parrot and Window XP; neither
  was running. Read-only Parrot showvminfo failed with E_FAIL/VBOX_E_VM_ERROR.
  No guest was booted, cloned, repaired or modified. A guest name is not proof of
  its OS, health, installed dependencies or suitability for Netlify runtime tests.
- Installed canvas 3.2.0 is Windows-native (MZ binary plus Windows DLLs), not a
  Linux deployment artifact. Local WASM binaries and model files exist. Models
  are ignored by Git and not covered by an explicit Netlify included_files rule.
- Browser connector reported its access host unavailable. Native Windows browser
  automation could open a dedicated tab and enter localhost:8888, but was stopped
  by its safety check because the current URL could not be confidently determined.
  No login, account mutation, credential entry or completed browser test occurred.
  Do not bypass this restriction or substitute a production browser tab.
- The new inactive frontend validator and existing frontend tests: 12 passed,
  0 failed. No cloud connection is needed for these pure validation tests.

## Linux path and acceptance checklist

Safest first choice is an existing, explicitly approved Linux guest with a fresh
test workspace, no host credentials and no writable production workspace mount.
VirtualBox is already installed, so inspection/use of a suitable guest might avoid
installing WSL/Docker. Approval is still required before booting/modifying an
existing user VM, repairing it, installing guest software or importing a new guest.
If no guest is suitable, choose an approved disposable Linux VM or WSL2/container
setup; installations can enable Windows features, consume disk/RAM and require a
reboot. None is approved by this document.

Linux tests must use a fresh dependency installation in that isolated workspace;
never copy Windows node_modules/canvas.node into the Linux artifact. Match the
future Netlify Node runtime, CPU architecture and glibc environment. Exact hosted
runtime compatibility still needs verification; a generic Linux pass is insufficient.

| Check | Required evidence before hosting | Current state |
| --- | --- | --- |
| Native canvas | Clean Linux install from lockfile; require canvas; encode/decode synthetic PNG and JPEG; verify dimensions | Blocked: no running Linux environment |
| Shared libraries | Inspect canvas.node with file/ldd; no missing libraries; Cairo/Pango and JPEG/PNG support; fonts and optional codecs understood | Unverified |
| Native install policy | Reviewed prebuilt artifact or reproducible source build; no broad unreviewed lifecycle scripts | Unverified |
| WASM assets | Enumerate wasm, simd and threaded-simd binaries in final bundle; validate runtime-relative setWasmPaths resolution | Present locally; bundle unverified |
| Face models | Inventory the six manifest/bin files used by faceVerificationService; validate hashes/provenance/license; explicit asset inclusion if inference is ever approved | Local ignored files; not a deployable model package |
| Lazy loading | Ordinary admin requests do not initialize canvas/models; manual uploads decode synthetic images only; /api/verify remains unavailable | Previously verified on Windows; Linux pending |
| Functions bundle | Build locally from isolated copy, inspect archive, then invoke extracted handler locally; no absolute Windows paths or DLL dependency | Windows works; Linux pending |
| Resource limits | Measure cold/warm time, RSS/peak memory, concurrent uploads and slow SDK calls; record Node/base image/architecture | Hosted/Linux measurements absent |
| Negative paths | Missing models/WASM/native module return safe failures and do not auto-approve verification | Required before Linux acceptance |

For a future approved guest, use synthetic fixtures and deny cloud network access.
Backend/API tests must use demo Firebase emulators. Guest localhost is not Windows
localhost: use a dedicated emulator pair inside the guest or a reviewed local port
mapping. Do not silently weaken loopback-only production-isolation guards.

Provider defaults currently document 1024 MB memory, 60-second synchronous timeout,
6 MB buffered request/response and about 4.5 MB effective binary payload. Local
limits remain 4 MiB decoded request body and two files of at most 1.5 MiB each,
16–2048 pixels per side / 4 million pixels. Validate multipart/base64 overhead and
malformed inputs. The 45-second cleanup boundary budget does not cancel an SDK
operation already running. No automatic face inference or scheduling is permitted.

Source: https://docs.netlify.com/build/functions/configuration/

## Explicit frontend target design — not activated

`admin/src/lib/hostedStagingTarget.js` is a pure, inactive validator. It is NOT
imported by firebase.js, firebaseTarget.js, api.js, Vite configuration or any entry
point. Existing production and emulator behavior is unchanged. There is no new
active .env file, hostname, web app, API endpoint or deployment configuration.

The draft requires all of these, with no default/fallback:

| Build input | Required value |
| --- | --- |
| VITE_SWIFTSERVE_TARGET | hosted-staging |
| VITE_FIREBASE_PROJECT_ID | swiftserve-staging-2026 |
| VITE_FIRESTORE_DATABASE_ID | (default) |
| VITE_USE_FIREBASE_EMULATORS | false |
| VITE_FIREBASE_AUTH_DOMAIN | swiftserve-staging-2026.firebaseapp.com |
| VITE_API_BASE_URL | Exact separately approved HTTPS staging site origin |
| approvedOrigin validator argument | Reviewed build constant; absent means reject |

It rejects production/unknown/missing project IDs, missing/other databases,
emulator ambiguity, wrong Auth domain, absent/unapproved API hosts, credentials in
URLs, paths/queries/fragments, loopback URLs and non-HTTPS endpoints. The synthetic
example.test origin used in tests is never contacted and is not an approved site.

Future wiring requires a separate reviewed staging-only entry/build path. Before
SDK initialization, validate the target and require all real staging web SDK
configuration. Do not invent an app ID or reuse Android config as web config.
Use a separately named Firebase app; reject an existing app with a different
project. Staging apiRequest must use the validated URL directly, without the
existing localhost:5000 fallback. Keep the production path unchanged.

The frontend currently only uses Firebase Auth directly; Firestore work is through
the API. A frontend database variable does NOT enforce the backend database or IAM.
Backend startup must independently require all three project environment variables
to equal swiftserve-staging-2026 and FIRESTORE_DATABASE_ID=(default), then construct
the actual Firestore client with explicit projectId/databaseId. Reject emulator
hosts, ambient production ADC, alternate credentials and unsafe feature gates in
hosted mode. Do not reuse current local stagingFirebase.js: it intentionally loads
a developer Firebase CLI refresh token for port 5002, which is unsuitable for hosting.

## Proposed hosted environment contract — documentation only

No values in this table are set by this document. Placeholders are not runnable
configuration. Existing NETLIFY_DEV/demo checks must stay intact; a hosted adapter
and bootstrap require a separate reviewed change rather than a bypass flag.

| Scope | Variables/design | Handling |
| --- | --- | --- |
| Public build | VITE_* inputs above; genuine staging web API key/appId/senderId | Public Firebase config only; verify they belong to staging; never put privileged secrets here |
| Server target | GOOGLE_CLOUD_PROJECT, GCLOUD_PROJECT, FIREBASE_PROJECT_ID = swiftserve-staging-2026; FIRESTORE_DATABASE_ID=(default) | All explicit and cross-checked |
| Hosted mode | Proposed SWIFTSERVE_HOSTED_STAGING=true, approved site ID/origin and deploy-context allowlist | Not implemented/activated; reject unknown site/context and previews |
| Local mode flags | NETLIFY_DEV and SWIFTSERVE_NETLIFY_PILOT must not be used to authorize cloud execution | Retain current demo path separately |
| Safety gates | EXPIRED_JOB_CLEANUP_ENABLED=false; EXPIRED_JOB_CLEANUP_DRY_RUN=true; PUSH_DELIVERY_ENABLED=false; ACTIVITY_PUSH_ENABLED=false; EXPIRY_PUSH_ENABLED=false | Mandatory exact values; also keep ENABLE_PUSH_NOTIFICATIONS=false if introduced |
| Storage | VERIFICATION_STORAGE=netlify-blobs; staging-specific store and key namespace | Requires new staging adapter; current adapter rejects all cloud transports |
| CORS | Exact approved site origin; method/header allowlist; authenticated no-Origin tools only as reviewed | Current local origins are not a hosted allowlist |
| Runtime | Explicit supported Node version and verified Linux artifact | Not set in current config |
| Server credentials | Dedicated staging service identity and approved runtime credential method | Function-only secret scope; never build/browser/preview scope |
| Super Admin | No UID/claim/allowlist changes in this phase | Staging identity activation requires explicit approval; never copy production UID |

### Credentials and IAM

Prefer short-lived workload identity if Netlify Free Functions actually provides a
supported runtime OIDC identity and refresh mechanism. This investigation did NOT
verify such a Netlify runtime facility. Build-only federation is not a Functions
runtime credential. Do not promise keyless support, reuse another host's OIDC docs,
or create a federation provider as a shortcut.

If runtime federation cannot be verified, a dedicated staging service-account key
would require separate explicit security approval, creation, rotation/revocation
procedures, function-only secret storage and testing. No key was created/read here.
Do not copy developer CLI refresh tokens, ADC files or production keys to Netlify.
Never grant a staging identity production-project access. Firebase CLI project
selection does not constrain Admin SDK credentials or their resource targets.

Review a custom IAM role before broader predefined roles:

- Firebase Auth: firebaseauth.users.get (lookup/list/revocation checks),
  firebaseauth.users.create and firebaseauth.users.update (managed-admin setup,
  disable/restore, refresh-token revocation and staff claims). Do not grant user
  deletion, Auth config mutation, secret/hash export or project administration.
- Firestore candidate permissions: datastore.databases.get for transaction APIs;
  datastore.entities.get/list/create/update/delete for the API and private cleanup.
  Verify SDK needs in isolated hosted staging; emulators do not enforce IAM.
- roles/datastore.user is broader than a minimal custom role. If approved, scope
  it to the staging project/default database with supported IAM conditions, and
  test those conditions. IAM is not collection-level Firestore Rules enforcement.
- No Owner/Editor, Firebase Admin blanket role, billing, IAM administration, Storage,
  FCM, Scheduler or Functions deployment rights. Token Creator is not needed merely
  to verify Firebase ID tokens; any federation/impersonation grant needs separate review.

Admin SDK bypasses Firestore Rules. Server authorization, current account checks,
permission checks, immutable audit API behavior and project-scoped IAM are all
required. IAM cannot substitute for per-user ownership checks.

Sources:
- https://docs.cloud.google.com/iam/docs/roles-permissions/firebaseauth
- https://docs.cloud.google.com/firestore/native/docs/security/iam
- https://firebase.google.com/docs/admin/setup

### Blobs, secrets and site isolation

Use a separate Netlify site for hosted staging, never a preview context on a
production site. Blobs stores are site-scoped; contexts on one site are not a
security boundary. Use a new versioned staging store and project/environment key
prefix. Do not reuse demo assets, production objects or private credentials.

Use the provider's server-side Functions context for site-bound Blobs access; no
browser PAT or arbitrary-key endpoint. Bind to the approved site ID and reject
other deploy contexts. Strong reads plus Firestore journal ownership checks remain
required. Strong consistency does not make a Firestore/Blobs transaction atomic.

Keep no-store/nosniff responses, bounded upload policy, quota reservation before
decode, current Auth/permission checks and server-generated object keys. Review
storage inventory recovery, quarantine, leases, retry/backoff, seven-day tombstones
and two-day quota removal from netlify-free-pilot.md. Keep minimal failed-deletion
recovery records until acknowledgment; do not discard them by age. Cleanup remains
manual, so outages/free-plan suspension can delay physical deletion indefinitely.
Real identity images remain prohibited.

Server secrets must be Functions-only, excluded from public VITE_*, static assets,
Git, source maps, logs, diagnostics, command output and deploy previews. Do not
log raw SDK error/request objects. Separate build and runtime credentials; no
production SDK bootstrap in build scripts. Review token refresh across warm
invocations. A hosting account operator may access stored Blobs: limit platform
account access as well as application access.

Source: https://docs.netlify.com/build/data-and-storage/netlify-blobs/

## Free-plan limits and cost risks

Published rates checked during this preparation (not an account-specific promise):

| Meter | Current published rate |
| --- | --- |
| Netlify Free | 300 shared credits/month; hard limit |
| Successful production deploy | 15 credits |
| Functions compute | 10 credits / GB-hour of allocated memory × execution time |
| Bandwidth | 20 credits / GB |
| Web requests | 2 credits / 10,000 requests |

A staging site's primary published URL still uses a production deployment in
Netlify terminology; calling the environment staging does not waive that meter.
Preview deploys may be free to create but their traffic/compute still consume usage.
No standalone per-byte/per-operation Blobs budget was verified; do not infer
unlimited free private storage. Validate actual Blobs accounting before approval.

Illustrative monthly estimate: two published deploys (30), one GB outbound (20),
100,000 requests (20), and 10,000 one-second invocations at 1 GB (27.8) = about
97.8 credits, excluding other account projects, Blobs-specific accounting, retries,
build features and cold starts. This is not measured SwiftServe usage. Image
downloads, repeated scans, idle retries and abuse can exhaust the pool.

Free hard limits prevent Netlify overage charges, but exhaustion can pause every
account project until reset. Do not attach payment, upgrade plan or enable paid
add-ons/auto-recharge. Exact account eligibility and limits are unverified here.

Firestore has one free database/project: 1 GiB storage, 50k reads/day, 20k writes/day,
20k deletes/day and 10 GiB outbound/month. Quotas reset around midnight Pacific.
Checkpoint transactions, permission refreshes, list pages and cleanup retries
consume reads/writes. Keep Spark: quota exhaustion must fail safely rather than
trigger a billing upgrade. Do not use Firestore TTL/PITR/backups/cloning as a free
cleanup solution; those require billing. New Firebase Functions or GCS storage
are not part of this design. No billing account is approved.

Sources:
- https://www.netlify.com/pricing/
- https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/how-credits-work/
- https://firebase.google.com/docs/firestore/pricing

## Browser scenario preparation

Run only the existing demo frontend at http://localhost:8888 using pilot:dev and
the dedicated local Auth/Firestore listeners (9599/8288). Wait for Loaded function
api as well as the ready banner. Never enter production credentials. No Playwright
or Cypress harness was found in the admin/backend dependencies. Browser tests
below are planned, NOT completed in this phase. Pure unit tests passed separately.
The prior phase's HTTP/emulator results do not prove browser interaction.

| Scenario | UI steps | Expected result / evidence |
| --- | --- | --- |
| Unauthorized entry | Signed out, open /dashboard/administrators directly | Redirect/login; no directory/private images rendered |
| Super Admin login | Use existing synthetic super-netlify@example.test fixture; enter disposable fixture password privately; do not save it in browser | Emulator warning, successful API session, correct navigation; never cloud Auth |
| Listing | Open Admin Management; filter name/role/status; Refresh | Real demo records, stable IDs, loading/empty/error states; protected accounts have no edit control |
| Creation (future approval) | Create Admin; validate name/email/password; select reports.manage | Only staff authority, reports.view added, no plaintext password in records/audit; double-click does not silently duplicate |
| Setup recovery (future approval) | Synthetic provisioning fixture; Retry setup | Confirmation; recover only managed incomplete setup; ordinary users cannot be promoted |
| Permissions (future approval) | Edit access; add/remove module; save | Permissions change on next request; regular admin cannot reach forbidden module by URL or API |
| Deactivate/activate (future approval) | Change status; confirm; try old session; restore | Old token rejected; inactive access denied; fresh login after restore; concurrent edits return conflict |
| Self/Super/legacy protection | Inspect protected row controls; attempt API tests separately with synthetic fixtures | No self privilege change; no Super Admin/legacy edit/deletion; last Super cannot be removed through this API |
| Audit | View activity log / per-actor Activity; Close activity | Read-only last 100, correct actor/action/target/time; regular admin forbidden; no password/token contents |
| Verification images | Open /dashboard/verification; select an existing synthetic pending submission; inspect document and selfie | Correct separate images via authenticated requests; no public object URLs; no-store; no auto-verification |
| Verification denial | Worker/staff without verification.view, expired image, forged query key | No bytes; correct 401/403/404/400; no raw exceptions |
| Synthetic upload/recovery (future approval) | Existing local HTTP uploader or isolated synthetic fixture | Exactly two validated images; owner binding; interrupted save/delete recovered; no real IDs |
| Resilience | Simulate local API offline/timeout; keyboard-only navigation; narrow viewport | Clear error/retry, no success before server confirmation, focus visible, no overflow/private stale content |

Do not run account-creation, activation/deactivation, permission/claim mutations or
image approval actions in this preparation phase. They need specific approval or
an explicitly authorized isolated emulator test phase. Login/list/navigation can
use existing demo fixtures when the browser safety system can verify the local URL.
Browser automation stopped before login in this run; do not bypass its URL check.

## Approval gates / next actions

1. Approve inspection/use of the powered-off Linux guest, or choose/approve a
   disposable Linux installation. Identify disk/RAM/Windows feature/reboot effects.
2. After a working Linux environment exists, run the checklist in an isolated copy,
   using fresh Linux dependencies, synthetic images and demo emulators only.
3. Approve a separate local implementation to wire hosted-staging validators,
   bootstrap, named Firebase app, same-origin API, strict CORS, site/context guards
   and server credential interface. Keep production behavior unchanged.
4. Decide whether to approve runtime federation investigation or a dedicated
   staging key with rotation policy. No creation/configuration is authorized yet.
5. Approve browser access once URL verification works, and separately authorize
   mutating synthetic test scenarios as needed. Do not use production tabs/accounts.
6. Resolve/accept remaining dependency findings: six runtime moderate entries;
   previous full audit includes 21 moderate + 2 low across dev/runtime. No high
   entries remained after the compatible fixes. Re-audit before any hosting approval.
7. Only after these checks, request separate approval for site/web-app creation,
   credentials/IAM/configuration, rules/index changes if needed, and deployment.
   None is authorized by this preparation. No billing, push or scheduling activation.
