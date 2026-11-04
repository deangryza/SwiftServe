# SwiftServe public release readiness — Phase 1

Audit date: **4 November 2026, Asia/Manila**. Investigation only; this is not
deployment approval. Only this requested report was created. Existing source,
configuration, dependencies, Firebase projects, credentials and Git history were
not changed. No backend was started, no cloud account/resources were accessed or
created, and no real documents were uploaded. Provider documentation was browsed.

## Decision

**NO-GO for public APK distribution with all current features advertised as working.**
The Express backend is a reasonable container-hosting candidate, but a public URL
alone is insufficient. Release signing, runtime isolation, durable private document
storage, hosted document review, Linux inference validation and release-device
testing remain necessary. New-worker approval also requires integrations that are
not implemented; hosting does not supply them.

Preferred full-backend architecture, conditional on separate billing approval:
**Cloud Run Express API + private object storage + existing Firebase Auth/Firestore
+ static admin/download hosting.** For a no-billing pilot, evaluate Render Free plus
a separately approved free private-storage provider. That is an experimental,
quota-limited pilot, not equivalent uptime/performance or an established secure
full-feature public release. No option is approved or activated by this report.

## 1. Current architecture and verified local findings

| Component | Current local implementation | Release implication |
| --- | --- | --- |
| Mobile | Flutter; Android label SwiftServe; app version 1.0.0+1 | Release APK not built/verified by this audit |
| API | Express 5.2.x, CommonJS; `server.js` loads dotenv, imports app, eagerly loads models, listens on `PORT` or 5000 | Container-compatible shape; startup needs models/native runtime |
| Backend Firebase | Firebase Admin SDK 14.x, Application Default Credentials in normal mode, default Firestore database | Normal config does not explicitly pin/check project; deployment identity must be deliberate |
| Mobile Firebase | Dart options and native Android configuration target `swiftserve-production` | Local config is not proof of deployed rules/settings/permissions |
| Android identity | `com.example.my_app`, namespace same; release uses debug signing config | Choose permanent package and signing identity before distribution |
| Web admin | React 18/Vite 5; `npm run build` produces `admin/dist` | Static host appropriate; API remains separate |
| Face inference | TFjs/WASM 4.22.0, face-api 1.7.15, canvas 3.2.0 | Linux-native canvas, WASM and model packaging unverified |
| Human document review | `document_suitability/{uid}`, owner/session/attempt/digest binding, backend reviewer authorization | Explicitly demo-emulator-only, local image files; not hosted-ready |
| Netlify pilot | serverless-http adapter + Blobs recovery/retention code | Explicitly local-only; cloud build and runtime rejected |
| Privileged admin operations | Backend token/current-role checks, Super Admin-only router, protected legacy accounts and audit writes | Need hosted IAM/identity and negative tests; do not promote accounts |
| Push/expiration | Separate feature gates/functions and local workflows | Remain disabled; API hosting does not activate them |

Existing Phase 6.4A report records a successful local admin build, 46 Flutter tests,
80 backend tests run in separate processes and a clean Flutter analyzer. Those are
**prior local results**, not tests rerun here or release/device/Linux validation.
That report also records shared-mock failures in combined-process testing.

The only APK observed in the output directory was a **debug** APK (149,166,258
bytes). It must not be mistaken for a newly built, signed public release. Release
APK size, merged manifest, certificate and install/update behavior remain unverified.

## 2. Backend hosting and Linux compatibility

### Cloud Run: technically suitable, not ready unchanged

`app.listen(PORT)` already consumes a host-provided port and does not deliberately
bind loopback in the normal entry point. Confirm container IPv4 reachability rather
than assuming the OS's unspecified-address behavior. Cloud Run requires listening
on `0.0.0.0:$PORT`; TLS terminates at the platform, not inside Express.
[Container contract](https://docs.cloud.google.com/run/docs/container-contract).

Future container preparation needs:
- A reviewed Dockerfile and `.dockerignore`; no such production container recipe
  was identified in the inspected repository configuration.
- A pinned supported Node runtime and clean Linux dependency build from lockfile.
  Do not copy Windows node_modules/native DLLs into the image.
- Explicit inclusion of all three model binaries and manifests, plus the selected
  TF WASM assets, without downloading models at runtime. Prior preparation notes
  identify model files as ignored/not explicitly included in the Netlify bundle.
- Startup/readiness checks that include successful model initialization; bounded
  requests, graceful shutdown and safe interruption behavior.
- A conservative initial concurrency (one inference request per instance is a
  proposed test setting), memory measurement and maximum-instance limit. A 1–2 GiB
  test envelope is a planning assumption, not a proven requirement or sizing result.
- Durable object storage. Container-local uploads must be temporary only.
- Keep push/expiration/mock gates off; no background timer inside an API replica.

The three model binaries total **12,417,829 bytes**, excluding manifests, JS/WASM,
native libraries and inference working memory. Phase 6.4A measured about 3.01 s
initialization and 4.74–6.53 s for synthetic no-face attempts on Windows. These do
not predict Linux cold starts or successful biometric inference.

Pinned **canvas 3.2.0** is Cairo-backed. Its versioned documentation lists Linux
x86-64/glibc prebuilds, and Cairo/Pango plus relevant JPEG/PNG support for source
builds. Current upstream main describes different internals/platform coverage;
do not use it as proof for the installed version. Package native dependencies,
fonts and codec support and test synthetic PNG/JPEG processing in the exact target
image. [Versioned canvas documentation](https://github.com/Automattic/node-canvas/tree/v3.2.0).

TF WASM must resolve its actual deployed files through `setWasmPaths`. Test baseline,
SIMD/threaded behavior available in the target runtime, model loads, no-face and
approved synthetic-face paths, concurrency and RSS. **No Linux container build,
native Linux execution or successful-face benchmark was run in this audit.**

### Provider comparison

USD figures below exclude taxes/FX, external services and domain purchases.
Free allowances do not establish a zero-cost operational guarantee.

| Option | Free/billing position | Backend fit and limitations | Storage/frontends |
| --- | --- | --- | --- |
| Google Cloud Run | Usage free allowance, **Cloud Billing required**; overages billed | Best fit for full Express/native/WASM container; scale-to-zero cold starts; CPU/RAM/concurrency need testing | Ephemeral local files; use private object storage; static frontend separate |
| Render Free web service | $0 instance available; no payment required for initial free deploy; quotas can suspend service without payment method | Runs Express; free instance listed as 0.1 CPU/512 MB, sleeps after 15 min; restart can take about a minute; inference viability unproven | Local files lost on sleep/restart/deploy; persistent disk requires paid compute |
| Netlify Free | $0/300-credit hard limit on current credit-based plan; pauses at exhaustion | Existing adapter preserves routes but is local-only. Default Functions 1 GB/60 s; buffered binary uploads effectively about 4.5 MB total | Good static admin/download candidate; Blobs requires hosted adaptation and reviewed limits |
| Vercel Hobby | $0 within quotas; personal/non-commercial restrictions need a suitability decision | Node functions possible with adaptation; 4.5 MB body cap conflicts with two 5 MB uploads; native bundle/inference unverified | Static admin possible; not the preferred full verification backend |
| Cloudflare Pages / Workers Free | Free static tier; Workers Free has 100k requests/day, 10 ms CPU and 128 MB | Not a drop-in host for this native-canvas/Admin-SDK/inference backend | Good static admin; Pages asset cap 25 MiB can block a single APK |
| Firebase Hosting Spark | Free static quotas, no Blaze required for static content within limits | Does **not** execute Express; Cloud Run/Functions rewrites do not remove backend billing requirements | Strong admin/download candidate; public assets only, never identity documents |

Provider evidence: [Cloud Run pricing](https://cloud.google.com/run/pricing),
[Google billing prerequisite](https://docs.cloud.google.com/free/docs/free-cloud-features),
[Render free behavior](https://render.com/docs/free), [Render compute](https://render.com/docs/compute-plans),
[Render free deployment](https://render.com/docs/your-first-deploy),
[Netlify pricing](https://www.netlify.com/pricing/),
[Netlify function limits](https://docs.netlify.com/build/functions/configuration/),
[Vercel limits](https://vercel.com/docs/functions/limitations),
[Vercel Hobby terms](https://vercel.com/docs/plans/hobby),
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/),
[Pages limits](https://developers.cloudflare.com/pages/platform/limits/),
[Firebase Hosting quotas](https://firebase.google.com/docs/hosting/usage-quotas-pricing).

### Illustrative cost assumptions

- Cloud Run request-based free allowance is 180k vCPU-seconds, 360k GiB-seconds
  and 2m requests/month at the documented reference basis, shared across a billing
  account. A hypothetical 1,000 requests × 10 seconds × 1 vCPU/1 GiB gives 10k of
  each resource-second: potentially $0 compute if unused allowance applies.
  Region, cold starts, build/artifact storage, logs, network and object storage are
  additional considerations. This is not an estimate from real user load or a cap.
- Netlify currently meters production deploys at 15 credits, bandwidth at 20/GB and
  compute at 10/GB-hour. Hypothetical 50 downloads of a 100 MB APK use roughly 5 GB:
  100 bandwidth credits plus 15 for one publish, before other traffic/compute.
  Neither that hypothetical APK size nor monthly traffic is measured here. Confirm
  the actual account plan: legacy plans can differ. [Credit plan behavior](https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/credit-based-pricing-plans/).
- Firebase Hosting currently documents 10 GB storage and 10 GB/month transfer at
  no cost; Spark sites can stop serving after transfer quota is exhausted. All
  retained releases count toward storage. Its free static tier does not provide
  private verification storage or an Express process.
- Firestore's free quota includes 1 GiB, 50k reads/day, 20k writes/day, 20k deletes/day
  and 10 GiB/month outbound transfer for one free database. Realtime listeners,
  retries and admin list reads count. TTL deletes/backups are not free features.
  [Firestore quotas](https://firebase.google.com/docs/firestore/quotas).

Small user count alone cannot predict cost. Monitor actual requests, inference
duration, document retention and download traffic. Billing alerts are not a hard
spending ceiling. Do not enable billing or auto-recharge as part of preparation.

## 3. Private verification documents

### Current blockers

`documentSuitabilityService.documentEnvironment()` rejects production/staging,
remote hosts and hosted environment flags. `submit()` requires local storage.
Accepted review evidence is required by the normal verification routes, so simply
hosting `server.js` will leave public verification blocked. This is intentional
fail-closed behavior, not a guard to remove without a reviewed replacement.

Document records expire after 30 days, but inaccessible is not physically deleted.
Local replacement/error cleanup is best effort; no durable physical expiry/orphan
cleanup is established for this document workflow. The mature Netlify pilot's
separate lease/journal/quota reconciliation is not automatically used by it.

Netlify Blobs code restricts project to the demo, uses loopback-only fetch and
local environment names. It cannot be repointed to public storage by one environment
variable. Strong consistency and retryable cleanup are useful reusable concepts,
not proof that hosted authorization/deletion/recovery works.
[Blobs consistency documentation](https://docs.netlify.com/build/data-and-storage/netlify-blobs/).

### Secure options

1. **Private Google Cloud/Firebase Storage bucket with a Cloud Run service identity**:
   natural full-production candidate. No public ACLs/download-token URLs for IDs;
   authorize every backend retrieval by owner or reviewer permission and current
   attempt/expiry. Scope IAM to necessary bucket operations and use lifecycle plus
   metadata reconciliation. Cloud Storage for Firebase now requires Blaze, including
   access to older default buckets under the announced 2026 change. Not approved and
   not a Spark/no-billing solution. [Official storage billing change](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024).
2. **Private Netlify Blobs**: possible future candidate alongside a hosted Netlify API
   or reviewed server-to-server access. Must replace local-only credentials/transport
   with approved scoped host configuration and independent environment namespaces.
   No client store token, public object route or arbitrary-key retrieval. Hosted
   storage capacity/account entitlements and failure handling remain unverified;
   no unlimited/private production storage guarantee is inferred from Free inclusion.
3. **Supabase Free private bucket**: plausible no-billing pilot alternative, not
   implemented. Keep Firebase Auth; backend validates Firebase identity/permissions
   before privileged storage operations. Do not assume Supabase RLS understands a
   Firebase token without deliberate integration. Free pricing lists 1 GB files,
   5 GB egress, two active projects and pausing after one inactive week. It adds
   another operator, secret and retention boundary; hosted behavior/card requirements
   for this user's account were not verified. [Pricing](https://supabase.com/pricing),
   [private buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals).
4. **Cloudflare R2 Standard private bucket**: durable alternative with 10 GB-month,
   1m Class A and 10m Class B monthly free allowances and no internet egress fee.
   It requires an R2 subscription/billing setup; do not equate it with a no-billing
   service. Overage storage is listed at $0.015/GB-month plus operation charges.
   New adapter/credentials and security tests required. [Pricing](https://developers.cloudflare.com/r2/pricing/),
   [subscription setup](https://developers.cloudflare.com/r2/get-started/).

For perspective, 50 retained attempts with two 5 MB images need about 500 MB before
retries/replacements/backups. This is a sizing assumption, not actual stored data.
Quota exhaustion must reject safely, not fall back to public URLs or container disk.

Any chosen storage implementation needs immutable server-generated keys; exact
owner/session/attempt/digest binding; MIME/header/decoded-dimension validation;
bounded uploads/concurrency; no-store authenticated responses; expiration recheck
before returning bytes; durable interrupted-upload/deletion recovery; fenced cleanup
acknowledgment; orphan/quota/diagnostic retention; separate stage/prod namespaces;
and auditable reviewer access. Retention/consent/incident-response policy needs
separate review before collecting real identity documents. Do not store images as
Firestore base64 to evade durable-storage requirements or mix them with public APKs.

## 4. API and emulator inventory

No verified deployed HTTPS SwiftServe API was identified in inspected source/config.
This does not prove that no external account has a deployment; account inventory,
DNS, live environment and hosting dashboards were not accessed.

| File/area | Current local target or restriction |
| --- | --- |
| `mobile/my_app/lib/shared/config/api_config.dart` | `API_BASE_URL`, default `http://127.0.0.1:5000` |
| `admin/src/lib/api.js`, current admin `.env` | `VITE_API_BASE_URL`, current/default `http://localhost:5000` |
| `admin/src/lib/firebaseTarget.js` | Loopback allowed even for normal cloud Auth; needs explicit release HTTPS/origin validation |
| `mobile/my_app/lib/shared/services/firebase_bootstrap.dart` | Debug-only loopback/10.0.2.2 demo Auth 9099, Firestore 8187, Functions 5001 |
| `admin/src/lib/firebase.js` | Demo Auth loopback ports 9099, 9599 or 9499; DEV-gated |
| `swiftserve-backend/src/app.js` | Netlify CORS loopback 8888/5181; normal CORS unrestricted |
| `scripts/startStaging.js` | Loopback 5002; staging-only |
| `scripts/startAdminDemo.js` | Loopback 5003; demo-only |
| `scripts/startLiveAdminReadOnly.js` | Loopback API 5004/admin 5182; local operator Firebase CLI credential flow |
| `scripts/startNationalIdMock.js` | Loopback 5007; mock-only |
| `scripts/startNetlifyPilot.js`, `netlify.toml` | Local API 8888/admin 5181; demo Auth 9599/Firestore 8288 |
| `mobile/my_app/tool/prepare_android_staging.dart` | Generates debug command with API loopback 5002 |
| `mobile/my_app/tool/prepare_android_expiry_demo.dart` | Debug loopback API 5006 |
| `firebase.admin-emulators.json` | Auth 9499, Firestore 8188, hub/logging 4488/4588 |
| `firebase.netlify-emulators.json` | Auth 9599, Firestore 8288, hub/logging 4498/4598 |
| `mobile/my_app/firebase.local.json` | Auth 9099, Firestore 8187, Functions 5001, hub/logging 4487/4587 |
| `android/app/build.gradle.kts` | Debug-only adb reverse of port 5000; not a public backend |

Inventory covers inspected active app/config and local launcher paths, not every
historical test fixture/archive/log string. Preserve emulator endpoints for development;
exclude them through deliberate release entry points/config, not global replacement.
SDK Google/Firebase service URLs are legitimate external endpoints, not SwiftServe API
hosting. `routingService.js` uses HTTPS OpenRouteService; map tiles use OpenStreetMap;
Flutter geocoding uses the installed native geocoding plugin. These have their own
quotas/terms/privacy considerations. No secret routing-key value was read or printed.

## 5. Firebase and Android identity/signing coordination

Default Android/Dart project is `swiftserve-production`; staging native config exists
under `config/firebase/staging`. Firebase CLI project selection does not determine
Admin SDK ADC targeting. Future backend must require an exact expected project and
`(default)` database, reject emulator variables in hosted mode, and verify the actual
initialized target before accepting traffic. Never use local Firebase CLI refresh
credentials from `liveAdminReadOnly.js` as a hosted server credential.

Cloud Run should use a dedicated attached service identity, not downloaded private
keys or broad Editor/Owner permissions. Review exact Firestore data, bucket-object,
Auth user-management and token-verification permissions. Admin Management needs
privileged Auth operations, so consider a separate admin API identity/service from
ordinary user/inference endpoints. Admin SDK bypasses Firestore rules; every API
must enforce its own permissions. Third-party hosts require approved workload
identity federation or tightly scoped server-only credentials; no preapproved
keyless mechanism is assumed for Render/Netlify. Never put secrets in VITE_* or Dart
defines, which are client-visible.

If changing `com.example.my_app`, coordinate as one separately approved change:
1. Pick a permanent reverse-domain package and release keystore ownership/backup.
2. Register a **new Firebase Android app** for the chosen package in each intended
   project; Firebase does not rename an existing registered package.
3. Coordinate applicationId/namespace and Kotlin activity package/path; download
   matching google-services.json and regenerate matching Android Dart options.
4. Register release SHA-1/SHA-256 fingerprints, check Google OAuth client/Web client
   coordination and sign-in. Preserve existing Firebase users/UID-based records.
5. Configure/test App Check for that package/certificate and APK distribution method.
6. Test install, Google/email login, profile access, upgrade and logout on a phone.

Changing package creates a distinct installed Android app; changing signing identity
can break upgrades of the existing package. Public users must receive updates signed
with the same approved release identity. The repository has no `android/key.properties`
at the inspected path; this does not prove no keystore exists elsewhere. No key was
searched for, created or read. [Firebase package registration](https://firebase.google.com/docs/android/setup).

Release manifest includes INTERNET/CAMERA/coarse/fine location/POST_NOTIFICATIONS;
label/icon references exist. Adaptive launcher foreground uses 0% inset. Debug
manifest permits cleartext, normal release manifest does not explicitly permit it.
Use approved HTTPS, not a release-wide cleartext exception. Merged release manifest,
native dependency compatibility, APK signing verification and device icon appearance
still need actual release-build tests. Working SDK constraints were previously
Flutter 3.38.3/Dart 3.10.1 compatible; no build was attempted here.

Production App Check enforcement/authorized domains/fingerprints were not accessed.
The inspected staging helper is debug-only; it is not a production App Check rollout.
Play Integrity supports distribution outside Play but requires appropriate settings;
do not assume a sideloaded APK satisfies store-recognition verdicts or distribute a
debug bypass. [App Check outside-Play support](https://firebase.google.com/docs/app-check/android/play-integrity-provider).

## 6. Admin and download site

The admin can be static-hosted after an approved build-time Firebase/public HTTPS API
configuration. SPA navigation needs index.html rewrites; `/api/*` must reach the real
API before fallback. Add approved security headers/CSP, restricted CORS, suitable
cache policies and authorized Auth domain coordination. Do not publish `.env`, server
keys, local logs, identity uploads or source credential files with static assets.

`netlify.toml` deliberately throws during cloud builds. Keep it intact until a reviewed
host-specific configuration is separately authorized. The current Netlify runtime,
hardcoded localhost source-IP bucket and loopback Blobs transport are local test
mechanisms, not production proxy/rate-limit configuration. `hostedStagingTarget.js`
is inactive and not wired into Firebase initialization; normal frontend validation
currently only accepts production cloud config or DEV demos. Hosted staging needs
explicit wiring and tests, not a production-target fallback.

Recommended download site: public HTTPS landing page with version/date, APK size,
SHA-256 checksum, signing-certificate fingerprint, install/update instructions,
privacy/support links and a QR code pointing to the stable HTTPS download page.
No QR/download website was implemented or deployed in this phase. Generate the QR
locally after approving its URL; avoid paid dynamic-QR dependencies.

Use Firebase Hosting or a suitably limited static host for the APK. Cloudflare Pages
allows a maximum 25 MiB per asset; actual release APK size is unknown. The observed
debug APK exceeds that limit. Keep public downloads and private verification objects
in separate sites/buckets/access boundaries. HTTPS and checksums complement, rather
than replace, release signing. Review current Android developer-verification rules
for intended regions/devices: official guidance describes a 2026 regional rollout
and wider 2027 rollout; limited free distribution accounts describe up to 20 devices,
so they must not be assumed to cover 20–50 classmates.
[Android distribution guidance](https://developer.android.com/developer-verification).

## 7. Security blockers and release gates

### Critical/high
- **Hosted document workflow is intentionally unavailable.** Add a separately reviewed
  hosted project/storage policy retaining binding and human authorization; do not
  remove the demo guard and call that production readiness.
- **New worker approval is incomplete by policy.** `workerVerificationPolicy.js`
  requires official PSA evidence and trusted server-side liveness, neither supplied
  by the normal workflow. A strong face match/admin acceptance cannot approve new
  workers. Preserve legacy workers and decide launch scope/provider approvals; no
  bypass or simulated official verification.
- **Private disk is not durable hosting storage.** Finish authenticated durable object
  storage and deletion/recovery before collecting real documents.
- **Release identity/API absent.** Debug signing, example package and loopback API
  are not the intended permanent public configuration.
- **Normal backend target is implicit.** Add fail-closed exact project/database and
  credential-environment validation rather than relying on ADC discovery.

### High/medium hardening required
- `authMiddleware.js` checks revocation in pilot mode only; normal user routes use
  verifyIdToken(token) without revocation checking. Admin and document-review paths
  add stronger checks. Review disabled/revoked user behavior across public routes
  without assuming protection is uniform.
- Normal `app.js` uses unrestricted CORS; pilot allowlist is local-only. Scope browser
  origins to approved HTTPS admin sites; CORS is not authentication and native apps
  do not provide a browser origin. Configure trusted proxies narrowly; never copy
  the pilot's fixed loopback source-IP rewrite into hosting.
- Rate limits are process-local. Autoscaling/restarts can reset or multiply them.
  Budget inference concurrency, uploads, request bodies/timeouts and admin/user
  operations. Registration availability is already limited (30/minute) but its
  intentional account-availability disclosure still needs abuse/privacy review.
- `testRoutes.js` exposes authenticated decoded-token claims through a diagnostic
  endpoint; remove from a future public deployment or replace with minimal diagnostics.
  Generic error logging in `app.js` should be reviewed for private payload/URL leakage.
- Audit hosted admin privileges, provisioning interruption recovery, self-change and
  legacy/Super Admin protections. Existing managed-admin edit paths refuse changes
  to Super Admin/legacy accounts; do not infer a generally implemented editable
  last-Super-Admin workflow or change allowlists/claims here.
- Compare local/deployed rules and indexes later with explicit read-only cloud access
  approval. No deployed rules were inspected now. Local worker verification writes
  are backend-only; local document suitability has no dedicated client allow rule.
  That does not validate every current production authorization path.
- Current dependency advisory status, secret scan, Linux image scan and supply-chain
  licence review were **not rerun**. Prior known rules/date-picker and combined-mock
  test failures require triage; do not assume all pre-existing failures are harmless.
- App Check, Google OAuth release fingerprints, authorization revocation, upload
  abuse, image retention and actual device behavior need end-to-end staging tests.
- Push and scheduled expiration remain disabled. Public API hosting does not notify
  users while offline or activate Cloud Functions. Those require separate approval,
  deployment/billing assessment and testing; do not advertise them as activated.

## 8. Exact files requiring future changes or coordination

Conditional plan, not permission to edit all listed paths:

| Area | Existing files | Proposed future work |
| --- | --- | --- |
| Container/runtime | `swiftserve-backend/server.js`, `package.json` | Startup/health/shutdown/runtime pinning; preserve model behavior |
| New container files | proposed `swiftserve-backend/Dockerfile`, `.dockerignore` | Exclude secrets/uploads/node_modules; package verified Linux artifacts |
| Backend target | `swiftserve-backend/src/config/firebase.js` | Exact project/database preflight and hosted service identity |
| API hardening | `src/app.js`, `src/middleware/authMiddleware.js`, `src/routes/testRoutes.js` | CORS/proxy/limits/logging/revocation/diagnostic review |
| Private storage | `src/services/verificationStorageService.js`, `documentSuitabilityService.js`, `netlifyVerificationStorage.js`, `src/routes/documentSuitabilityRoutes.js` | Explicit selected-host adapter, hosted guard, private access and durable cleanup |
| Binding/inference integration | `src/routes/verificationRoutes.js`, `src/controllers/adminVerificationController.js`, `src/services/faceVerificationService.js` | Only if chosen storage integration needs it; no model/policy changes |
| Admin deployment | `admin/src/lib/api.js`, `firebaseTarget.js`, `hostedStagingTarget.js`, `firebase.js`; host configuration | Explicit HTTPS release/stage configuration, redirects and headers |
| Public environment templates | `admin/.env.example`, `swiftserve-backend/.env.example` | Document names/default-off gates only; never commit secret values |
| Netlify option only | root `netlify.toml`, `swiftserve-backend/netlify/functions/api.js`, `src/config/netlifyPilot.js` | Separate hosted design retaining current local pilot safeguards |
| Android | `mobile/my_app/android/app/build.gradle.kts`, `android/app/src/main/kotlin/com/example/my_app/MainActivity.kt`, `lib/shared/config/api_config.dart` | Approved identity/signing and fail-closed public API configuration |
| Firebase client coordination | `android/app/google-services.json`, `config/firebase/staging/google-services.json`, `lib/firebase_options.dart`, `lib/shared/services/firebase_bootstrap.dart`, `staging_app_check.dart` | Only matching approved app registrations/certificates and explicit environments |
| Secrets outside Git | future `android/key.properties` and external release keystore | Create only after signing approval, secure backups; not static/bundle inputs |
| Tests | backend storage/auth/review tests; admin Firebase-target tests; Flutter Android config/verification tests | Hosted-stage isolation, exact bytes/attempts, private storage, release sign-in |
| Download site | proposed `download-site/` plus selected host config | Landing page/QR/checksum after URL/APK approval; path is proposed, absent today |

Backend table paths beginning `src/` are relative to `swiftserve-backend`; admin table
library names are relative to `admin/src/lib`. Policy changes, migrations, existing
user records and production rules are deliberately outside this proposed file work.

## 9. Recommended implementation sequence and separate approvals

1. Approve launch scope: public worker onboarding cannot be described as fully
   verified without mandatory government/liveness evidence. Preserve policy.
2. Choose budget boundary: billing-enabled full container stack versus no-billing,
   limited pilot. Choose object storage and region/retention/access design.
3. Approve local-only container/hosted-target/storage code work and necessary isolated
   Linux tooling/dependency installation, if required. Test with synthetic fixtures
   and demo emulators first; do not boot or install system tooling implicitly.
4. Approve permanent Android package and signing plan; only then create/secure keys.
5. Approve staging-only resources/IAM/credentials and provider account/billing setup
   as separate actions. Production remains unchanged. Hosted preparation is not
   deployment permission.
6. Deploy isolated hosted staging only after explicit approval. Verify exact target,
   HTTPS, Google/email sign-in, revoked/disabled users, private review, stale attempts,
   role separation, image limits, storage failure/restart/deletion recovery and costs.
7. Build a signed staging APK and test on physical phones off USB and outside the
   development LAN, including process restarts and updates. Measure memory/latency.
8. Resolve remaining security/test findings; inspect deployed production configuration
   only with explicit approval. Plan rollback, alerts, key recovery and incident handling.
9. Obtain separate production deployment/configuration approval, then separate release
   distribution approval. Publish approved APK/checksum/download page/QR only after
   verifying the hosted flow. Do not silently enable push, schedules or billing.

## 10. What remains unverified

No cloud account inventory, production/staging settings, deployed API, Linux build,
hosted native/WASM inference, current advisory audit, real ID processing, physical
release-device test, public load test, private hosted storage lifecycle or release
APK certificate was verified in this audit. Previous Windows/synthetic tests cannot
establish those facts. Local source checks and official provider documentation
support this plan; all implementation and activation steps remain separately gated.
