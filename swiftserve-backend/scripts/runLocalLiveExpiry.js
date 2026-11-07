// Owner-approved local computer runner. No cloud deployment, daemon installation,
// dotenv, ADC key files, Auth mutation, FCM sender or production global gate edits.
const path = require('node:path');
const { createRequire } = require('node:module');
const PROJECT = 'swiftserve-production';
const SETTINGS = '_jobExpiryControl/localComputerSettings';
const root = path.resolve(__dirname, '../..');
const sdk = createRequire(path.join(root, 'mobile/my_app/functions/package.json'));

function options(args) {
  const allowed = new Set(['--preview', '--run-live', '--stop-live', '--once', `--confirm-project=${PROJECT}`]);
  if (args.some(arg => !allowed.has(arg)) || new Set(args).size !== args.length) throw new Error('INVALID_ARGUMENTS');
  const modes = ['--preview', '--run-live', '--stop-live'].filter(arg => args.includes(arg));
  if (modes.length > 1) throw new Error('SELECT_ONE_MODE');
  const mode = modes[0] || '--preview';
  if (mode !== '--preview' && !args.includes(`--confirm-project=${PROJECT}`)) throw new Error('EXPLICIT_LIVE_PROJECT_CONFIRMATION_REQUIRED');
  return { mode, once: args.includes('--once') };
}
function validateEnvironment(env) {
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST', 'FUNCTIONS_EMULATOR',
    'FIREBASE_CONFIG', 'GOOGLE_APPLICATION_CREDENTIALS', 'SWIFTSERVE_SUPER_ADMIN_UIDS']) {
    if (env[key] !== undefined) throw new Error('LIVE_UNSAFE_ENVIRONMENT');
  }
  for (const key of ['GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT', 'FIREBASE_PROJECT_ID', 'EXPIRY_EXPECTED_PROJECT']) {
    if (env[key] && env[key] !== PROJECT) throw new Error('LIVE_PROJECT_MISMATCH');
  }
  if (env.FIRESTORE_DATABASE_ID && env.FIRESTORE_DATABASE_ID !== '(default)') throw new Error('LIVE_DATABASE_MISMATCH');
  if (env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('LIVE_TLS_REQUIRED');
  for (const key of ['EXPIRED_JOB_CLEANUP_ENABLED', 'PUSH_DELIVERY_ENABLED', 'EXPIRY_PUSH_ENABLED',
    'ACTIVITY_PUSH_ENABLED', 'EXPIRY_TOKEN_REGISTRATION_ENABLED', 'SWIFTSERVE_NETLIFY_PILOT', 'SWIFTSERVE_STAGING']) {
    if (env[key] && env[key] !== 'false') throw new Error('LIVE_UNEXPECTED_GLOBAL_GATE');
  }
}
function sweepOptions(db, shouldStop = () => false) {
  return { db, shouldStop, settingsDocument: 'localComputerSettings', env: {
    EXPIRY_EXPECTED_PROJECT: PROJECT, EXPIRY_DATABASE: '(default)',
    EXPIRED_JOB_CLEANUP_ENABLED: 'true', EXPIRED_JOB_CLEANUP_DRY_RUN: 'false',
    EXPIRY_METADATA_WRITES_ENABLED: 'true', EXPIRY_PUSH_ENABLED: 'false',
    ACTIVITY_PUSH_ENABLED: 'false', EXPIRY_TOKEN_REGISTRATION_ENABLED: 'false',
  } };
}
async function setLocalGate(db, expirationEnabled) {
  await db.doc(SETTINGS).set({ expirationEnabled, source: 'local-computer', updatedAt: new Date() }, { merge: true });
}
function serverClock(snapshot, monotonic = () => performance.now()) {
  const epoch = snapshot.readTime?.toMillis?.();
  if (!Number.isFinite(epoch)) throw new Error('LIVE_SERVER_CLOCK_UNAVAILABLE');
  const anchor = monotonic();
  return () => epoch + Math.max(0, monotonic() - anchor);
}
async function initialize() {
  validateEnvironment(process.env);
  const cli = createRequire(path.join(root, 'mobile/my_app/rules-tests/node_modules/firebase-tools/package.json'));
  const account = cli('./lib/auth').getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) throw new Error('CLI_LOGIN_REQUIRED');
  const api = cli('./lib/api');
  const { GoogleAuth } = sdk('google-auth-library');
  const auth = new GoogleAuth({ projectId: PROJECT, credentials: {
    type: 'authorized_user', client_id: api.clientId(), client_secret: api.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  } });
  const client = await auth.getClient();
  const checkBilling = async () => {
    const response = await client.request({ url: `https://cloudbilling.googleapis.com/v1/projects/${PROJECT}/billingInfo`, timeout: 20000 });
    if (response.data.billingEnabled !== false) throw new Error('NO_BILLING_REQUIREMENT_NOT_VERIFIED');
  };
  await checkBilling();
  const metadata = await client.request({ url: `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)`, timeout: 20000 });
  if (metadata.data.name !== `projects/${PROJECT}/databases/(default)` || metadata.data.type !== 'FIRESTORE_NATIVE' ||
    metadata.data.databaseEdition !== 'STANDARD') throw new Error('LIVE_DATABASE_MISMATCH');
  // Use the same SDK package as the shared runtime: Timestamp instanceof checks
  // must not mix independently installed SDK constructors.
  const { Firestore } = sdk('@google-cloud/firestore');
  const db = new Firestore({ projectId: PROJECT, databaseId: '(default)', auth, preferRest: true });
  if (db.projectId !== PROJECT || db.databaseId !== '(default)') { await db.terminate(); throw new Error('LIVE_DATABASE_MISMATCH'); }
  return { db, checkBilling };
}
async function preview(db, now = Date.now) {
  const policy = sdk('./src/expiredJobCleanupService');
  const asOf = new Date(now());
  let cursor = null; let scanned = 0; let wouldExpire = 0; const skipped = {};
  do {
    const result = await policy.runExpiredJobCleanup({ db, dryRun: true, startAfterId: cursor,
      now: () => asOf, logger: { info() {}, warn() {}, error() {} } });
    scanned += result.scanned; wouldExpire += result.wouldExpire;
    for (const [reason, count] of Object.entries(result.skipped)) skipped[reason] = (skipped[reason] || 0) + count;
    if (result.errors || !['complete', 'partial'].includes(result.status)) throw new Error('LIVE_PREVIEW_INCOMPLETE');
    if (result.status === 'complete') return { status: 'complete', scanned, wouldExpire, skipped, businessWrites: 0, metadataWrites: 0 };
    if (!result.nextAfterId || result.nextAfterId === cursor || scanned >= 5000) throw new Error('LIVE_PREVIEW_TOO_LARGE_OR_INCOMPLETE');
    cursor = result.nextAfterId;
  } while (true);
}
async function main(args = process.argv.slice(2)) {
  const config = options(args);
  validateEnvironment(process.env);
  const { db, checkBilling } = await initialize();
  let stop;
  const close = () => db.terminate();
  try {
    if (config.mode === '--stop-live') { await setLocalGate(db, false); console.info({ event: 'local_live_expiry_disabled' }); await close(); return; }
    const previewNow = serverClock(await db.doc(SETTINGS).get());
    console.info({ event: 'live_expiry_read_only_preview', ...(await preview(db, previewNow)) });
    if (config.mode === '--preview') { await close(); return; }
    await checkBilling();
    await setLocalGate(db, true);
    const { sweep } = sdk('./src/runtime');
    const run = async shouldStop => {
      await checkBilling(); // Fail closed if billing state cannot be verified.
      // Use Firestore's authoritative read time, advanced monotonically, rather
      // than trusting this computer's wall clock for deadlines or fenced leases.
      const now = serverClock(await db.doc(SETTINGS).get());
      return sweep({ ...sweepOptions(db, shouldStop), now });
    };
    if (config.once) {
      const result = await run(() => false);
      console.info({ event: 'local_live_expiry_sweep', ...result });
      if (result.status !== 'complete') process.exitCode = 2;
      await close(); return;
    }
    const { startLoop } = sdk('./scripts/localExpiryDemo');
    console.info('Live computer cleanup enabled: swiftserve-production/(default). Checks every 30 minutes; no FCM. Keep this terminal and computer running.');
    stop = startLoop({ sweep: run, delay: 30 * 60 * 1000,
      onResult: result => console.info({ event: 'local_live_expiry_sweep', ...result }),
      onError: () => console.error({ event: 'local_live_expiry_failed', message: 'Scan failed or gate closed; checkpoint retained. Retry in 30 minutes.' }) });
    let closing;
    const shutdown = () => { closing ||= (async () => { await stop(); await close(); })(); return closing; };
    process.once('SIGINT', shutdown); process.once('SIGTERM', shutdown);
  } catch (error) { if (stop) await stop(); await close(); throw error; }
}
if (require.main === module) main().catch(error => {
  const value = String(error.code || (/^[A-Z_]+$/.test(error.message) ? error.message : 'CONNECTION_OR_AUTHENTICATION_FAILED'));
  console.error({ event: 'local_live_expiry_start_failed', code: value.slice(0, 64) }); process.exitCode = 1;
});
module.exports = { PROJECT, SETTINGS, options, validateEnvironment, sweepOptions, setLocalGate, serverClock, preview, main };
