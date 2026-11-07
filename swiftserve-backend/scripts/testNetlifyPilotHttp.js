// Actual local Netlify Dev smoke test. Synthetic emulator accounts only.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
Object.assign(process.env, require('./startNetlifyPilot').environment());
async function run() {
  const {auth,db} = require('../src/config/firebase');
  async function login(email) {
    const r=await fetch('http://127.0.0.1:9599/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password:'LocalTestOnly-Password123!',returnSecureToken:true})});
    assert.equal(r.status,200);return(await r.json()).idToken;
  }
  const admin=await login('super-netlify@example.test');
  const api=(path,token,options={})=>fetch('http://localhost:8888'+path,{...options,redirect:'error',signal:AbortSignal.timeout(30000),headers:{...(token?{Authorization:'Bearer '+token}:{}),...options.headers}});
  assert.equal((await api('/')).status,200);
  assert.equal((await api('/api/admin/session')).status,401);
  const session=await api('/api/admin/session',admin);assert.equal(session.status,200);assert.equal((await session.json()).access.isSuperAdmin,true);
  const worker=await auth.createUser({email:`http-${randomUUID()}@example.test`,password:'LocalTestOnly-Password123!'});
  await db.collection('users').doc(worker.uid).create({role:'worker',verificationStatus:'pending',fullName:'Synthetic HTTP Worker'});
  const token=await login(worker.email),form=new FormData(),image=require('canvas').createCanvas(32,32).toBuffer('image/png');
  form.set('idType','Synthetic image only');form.set('idNumber','TEST-12345');for(const name of ['document','selfie'])form.set(name,new Blob([image],{type:'image/png'}),name+'.png');
  const uploaded=await api('/api/pilot/verification-images',token,{method:'POST',body:form});assert.equal(uploaded.status,201,await uploaded.text());
  const detail=await api('/api/admin/verifications/'+worker.uid,admin);assert.equal(detail.status,200);const item=(await detail.json()).item;
  for(const path of [item.governmentIdUrl,item.facePhotoUrl]) {
    assert.equal((await api(path,token)).status,403);
    const response=await api(path,admin);assert.equal(response.status,200);assert.match(response.headers.get('cache-control'),/no-store/);assert.deepEqual(Buffer.from(await response.arrayBuffer()),image);
  }
  const cleanup=await api('/api/pilot/verification-images/reconcile',admin,{method:'POST'});assert.equal(cleanup.status,200);
  console.log('PASS: actual Netlify Dev frontend, emulator login, protected session, synthetic upload, private document/selfie reads, denied worker access and manual reconciliation.');
  await db.terminate();await require('firebase-admin/app').deleteApp(require('firebase-admin/app').getApp());
}
run().catch(e=>{console.error('Local HTTP pilot failed: '+e.message);process.exitCode=1;});
