const path = require('node:path');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const live = require('../src/config/liveAdminReadOnly');

async function start() {
  if (process.argv.includes('--super-admin')) {
    if (process.env.SWIFTSERVE_SUPER_ADMIN_UIDS && process.env.SWIFTSERVE_SUPER_ADMIN_UIDS !== live.APPROVED_ADMIN_UID) {
      throw new Error('LIVE_UNAPPROVED_SUPER_ADMIN');
    }
    // Explicitly approved local authority only; never write Firebase custom claims.
    process.env.SWIFTSERVE_SUPER_ADMIN_UIDS = live.APPROVED_ADMIN_UID;
  }
  // Explicit opt-in; a normal restart remains read-only even if a gate is inherited.
  process.env.SWIFTSERVE_LIVE_ADMIN_CREATION = process.argv.includes('--allow-admin-creation') ? 'true' : 'false';
  // Separate launch environment: never edit .env, the demo, or production settings.
  Object.assign(process.env, {
    SWIFTSERVE_LIVE_READ_ONLY: 'true', FIREBASE_PROJECT_ID: live.PROJECT,
    FIRESTORE_DATABASE_ID: '(default)', SWIFTSERVE_NETLIFY_PILOT: 'false', SWIFTSERVE_STAGING: 'false',
    EXPIRED_JOB_CLEANUP_ENABLED: 'false', PUSH_DELIVERY_ENABLED: 'false', ACTIVITY_PUSH_ENABLED: 'false',
    EXPIRY_PUSH_ENABLED: 'false', EXPIRED_JOB_CLEANUP_DRY_RUN: 'true',
  });
  live.validate(process.env); // Reject inherited credentials/emulators; do not silently repoint them.
  const env = require('dotenv').parse(fs.readFileSync(path.join(root, 'admin/.env')));
  if (env.VITE_FIREBASE_PROJECT_ID !== live.PROJECT || env.VITE_FIREBASE_AUTH_DOMAIN !== `${live.PROJECT}.firebaseapp.com`) {
    throw new Error('LIVE_WEB_CONFIGURATION_MISMATCH');
  }
  await live.initialize(path.join(root, 'mobile/my_app/rules-tests/node_modules/firebase-tools'));
  const express = require('express');
  const app = express();
  app.disable('x-powered-by');
  const creationEnabled = process.env.SWIFTSERVE_LIVE_ADMIN_CREATION === 'true';
  app.use(require('cors')({ origin: 'http://127.0.0.1:5182', methods: creationEnabled ? ['GET', 'POST'] : ['GET'], allowedHeaders: ['Authorization', 'Content-Type'] }));
  app.use(live.readOnly);
  app.use(express.json({ limit: '100kb' }));
  app.get('/api/health', (_req, res) => res.json({ ok: true, projectId: live.PROJECT, databaseId: '(default)', readOnly: !creationEnabled, adminCreationEnabled: creationEnabled }));
  app.use('/api/admin', require('express-rate-limit').rateLimit({ windowMs: 60000, limit: 60, standardHeaders: 'draft-8', legacyHeaders: false }));
  // Creation/recovery require explicit opt-in and existing Super Admin authorization.
  app.use('/api/admin/administrators', require('../src/routes/adminManagementRoutes'));
  app.use('/api/admin', require('../src/routes/adminDataRoutes'));
  app.use((error, _req, res, _next) => {
    if (error.type === 'entity.too.large') return res.status(413).json({ message: 'Request is too large.' });
    if (error.type === 'entity.parse.failed') return res.status(400).json({ message: 'Request must contain valid JSON.' });
    return res.status(503).json({ message: 'Live request could not be completed. Refresh the administrator list before retrying; interrupted setup may need recovery.' });
  });
  const server = app.listen(5004, '127.0.0.1', () => console.log(`Live ${creationEnabled ? 'ADMIN-CREATION-ONLY' : 'READ-ONLY'} API: http://127.0.0.1:5004; Firebase swiftserve-production/(default)`));
  const publicEnv = Object.fromEntries(Object.entries(env).filter(([key]) => key.startsWith('VITE_FIREBASE_')));
  const child = spawn(process.execPath, [path.join(root, 'admin/node_modules/vite/bin/vite.js'), '--host', '127.0.0.1', '--port', '5182', '--strictPort'], {
    cwd: path.join(root, 'admin'), stdio: 'inherit', env: { ...process.env, ...publicEnv,
      VITE_USE_FIREBASE_EMULATORS: 'false', VITE_API_BASE_URL: 'http://127.0.0.1:5004' },
  });
  const stop = () => { child.kill(); server.close(); };
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
  child.once('exit', () => server.close());
  child.once('error', () => { console.error('Live frontend could not start.'); server.close(); });
}
if (require.main === module) start().catch(error => {
  console.error('Live read-only startup failed:', error.code || (/^[A-Z_]+$/.test(error.message) ? error.message : 'CONNECTION_OR_CONFIGURATION_ERROR'));
  process.exitCode = 1;
});
module.exports = { start };
