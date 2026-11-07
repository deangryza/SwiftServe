const PROJECT = 'demo-swiftserve-netlify';
function validatePilot(env = process.env) {
  if (env.NODE_TLS_REJECT_UNAUTHORIZED === '0') throw new Error('PILOT_TLS_VERIFICATION_REQUIRED');
  if (env.NETLIFY_DEV !== 'true' || env.SWIFTSERVE_NETLIFY_PILOT !== 'true') throw new Error('PILOT_LOCAL_ONLY');
  for (const key of ['GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT', 'FIREBASE_PROJECT_ID']) {
    if (env[key] !== PROJECT) throw new Error('PILOT_WRONG_PROJECT');
  }
  if (env.FIRESTORE_DATABASE_ID !== '(default)') throw new Error('PILOT_WRONG_DATABASE');
  for (const key of ['FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST']) {
    if (!/^127\.0\.0\.1:\d+$/.test(env[key] || '')) throw new Error('PILOT_EMULATORS_REQUIRED');
  }
  for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_CONFIG', 'FIREBASE_STORAGE_BUCKET', 'NETLIFY_AUTH_TOKEN', 'SWIFTSERVE_SUPER_ADMIN_UIDS']) {
    if (env[key]) throw new Error(`PILOT_UNSAFE_ENVIRONMENT: ${key}`);
  }
  if (env.SWIFTSERVE_STAGING === 'true' || env.VERIFICATION_STORAGE !== 'netlify-blobs') throw new Error('PILOT_WRONG_STORAGE_OR_ENVIRONMENT');
  for (const key of ['EXPIRED_JOB_CLEANUP_ENABLED', 'PUSH_DELIVERY_ENABLED', 'ACTIVITY_PUSH_ENABLED', 'EXPIRY_PUSH_ENABLED']) {
    if (env[key] !== 'false') throw new Error('PILOT_UNSAFE_GATE');
  }
  if (env.EXPIRED_JOB_CLEANUP_DRY_RUN !== 'true') throw new Error('PILOT_UNSAFE_GATE');
  return PROJECT;
}
function initializePilot() {
  validatePilot();
  const { initializeApp } = require('firebase-admin/app');
  const app = initializeApp({ projectId: PROJECT });
  return { auth: require('firebase-admin/auth').getAuth(app), db: require('firebase-admin/firestore').getFirestore(app),
    storage: { bucket() { throw new Error('PILOT_GCS_DISABLED'); } } };
}
module.exports = { PROJECT, validatePilot, initializePilot };
