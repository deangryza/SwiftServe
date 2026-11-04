// Local-only entry point. Deliberately does not import server.js or dotenv.
const path = require('node:path');
const os = require('node:os');
const { PROJECT, validateStagingEnvironment, initializeStagingFirebase, diagnostic } = require('../src/config/stagingFirebase');

async function start(cliDirectory) {
  validateStagingEnvironment(process.env);
  if (!cliDirectory) throw new Error('STAGING_CLI_DIRECTORY_REQUIRED');
  Object.assign(process.env, {
    SWIFTSERVE_STAGING: 'true', PORT: '5002', GOOGLE_CLOUD_PROJECT: PROJECT,
    GCLOUD_PROJECT: PROJECT, FIREBASE_PROJECT_ID: PROJECT, FIRESTORE_DATABASE_ID: '(default)',
    EXPIRED_JOB_CLEANUP_ENABLED: 'false', EXPIRED_JOB_CLEANUP_DRY_RUN: 'true',
    PUSH_DELIVERY_ENABLED: 'false', ACTIVITY_PUSH_ENABLED: 'false', EXPIRY_PUSH_ENABLED: 'false',
    VERIFICATION_STORAGE: 'local', UPLOADS_DIR: path.join(os.tmpdir(), 'SwiftServeStagingUploads'),
    DEBUG: '',
  });
  const { db } = await initializeStagingFirebase(cliDirectory);
  const app = require('../src/app');
  const server = await new Promise((resolve, reject) => {
    const listening = app.listen(5002, '127.0.0.1', () => resolve(listening));
    listening.once('error', reject);
  });
  console.info('SwiftServe STAGING ready: http://127.0.0.1:5002; swiftserve-staging-2026/(default); push/schedules disabled.');
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    server.close(async () => { await db.terminate(); });
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  return server;
}
if (require.main === module) start(process.argv[2]).catch(error => {
  diagnostic('startup', error);
  console.error('Staging startup failed. Check CLI login, explicit staging environment and port 5002. No ADC fallback is allowed.');
  process.exitCode = 1;
});
module.exports = { start };
