const path = require('node:path');
const { createRequire } = require('node:module');

const PROJECT = 'swiftserve-staging-2026';
const ANDROID_APP = '1:856393660184:android:5ab53b8630b20d3e47d06d';
let initialized;

function validateStagingEnvironment(env) {
  for (const key of ['GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT', 'FIREBASE_PROJECT_ID']) {
    if (env[key] && env[key] !== PROJECT) throw new Error(`STAGING_WRONG_PROJECT: ${key}`);
  }
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST', 'STORAGE_EMULATOR_HOST', 'GOOGLE_APPLICATION_CREDENTIALS',
    'FIREBASE_CONFIG', 'FIREBASE_STORAGE_BUCKET']) {
    if (env[key]) throw new Error(`STAGING_UNSAFE_ENVIRONMENT: ${key}`);
  }
  if (env.PORT && String(env.PORT) !== '5002') throw new Error('STAGING_WRONG_PORT');
  if (env.FIRESTORE_DATABASE_ID && env.FIRESTORE_DATABASE_ID !== '(default)') {
    throw new Error('STAGING_WRONG_DATABASE');
  }
  for (const key of ['EXPIRED_JOB_CLEANUP_ENABLED', 'PUSH_DELIVERY_ENABLED',
    'ACTIVITY_PUSH_ENABLED', 'EXPIRY_PUSH_ENABLED', 'ENABLE_PUSH_NOTIFICATIONS']) {
    if (env[key] && env[key] !== 'false') throw new Error(`STAGING_UNSAFE_GATE: ${key}`);
  }
  if (env.EXPIRED_JOB_CLEANUP_DRY_RUN === 'false') throw new Error('STAGING_UNSAFE_DRY_RUN');
}

function diagnostic(category, error) {
  const raw = String(error?.code ?? /^STAGING_[A-Z_]+/.exec(error?.message || '')?.[0] ?? 'unknown');
  const code = /^[a-zA-Z0-9_/-]{1,64}$/.test(raw) ? raw : 'redacted';
  console.error(JSON.stringify({ environment: 'staging', category, code }));
}

async function initializeStagingFirebase(cliDirectory) {
  validateStagingEnvironment(process.env);
  if (initialized) throw new Error('STAGING_ALREADY_INITIALIZED');
  // Explicit CLI login only: never discover ADC, .env credentials or a key file.
  const cliRequire = createRequire(path.join(path.resolve(cliDirectory), 'package.json'));
  if (cliRequire('./package.json').name !== 'firebase-tools') throw new Error('STAGING_INVALID_CLI');
  const cliAuth = cliRequire('./lib/auth');
  const account = cliAuth.getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) throw new Error('STAGING_CLI_LOGIN_REQUIRED');
  const api = cliRequire('./lib/api');
  const { GoogleAuth } = require('google-auth-library');
  const googleAuth = new GoogleAuth({
    projectId: PROJECT,
    credentials: {
      type: 'authorized_user', client_id: api.clientId(), client_secret: api.clientSecret(),
      refresh_token: account.tokens.refresh_token,
    },
  });
  const credential = {
    async getAccessToken() {
      const client = await googleAuth.getClient();
      const token = await client.getAccessToken();
      if (!token.token) throw new Error('STAGING_CREDENTIAL_UNAVAILABLE');
      return { access_token: token.token,
        expires_in: Math.max(1, Math.floor(((client.credentials.expiry_date || Date.now()) - Date.now()) / 1000)) };
    },
  };
  // All resource clients receive explicit staging project and database IDs.
  const { initializeApp } = require('firebase-admin/app');
  const app = initializeApp({ projectId: PROJECT, credential }, 'swiftserve-local-staging');
  const { Firestore } = require('@google-cloud/firestore');
  const db = new Firestore({ projectId: PROJECT, databaseId: '(default)', auth: googleAuth });
  const { getAuth } = require('firebase-admin/auth');
  const { getAppCheck } = require('firebase-admin/app-check');
  const auth = getAuth(app);
  // A harmless empty read checks Firestore connectivity/IAM before listening.
  try {
    await db.collection('staging_diagnostics').limit(1).get();
  } catch (error) {
    diagnostic('firestore-preflight', error);
    await db.terminate();
    await require('firebase-admin/app').deleteApp(app);
    throw error;
  }
  try {
    await auth.listUsers(1); // Read only, staging only; never log account records.
  } catch (error) {
    diagnostic('authentication-preflight', error);
    await db.terminate();
    await require('firebase-admin/app').deleteApp(app);
    throw error;
  }
  initialized = { app, auth, db, appCheck: getAppCheck(app),
    storage: { bucket() { throw new Error('STAGING_CLOUD_STORAGE_DISABLED'); } } };
  return initialized;
}

function getStagingFirebase() {
  if (!initialized) throw new Error('STAGING_NOT_INITIALIZED');
  return initialized;
}

module.exports = { PROJECT, ANDROID_APP, validateStagingEnvironment,
  initializeStagingFirebase, getStagingFirebase, diagnostic };
