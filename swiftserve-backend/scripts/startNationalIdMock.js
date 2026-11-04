// Dedicated demo/emulator process: no dotenv, keys, ADC or production access.
const { localTarget } = require('../src/identity/policy');
function validate(env) {
  localTarget({ projectId: env.GCLOUD_PROJECT, databaseId: '(default)' }, env);
  if (['SWIFTSERVE_LIVE_READ_ONLY', 'SWIFTSERVE_STAGING', 'SWIFTSERVE_NETLIFY_PILOT'].some(key => env[key] === 'true')) throw new Error('Use a separate identity demo process');
}
async function main() {
  validate(process.env);
  const { initializeApp } = require('firebase-admin/app');
  const { getAuth } = require('firebase-admin/auth');
  const { getFirestore } = require('firebase-admin/firestore');
  const app = initializeApp({ projectId: process.env.GCLOUD_PROJECT });
  if (process.argv.includes('--seed-synthetic')) {
    for (const role of ['client', 'worker', 'reviewer']) {
      const uid = `identity-demo-${role}`, email = `identity-${role}@example.test`;
      let account;
      try { account = await getAuth(app).getUser(uid); }
      catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
      if (account) {
        if (account.email !== email || (role === 'reviewer' && account.customClaims?.admin !== true)) throw new Error('Existing synthetic account differs; refusing overwrite');
        const profile = (await getFirestore(app).collection('users').doc(uid).get()).data();
        if (!profile || profile.dateOfBirth !== '2000-01-01') throw new Error('Existing synthetic profile differs; refusing overwrite');
        continue;
      }
      await getAuth(app).createUser({ uid, email, password: 'SyntheticIdentityOnly123!', displayName: `Synthetic ${role}` });
      if (role === 'reviewer') await getAuth(app).setCustomUserClaims(uid, { admin: true });
      await getFirestore(app).collection('users').doc(uid).create({ uid, fullName: `Synthetic ${role}`, email,
        role: role === 'worker' ? 'worker' : 'client', dateOfBirth: '2000-01-01',
        verificationStatus: role === 'worker' ? 'pending' : 'not_required', createdAt: new Date() });
    }
    console.info('Created/retained synthetic identity-client, identity-worker and identity-reviewer accounts in demo emulators only.');
  }
  const configPath = require.resolve('../src/config/firebase');
  require.cache[configPath] = { id: configPath, filename: configPath, loaded: true, exports: { db: getFirestore(app), auth: getAuth(app), storage: null } };
  const server = require('../src/app').listen(5007, '127.0.0.1', () => console.info('Local MOCK identity API on 127.0.0.1:5007; synthetic data only; no official verification.'));
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => server.close());
}
if (require.main === module) main().catch(() => { console.error('Identity demo refused startup. Check demo project and loopback emulator configuration.'); process.exitCode = 1; });
module.exports = { validate };
