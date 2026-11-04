// Optional synthetic fixtures, exclusively in the dedicated local Auth emulator.
Object.assign(process.env, require('./startNetlifyPilot').environment());
if (!process.argv.includes('--seed')) throw new Error('Pass --seed to create synthetic emulator accounts.');
async function seed() {
  const { auth, db } = require('../src/config/firebase');
  for (const [email, claims, worker] of [['super-netlify@example.test',{admin:true,superAdmin:true},false],['worker-netlify@example.test',{},true]]) {
    let user;
    try { user = await auth.getUserByEmail(email); }
    catch(error) { if(error.code !== 'auth/user-not-found') throw error; }
    if (user) { console.log('Existing synthetic fixture retained: '+email); continue; }
    user = await auth.createUser({ email, password:'LocalTestOnly-Password123!', displayName: worker ? 'Synthetic Worker' : 'Synthetic Super Admin' });
    await auth.setCustomUserClaims(user.uid,claims);
    if(worker)await db.collection('users').doc(user.uid).create({uid:user.uid,role:'worker',fullName:'Synthetic Worker',verificationStatus:'pending',createdAt:new Date()});
    console.log('Created synthetic emulator fixture: '+email);
  }
}
seed().catch(error=>{console.error('Local fixture setup failed: '+String(error.code||'unknown'));process.exitCode=1;});
