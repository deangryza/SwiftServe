// Explicit opt-in synthetic staging writes; no production endpoint or ADC path.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { PROJECT, ANDROID_APP, initializeStagingFirebase } = require('../src/config/stagingFirebase');

async function test(cliDirectory) {
  if (process.argv[2] !== '--write-synthetic-staging-records' || !cliDirectory) {
    throw new Error('Use --write-synthetic-staging-records followed by the firebase-tools package directory.');
  }
  const { app, db } = await initializeStagingFirebase(cliDirectory);
  const sdk = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../mobile/my_app/config/firebase/staging/google-services.json')));
  if (sdk.project_info.project_id !== PROJECT || sdk.project_info.project_number !== '856393660184') throw new Error('Wrong SDK project');
  const client = sdk.client.find(value => value.client_info.mobilesdk_app_id === ANDROID_APP);
  if (!client) throw new Error('Wrong SDK app');
  const key = client.api_key[0].current_key;
  const access = await app.options.credential.getAccessToken();
  const parent = `projects/856393660184/apps/${ANDROID_APP}`;
  const acBase = 'https://firebaseappcheck.googleapis.com/v1/';
  let debugName;
  async function json(url, options) {
    const response = await fetch(url, options);
    const data = await response.json();
    if (!response.ok) throw new Error(`Staging test HTTP ${response.status}`);
    return data;
  }
  try {
    const health = await json('http://127.0.0.1:5002/api/health');
    if (health.projectId !== PROJECT || health.databaseId !== '(default)') throw new Error('Wrong backend target');
    const debugSecret = crypto.randomUUID();
    const debug = await json(acBase + parent + '/debugTokens', {
      method: 'POST', headers: { Authorization: 'Bearer ' + access.access_token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ displayName: 'Temporary local onboarding smoke test', token: debugSecret }),
    });
    debugName = debug.name;
    const check = await json(acBase + parent + ':exchangeDebugToken?key=' + key, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ debugToken: debugSecret }),
    });
    const headers = { 'Content-Type': 'application/json', 'X-Firebase-AppCheck': check.token };
    const missing = await fetch('http://127.0.0.1:5002/api/staging/session');
    if (missing.status !== 401) throw new Error('Missing App Check accepted');
    const unauthenticated = await fetch('http://127.0.0.1:5002/api/staging/session', { headers });
    if (unauthenticated.status !== 401) throw new Error('Missing Auth accepted');
    const forged = await fetch('http://127.0.0.1:5002/api/staging/session', { headers: { ...headers, Authorization: 'Bearer invalid' } });
    if (forged.status !== 401) throw new Error('Invalid Auth accepted');
    console.log('PASS real staging backend rejects missing App Check, missing Auth and invalid Auth.');
    for (const [index, role] of ['client', 'worker'].entries()) {
      const password = crypto.randomBytes(32).toString('base64url') + 'aA1!';
      const email = `onboarding-${role}-${crypto.randomUUID()}@example.test`;
      const account = await json('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + key, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Firebase-AppCheck': check.token },
        body: JSON.stringify({ email, password, returnSecureToken: true }),
      });
      const signed = await json('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=' + key, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Firebase-AppCheck': check.token },
        body: JSON.stringify({ email, password, returnSecureToken: true }),
      });
      const authorized = { ...headers, Authorization: 'Bearer ' + signed.idToken };
      // Reserved fictional NANP 202-555-01xx numbers; no SMS is sent.
      let phoneNumber;
      for (let number = 10 + index; number < 100; number += 2) {
        const candidate = '+120255501' + String(number).padStart(2, '0');
        const hash = crypto.createHash('sha256').update(candidate).digest('hex');
        if (!(await db.collection('phone_number_claims').doc(hash).get()).exists) { phoneNumber = candidate; break; }
      }
      if (!phoneNumber) throw new Error('Reserved synthetic phone-number pool exhausted');
      const created = await fetch('http://127.0.0.1:5002/api/users/profile', {
        method: 'POST', headers: authorized, body: JSON.stringify({ dateOfBirth: '2000-01-01', fullName: `Staging ${role} test`, email,
          phoneNumber, address: '123 Example Street, Brgy. Ligas, Malolos, Bulacan', role,
          ...(role === 'worker' ? { category: 'Cleaning', skills: ['Cleaning', 'Repairs'] } : {}),
        }),
      });
      if (created.status !== 201) throw new Error(`${role} profile HTTP ${created.status}`);
      const session = await json('http://127.0.0.1:5002/api/staging/session', { headers: authorized });
      if (!session.profileExists || session.role !== role) throw new Error('Profile session mismatch');
      const user = (await db.collection('users').doc(account.localId).get()).data();
      const publicProfile = (await db.collection('public_profiles').doc(account.localId).get()).data();
      if (user.role !== role || publicProfile.location !== 'Brgy. Ligas, Malolos') throw new Error('Profile projection mismatch');
      if (JSON.stringify(publicProfile).includes('123 Example Street')) throw new Error('Public profile privacy violation');
      if (role === 'worker') {
        const worker = (await db.collection('worker_profiles').doc(account.localId).get()).data();
        if (worker.skills.join(',') !== 'Cleaning,Repairs' || worker.verificationStatus !== 'pending') throw new Error('Worker profile mismatch');
      }
      console.log(`PASS ${role}: staging signup/sign-in, App Check-authenticated backend profile transaction, private/public projections and session load.`);
    }
    console.log('Synthetic accounts, phone claims and profiles retained in staging. No credentials printed/saved. Dashboard UI and physical-device App Check are NOT verified by this script.');
  } finally {
    // Revoke only the temporary token created by this invocation, never a device token.
    if (debugName?.startsWith(parent + '/debugTokens/')) {
      const response = await fetch(acBase + debugName, { method: 'DELETE', headers: { Authorization: 'Bearer ' + access.access_token } });
      if (!response.ok) throw new Error('Temporary App Check token cleanup failed HTTP ' + response.status);
    }
    await db.terminate();
  }
}
if (require.main === module) test(process.argv[3]).catch(error => { console.error(error.message); process.exitCode = 1; });
