// Manual browser testing only. No dotenv, ADC key files, real projects or workers.
const os = require('node:os');
const path = require('node:path');
async function start() {
  const project = 'demo-swiftserve-admin-management';
  if (process.env.GOOGLE_CLOUD_PROJECT !== project ||
    !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '') ||
    !/^127\.0\.0\.1:\d+$/.test(process.env.FIREBASE_AUTH_EMULATOR_HOST || '') ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_CONFIG || process.env.FIREBASE_STORAGE_BUCKET) {
    throw new Error('Admin demo requires the exact demo project, both loopback emulators and no credential/config/bucket override.');
  }
  Object.assign(process.env, { GCLOUD_PROJECT: project, FIREBASE_PROJECT_ID: project, FIRESTORE_DATABASE_ID: '(default)', SWIFTSERVE_STAGING: 'false',
    EXPIRED_JOB_CLEANUP_ENABLED: 'false', EXPIRED_JOB_CLEANUP_DRY_RUN: 'true', PUSH_DELIVERY_ENABLED: 'false',
    VERIFICATION_STORAGE: 'local', UPLOADS_DIR: path.join(os.tmpdir(), 'SwiftServeAdminDemoUploads') });
  const { auth } = require('../src/config/firebase');
  if (process.argv.includes('--seed-super')) {
    let user;
    try { user = await auth.getUserByEmail('super@example.test'); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    user ||= await auth.createUser({ email: 'super@example.test', password: 'LocalTestOnly-Password123!', displayName: 'Demo Super Admin' });
    await auth.setCustomUserClaims(user.uid, { admin: true, superAdmin: true });
    console.log('Seeded the documented synthetic Super Admin in local demo Auth only.');
  }
  require('../src/app').listen(5003, '127.0.0.1', () => console.log('Local DEMO admin API ready on 127.0.0.1:5003; no cloud project or scheduling.'));
}
if (require.main === module) start().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { start };
