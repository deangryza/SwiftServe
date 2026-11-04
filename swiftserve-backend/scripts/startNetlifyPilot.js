// No dotenv, Netlify login, remote project linking or credential discovery.
const { spawn } = require('node:child_process');
const path = require('node:path');
function environment() {
  const env = { ...process.env, NETLIFY_DEV: 'true', SWIFTSERVE_NETLIFY_PILOT: 'true', SWIFTSERVE_STAGING: 'false',
    GOOGLE_CLOUD_PROJECT: 'demo-swiftserve-netlify', GCLOUD_PROJECT: 'demo-swiftserve-netlify', FIREBASE_PROJECT_ID: 'demo-swiftserve-netlify',
    FIRESTORE_DATABASE_ID: '(default)', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9599', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8288',
    VERIFICATION_STORAGE: 'netlify-blobs', EXPIRED_JOB_CLEANUP_ENABLED: 'false', EXPIRED_JOB_CLEANUP_DRY_RUN: 'true',
    PUSH_DELIVERY_ENABLED: 'false', ACTIVITY_PUSH_ENABLED: 'false', EXPIRY_PUSH_ENABLED: 'false', NETLIFY_TELEMETRY_DISABLED: '1',
    VITE_FIREBASE_PROJECT_ID: 'demo-swiftserve-netlify', VITE_FIREBASE_API_KEY: 'demo-key',
    VITE_FIREBASE_AUTH_DOMAIN: 'demo-swiftserve-netlify.localhost', VITE_FIREBASE_STORAGE_BUCKET: 'demo.invalid',
    VITE_FIREBASE_MESSAGING_SENDER_ID: '123456789', VITE_FIREBASE_APP_ID: '1:123456789:web:0000000000000000000000',
    VITE_USE_FIREBASE_EMULATORS: 'true', VITE_API_BASE_URL: 'http://localhost:8888', DEBUG: '', NODE_USE_SYSTEM_CA: '1' };
  for (const name of ['GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_CONFIG','FIREBASE_STORAGE_BUCKET','SWIFTSERVE_SUPER_ADMIN_UIDS','NETLIFY_AUTH_TOKEN','NETLIFY_SITE_ID']) env[name] = '';
  require('../src/config/netlifyPilot').validatePilot(env);
  return env;
}
if (require.main === module) {
  const cli = path.resolve(__dirname, '../node_modules/netlify-cli/bin/run.js');
  // No Edge Functions exist in this pilot. Avoid downloading/starting Deno.
  const child = spawn(process.execPath, ['--use-system-ca', cli, 'dev', '--offline', '--internal-disable-edge-functions'], { cwd: path.resolve(__dirname, '../..'), env: environment(), stdio: 'inherit', windowsHide: true });
  child.on('exit', code => { process.exitCode = code || 0; });
}
module.exports = { environment };
