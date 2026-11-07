const PROJECT = 'swiftserve-production';
const APPROVED_ADMIN_UID = 'n4n7wxbWo6OkRmlEsrlk3V7mJhy1';
let firebase;

function validate(env) {
  if (env.SWIFTSERVE_LIVE_READ_ONLY !== 'true' || env.FIREBASE_PROJECT_ID !== PROJECT ||
      env.FIRESTORE_DATABASE_ID !== '(default)') throw new Error('LIVE_TARGET_REQUIRED');
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_CONFIG', 'GOOGLE_APPLICATION_CREDENTIALS']) {
    if (env[key]) throw new Error('LIVE_UNSAFE_ENVIRONMENT: ' + key);
  }
  if (env.SWIFTSERVE_SUPER_ADMIN_UIDS && env.SWIFTSERVE_SUPER_ADMIN_UIDS !== APPROVED_ADMIN_UID) {
    throw new Error('LIVE_UNAPPROVED_SUPER_ADMIN');
  }
  if (env.SWIFTSERVE_LIVE_ADMIN_CREATION !== undefined && !['true', 'false'].includes(env.SWIFTSERVE_LIVE_ADMIN_CREATION)) {
    throw new Error('LIVE_INVALID_CREATION_GATE');
  }
  if (env.SWIFTSERVE_LIVE_ADMIN_CREATION === 'true' && env.SWIFTSERVE_SUPER_ADMIN_UIDS !== APPROVED_ADMIN_UID) {
    throw new Error('LIVE_CREATION_REQUIRES_APPROVED_SUPER_ADMIN');
  }
  for (const key of ['SWIFTSERVE_NETLIFY_PILOT', 'SWIFTSERVE_STAGING',
    'EXPIRED_JOB_CLEANUP_ENABLED', 'PUSH_DELIVERY_ENABLED', 'ACTIVITY_PUSH_ENABLED', 'EXPIRY_PUSH_ENABLED']) {
    if (env[key] !== 'false') throw new Error('LIVE_UNSAFE_GATE: ' + key);
  }
  if (env.EXPIRED_JOB_CLEANUP_DRY_RUN !== 'true' || env.NODE_TLS_REJECT_UNAUTHORIZED === '0') {
    throw new Error('LIVE_UNSAFE_CONFIGURATION');
  }
}

function readOnly(req, res, next, env = process.env) {
  res.setHeader('Cache-Control', 'no-store');
  const path = req.path;
  const creationPath = path === '/api/admin/administrators' || path === '/api/admin/administrators/' ||
    /^\/api\/admin\/administrators\/[A-Za-z0-9_-]{1,128}\/complete-setup\/?$/.test(path || '');
  const approvedCreation = env.SWIFTSERVE_LIVE_ADMIN_CREATION === 'true' &&
    env.SWIFTSERVE_SUPER_ADMIN_UIDS === APPROVED_ADMIN_UID && req.method === 'POST' && creationPath;
  // Passing this boundary never grants identity/permission: the management router
  // still verifies the token, current account, revocation and Super Admin authority.
  if (req.method !== 'GET' && !approvedCreation) return res.status(403).json({ message:
    env.SWIFTSERVE_LIVE_ADMIN_CREATION === 'true'
      ? 'Only administrator creation and interrupted setup recovery are enabled. Other changes are blocked.'
      : 'Live database viewing only. Changes are not enabled.' });
  return next();
}

async function initialize(cliDirectory) {
  validate(process.env);
  const { createRequire } = require('node:module');
  const path = require('node:path');
  const cli = createRequire(path.join(cliDirectory, 'package.json'));
  const account = cli('./lib/auth').getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) throw new Error('FIREBASE_CLI_LOGIN_REQUIRED');
  const api = cli('./lib/api');
  const { GoogleAuth } = require('google-auth-library');
  // Local operator login only. No key file, browser credentials, or cloud deployment.
  const googleAuth = new GoogleAuth({ projectId: PROJECT, credentials: {
    type: 'authorized_user', client_id: api.clientId(), client_secret: api.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  } });
  const client = await googleAuth.getClient();
  const metadata = await client.request({ url: `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)` });
  if (metadata.data.name !== `projects/${PROJECT}/databases/(default)`) throw new Error('LIVE_DATABASE_MISMATCH');
  const credential = { async getAccessToken() {
    const result = await client.getAccessToken();
    if (!result.token) throw new Error('LIVE_LOGIN_REQUIRED');
    return { access_token: result.token, expires_in: Math.max(1, Math.floor(((client.credentials.expiry_date || Date.now()) - Date.now()) / 1000)) };
  } };
  const app = require('firebase-admin/app').initializeApp({ projectId: PROJECT, credential }, 'swiftserve-live-read-only');
  const auth = require('firebase-admin/auth').getAuth(app);
  const existing = await auth.getUser(APPROVED_ADMIN_UID);
  if (existing.email !== 'admin@swiftserve.com' || existing.disabled || existing.customClaims?.admin !== true || existing.customClaims?.staff === true) {
    throw new Error('LIVE_EXISTING_ADMIN_NOT_VERIFIED');
  }
  const { Firestore } = require('@google-cloud/firestore');
  firebase = { auth, db: new Firestore({ projectId: PROJECT, databaseId: '(default)', auth: googleAuth, preferRest: true }),
    storage: { bucket() { throw new Error('LIVE_IMAGE_ACCESS_NOT_ENABLED'); } } };
}

function getFirebase() {
  if (!firebase) throw new Error('LIVE_NOT_INITIALIZED');
  return firebase;
}
module.exports = { PROJECT, APPROVED_ADMIN_UID, validate, readOnly, initialize, getFirebase };
