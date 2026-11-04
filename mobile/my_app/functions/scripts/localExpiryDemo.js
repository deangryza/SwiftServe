// Explicit local-only helper. No dotenv, ADC discovery, cloud Scheduler or FCM.
const PROJECT = 'demo-swiftserve-cleanup';
const PASSWORD = 'LocalTestOnly-Password123!';

function validate(env) {
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    if (!/^127\.0\.0\.1:([1-9]\d{0,4})$/.test(env[key] || '') || Number(env[key].split(':')[1]) > 65535) {
      throw new Error('LOCAL_DEMO_LOOPBACK_EMULATORS_REQUIRED');
    }
  }
  for (const key of ['GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT', 'FIREBASE_PROJECT_ID', 'EXPIRY_EXPECTED_PROJECT']) {
    if (env[key] && env[key] !== PROJECT) throw new Error('LOCAL_DEMO_PROJECT_MISMATCH');
  }
  for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_CONFIG', 'SWIFTSERVE_SUPER_ADMIN_UIDS']) {
    if (env[key]) throw new Error('LOCAL_DEMO_CREDENTIAL_OVERRIDE_REJECTED');
  }
  if (env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('LOCAL_DEMO_TLS_REQUIRED');
  if (env.FIRESTORE_DATABASE_ID && env.FIRESTORE_DATABASE_ID !== '(default)') throw new Error('LOCAL_DEMO_DEFAULT_DATABASE_REQUIRED');
}

function runtimeEnv(env) {
  validate(env);
  return {
    FUNCTIONS_EMULATOR: 'true', FIRESTORE_EMULATOR_HOST: env.FIRESTORE_EMULATOR_HOST,
    EXPIRY_EXPECTED_PROJECT: PROJECT, EXPIRY_DATABASE: '(default)',
    EXPIRED_JOB_CLEANUP_ENABLED: 'true', EXPIRED_JOB_CLEANUP_DRY_RUN: 'false',
    EXPIRY_METADATA_WRITES_ENABLED: 'true', EXPIRY_PUSH_ENABLED: 'false',
    ACTIVITY_PUSH_ENABLED: 'false', EXPIRY_TOKEN_REGISTRATION_ENABLED: 'false',
  };
}

async function seed(auth, db, timestamp) {
  const category = db.collection('service_categories').doc('expiry-demo-cleaning');
  const existingCategory = await category.get();
  if (existingCategory.exists && (existingCategory.data().name !== 'Cleaning' || existingCategory.data().status !== 'active')) {
    throw new Error('LOCAL_DEMO_EXISTING_CATEGORY_MISMATCH');
  }
  if (!existingCategory.exists) await category.create({ name: 'Cleaning', status: 'active', createdAt: timestamp });
  for (const role of ['client', 'worker']) {
    const uid = `expiry-demo-${role}`;
    const email = `${role}-expiry@example.test`;
    let account;
    try { account = await auth.getUser(uid); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    if (account && (account.email !== email || account.disabled)) throw new Error('LOCAL_DEMO_EXISTING_ACCOUNT_MISMATCH');
    if (!account) await auth.createUser({ uid, email, password: PASSWORD, displayName: `Expiry Demo ${role}` });
    const profile = db.collection('users').doc(uid);
    const previous = await profile.get();
    if (previous.exists && (previous.data().role !== role || previous.data().email !== email)) {
      throw new Error('LOCAL_DEMO_EXISTING_PROFILE_MISMATCH');
    }
    if (!previous.exists) await profile.create({
      fullName: `Expiry Demo ${role}`, email, role, roles: [role],
      verificationStatus: role === 'worker' ? 'verified' : 'pending',
      address: 'Brgy. Demo, Demo City, Demo Province', phoneNumber: '',
      photoBase64: '', createdAt: timestamp,
    });
  }
}

function startLoop({ sweep, delay = 5000, schedule = setTimeout, cancel = clearTimeout, onResult = console.info, onError = console.error }) {
  let stopped = false;
  let timer;
  let active;
  const tick = () => {
    if (stopped) return;
    active = (async () => {
      try { onResult(await sweep(() => stopped)); }
      catch (error) { onError({ event: 'local_expiry_failed', code: String(error.code || 'SCAN_FAILED').slice(0, 64) }); }
      finally { if (!stopped) timer = schedule(tick, delay); }
    })();
  };
  tick();
  return async () => { stopped = true; cancel(timer); await active; };
}

async function main({ args = process.argv.slice(2), env = process.env } = {}) {
  if (!args.includes('--write-demo')) {
    console.info('No writes performed. Use --write-demo (and optionally --seed-demo, --once) with local Auth/Firestore emulators.');
    return;
  }
  validate(env); // Must finish before importing/initializing Firebase.
  // The Admin SDK reads process.env itself. Never validate a different object
  // and then accidentally initialize the SDK with unvalidated real endpoints.
  if (env !== process.env) throw new Error('LOCAL_DEMO_PROCESS_ENVIRONMENT_REQUIRED');
  const { initializeApp, deleteApp } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');
  const { getFirestore, Timestamp } = require('firebase-admin/firestore');
  const { sweep } = require('../src/runtime');
  const app = initializeApp({ projectId: PROJECT }, 'local-expiry-demo');
  const db = getFirestore(app);
  let stop;
  const close = async () => { await db.terminate(); await deleteApp(app); };
  try {
    if (args.includes('--seed-demo')) await seed(getAuth(app), db, Timestamp.now());
    // Emulator metadata writes are explicit and separate from business-data writes.
    await db.collection('_jobExpiryControl').doc('settings').set({
      previewEnabled: true, expirationEnabled: true, pushEnabled: false,
      activityPushEnabled: false, registrationEnabled: false,
    }, { merge: true });
    const run = (shouldStop = () => false) => sweep({ db, env: runtimeEnv(env), shouldStop });
    if (args.includes('--once')) { console.info(await run()); await close(); return; }
    console.info('LOCAL DEMO only: demo-swiftserve-cleanup/(default); scans every 5 seconds; no FCM.');
    stop = startLoop({ sweep: run, onResult: result => console.info({ event: 'local_expiry_scan', ...result }) });
    let closing;
    const shutdown = () => { closing ||= (async () => { await stop(); await close(); })(); return closing; };
    process.once('SIGINT', shutdown); process.once('SIGTERM', shutdown);
  } catch (error) {
    if (stop) await stop();
    await close();
    throw error;
  }
}
if (require.main === module) main().catch(error => {
  console.error({ event: 'local_expiry_start_failed', code: String(error.code || 'LOCAL_DEMO_CONFIGURATION_OR_CONNECTION_FAILED').slice(0, 64) });
  process.exitCode = 1;
});
module.exports = { PROJECT, validate, runtimeEnv, seed, startLoop, main };
