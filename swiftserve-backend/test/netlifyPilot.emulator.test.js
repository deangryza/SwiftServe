const { describe, test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { randomUUID } = require('node:crypto');
describe('Netlify pilot with actual adapter, Blobs local server and Firebase emulators', { skip: process.env.RUN_NETLIFY_EMULATOR_TESTS !== 'true' }, () => {
  let db, auth, sdk, server, temporary, store, handler, superToken, workerToken, staffToken, workerId, superId;
  const password = 'LocalTestOnly-Password123!';
  const png = () => require('canvas').createCanvas(32,32).toBuffer('image/png');
  async function login(email) {
    const r = await fetch('http://127.0.0.1:9599/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }) });
    assert.equal(r.status,200); return (await r.json()).idToken;
  }
  async function call(method, url, token, body, extra = {}) {
    const headers = { host: 'localhost:8888', ...(token ? { authorization: 'Bearer '+token } : {}) };
    let text = '', binary = false;
    if (body instanceof FormData) {
      const req = new Request('http://localhost:8888'+url, { method, body }); headers['content-type'] = req.headers.get('content-type');
      text = Buffer.from(await req.arrayBuffer()).toString('base64'); binary = true;
    } else if (body) { text = JSON.stringify(body); headers['content-type'] = 'application/json'; }
    const response = await handler({ httpMethod: method, path: url.split('?')[0], rawUrl: 'http://localhost:8888'+url,
      queryStringParameters: Object.fromEntries(new URL('http://localhost'+url).searchParams), headers: { ...headers, ...extra }, body: text, isBase64Encoded: binary,
      requestContext: { identity: { sourceIp: '127.0.0.1' } } }, {});
    return { ...response, json() { return JSON.parse(this.body); } };
  }
  const form = () => { const f = new FormData(); f.set('idType','Synthetic test document'); f.set('idNumber','TEST-123456'); for(const kind of ['document','selfie'])f.set(kind,new Blob([png()],{type:'image/png'}),kind+'.png');return f; };
  before(async () => {
    if (process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9599' || process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8288') throw new Error('Dedicated local pilot emulators required.');
    Object.assign(process.env, require('../scripts/startNetlifyPilot').environment());
    temporary = await fs.mkdtemp(path.join(os.tmpdir(),'SwiftServeBlobsTest-'));
    const { BlobsServer } = require('@netlify/blobs/server'); server = new BlobsServer({ directory: temporary, token: 'synthetic-local-token' });
    const address = await server.start();
    const blobs = require('@netlify/blobs'); const base = `http://127.0.0.1:${address.port}`;
    blobs.setEnvironmentContext({ siteID: 'pilot-local', token: 'synthetic-local-token', edgeURL: base, uncachedEdgeURL: base });
    store = blobs.getStore({ name: 'swiftserve-local-verification-v1', consistency: 'strong', fetch: require('../src/services/netlifyVerificationStorage').localFetch });
    ({ db, auth } = require('../src/config/firebase')); sdk = require('firebase-admin/app').getApp();
    const suffix = randomUUID().slice(0,8);
    for (const [kind, claims] of [['super',{admin:true,superAdmin:true}],['worker',{}],['staff',{staff:true}]]) {
      const u = await auth.createUser({ email: `${kind}-${suffix}@example.test`, password }); await auth.setCustomUserClaims(u.uid,claims);
      const token = await login(u.email);
      if (kind==='super') { superToken=token; superId=u.uid; }
      if (kind==='worker') { workerToken=token; workerId=u.uid; await db.collection('users').doc(u.uid).set({ role:'worker', verificationStatus:'pending',fullName:'Synthetic Worker' }); }
      if (kind==='staff') { staffToken=token; await db.collection('admin_accounts').doc(u.uid).set({email:u.email, status:'active',permissions:['reports.view'],role:'Reviewer'}); }
    }
    handler = require('../netlify/functions/api').handler;
  });
  after(async () => { if(db)await db.terminate();if(sdk)await require('firebase-admin/app').deleteApp(sdk);if(server)await server.stop();if(temporary)await fs.rm(temporary,{recursive:true,force:true}); });
  test('actual handler rejects unauthorized, invalid-token and disallowed-origin requests; lightweight initialization', async () => {
    assert.equal((await call('GET','/api/admin/session')).statusCode,401);
    assert.equal((await call('GET','/api/admin/session','invalid-token')).statusCode,401);
    const parts=superToken.split('.'), payload=JSON.parse(Buffer.from(parts[1],'base64url'));
    parts[1]=Buffer.from(JSON.stringify({...payload,iat:1,exp:2})).toString('base64url');
    assert.equal((await call('GET','/api/admin/session',parts.join('.'))).statusCode,401);
    assert.equal((await call('GET','/api/admin/session',workerToken)).statusCode,403);
    assert.equal((await call('GET','/api/admin/session',superToken,{},{origin:'https://untrusted.example'})).statusCode,403);
    const r=await call('GET','/api/admin/session',superToken); assert.equal(r.statusCode,200);assert.equal(r.json().access.isSuperAdmin,true);
    assert.equal(Object.keys(require.cache).some(x=>/node_modules[\\/]canvas[\\/]lib[\\/]canvas/.test(x)),false);
  });
  test('all management operations stay Super Admin-only; no self edits or legacy disable', async () => {
    assert.equal((await call('GET','/api/admin/administrators',staffToken)).statusCode,403);
    assert.equal((await call('GET','/api/admin/users',staffToken)).statusCode,403);
    const data={fullName:'Local managed admin',email:`managed-${randomUUID()}@example.test`,password,role:'Reviewer',permissions:['reports.view']};
    const created=await call('POST','/api/admin/administrators',superToken,data);assert.equal(created.statusCode,201); const u=created.json().item;
    assert.equal((await auth.getUser(u.id)).customClaims.staff,true);
    assert.equal((await call('PATCH','/api/admin/administrators/'+superId,superToken,{...data,status:'inactive',version:0})).statusCode,400);
    const {password:ignored,...edit}=data;
    assert.equal((await call('PATCH','/api/admin/administrators/'+u.id,superToken,{...edit,status:'inactive',version:u.version})).statusCode,200);
    assert.equal((await auth.getUser(u.id)).disabled,true);
    assert.equal((await call('GET','/api/admin/administrators/audit',superToken)).statusCode,200);
    assert.equal((await call('GET','/api/admin/administrators/audit',staffToken)).statusCode,403);
  });
  test('synthetic upload creates pending manual review without face approval; private image retrieval', async () => {
    assert.equal((await call('POST','/api/pilot/verification-images',workerToken,form())).statusCode,201);
    const v=(await db.collection('worker_verifications').doc(workerId).get()).data();assert.equal(v.faceVerified,false);assert.equal(v.status,'pending');
    const url='/api/admin/verifications/'+workerId+'/image';
    assert.equal((await call('GET',url,workerToken)).statusCode,403);
    assert.equal((await call('GET',url,staffToken)).statusCode,403);
    const r=await call('GET',url,superToken);assert.equal(r.statusCode,200);assert.match(r.headers['cache-control'],/no-store/);
    assert.equal(r.isBase64Encoded,true);assert.deepEqual(Buffer.from(r.body,'base64'),png());
    assert.equal((await call('GET',url+'?key=arbitrary',superToken)).statusCode,400);
    assert.equal((await call('POST','/api/pilot/verification-images',workerToken,form())).statusCode,409);
    assert.equal((await call('POST','/api/verify',workerToken,form())).statusCode,503);
  });
  test('Blobs journal survives upload interruption, deletion failures and interrupted reconciliation', async () => {
    const {createBlobStorage}=require('../src/services/netlifyVerificationStorage');let clock=Date.now(), failDelete=true;
    const wrapped={set:async(...a)=>{await store.set(...a);throw Object.assign(new Error('Injected after upload'),{code:'INJECTED'});},get:(...a)=>store.get(...a),delete:async(...a)=>{if(failDelete)throw Object.assign(new Error('Injected delete'),{code:'INJECTED'});return store.delete(...a);}};
    const adapter=createBlobStorage({database:db,store:wrapped,project:'demo-swiftserve-netlify',environment:'local-recovery'+randomUUID().replace(/[^a-z]/g,'').slice(0,8),now:()=>clock});
    await assert.rejects(adapter.save({owner:workerId,submissionId:randomUUID(),kind:'document',file:{buffer:png(),mimetype:'image/png'}}));
    clock+=7200000;
    assert.equal((await adapter.reconcile({shouldStop:()=>true})).interrupted,true);
    assert.equal((await adapter.reconcile()).failed,1);clock+=10000;failDelete=false;
    assert.equal((await adapter.reconcile()).deleted,1);
    clock+=86400001;assert.equal((await adapter.reconcile()).deleted,1);
  });
  test('storage isolation, authorization metadata and retention block stale object reads', async () => {
    const {createBlobStorage}=require('../src/services/netlifyVerificationStorage');let clock=Date.now();
    const adapter=createBlobStorage({database:db,store,project:'demo-swiftserve-netlify',environment:'local-retention'+randomUUID().replace(/[^a-z]/g,'').slice(0,8),now:()=>clock});
    const submissionId=randomUUID(),keys=[];for(const kind of ['document','selfie'])keys.push(await adapter.save({owner:workerId,submissionId,kind,file:{buffer:png(),mimetype:'image/png'}}));
    await db.runTransaction(tx=>adapter.attach(tx,keys,workerId,submissionId));
    assert.ok((await adapter.read({key:keys[0],owner:workerId,submissionId,kind:'document'})).bytes.length);
    await assert.rejects(adapter.read({key:keys[0],owner:'someone-else',submissionId,kind:'document'}));
    const isolated=createBlobStorage({database:db,store,project:'demo-swiftserve-netlify',environment:'local-other'});
    await assert.rejects(isolated.read({key:keys[0],owner:workerId,submissionId,kind:'document'}));
    clock+=31*86400000;await assert.rejects(adapter.read({key:keys[0],owner:workerId,submissionId,kind:'document'}));
    const result=await adapter.reconcile();assert.equal(result.deleted,2);
  });
  test('payload and remaining execution budget limits reject before processing', async () => {
    const event={body:Buffer.alloc(4*1024*1024+1).toString('base64'),isBase64Encoded:true};
    assert.equal((await handler(event,{})).statusCode,413);
    assert.equal((await handler({},{getRemainingTimeInMillis:()=>1000})).statusCode,503);
  });
  test('untrusted clients cannot read or forge private asset journals or upload quotas', async () => {
    const {createRequire}=require('node:module');
    const clientRequire=createRequire(path.resolve(__dirname,'../../mobile/my_app/rules-tests/package.json'));
    const env=await clientRequire('@firebase/rules-unit-testing').initializeTestEnvironment({projectId:'demo-swiftserve-netlify',firestore:{host:'127.0.0.1',port:8288}});
    try {
      const {doc,getDoc,setDoc}=clientRequire('firebase/firestore'),{assertFails}=clientRequire('@firebase/rules-unit-testing');
      const user=env.authenticatedContext(workerId).firestore();
      const suffix=require('node:crypto').createHash('sha256').update('demo-swiftserve-netlify/local').digest('hex').slice(0,16);
      await assertFails(getDoc(doc(user,'pilot_verification_assets_'+suffix,'any')));
      await assertFails(setDoc(doc(user,'pilot_verification_assets_'+suffix,'forged'),{state:'active',owner:workerId}));
      await assertFails(setDoc(doc(user,'pilot_upload_quotas','forged'),{attempts:0}));
    } finally {await env.cleanup();}
  });
  test('concurrent reconcilers fence deletion and an interrupted deleting claim resumes', async () => {
    const {createBlobStorage}=require('../src/services/netlifyVerificationStorage');let clock=Date.now(),deletes=0;
    const environment='local-concurrent'+randomUUID().replace(/[^a-z]/g,'').slice(0,8);
    const adapter=createBlobStorage({database:db,store:{set:(...a)=>store.set(...a),get:(...a)=>store.get(...a),delete:async(...a)=>{deletes++;return store.delete(...a);}},project:'demo-swiftserve-netlify',environment,now:()=>clock});
    await adapter.save({owner:workerId,submissionId:randomUUID(),kind:'document',file:{buffer:png(),mimetype:'image/png'}});
    clock+=7200000;
    const suffix=require('node:crypto').createHash('sha256').update('demo-swiftserve-netlify/'+environment).digest('hex').slice(0,16);
    const row=(await db.collection('pilot_verification_assets_'+suffix).get()).docs[0];
    await row.ref.update({state:'deleting',leaseToken:'interrupted',leaseUntil:new Date(clock+60000)});
    assert.equal((await adapter.reconcile()).deleted,0);clock+=60001;
    const results=await Promise.all([adapter.reconcile(),adapter.reconcile()]);
    assert.equal(results.reduce((n,r)=>n+r.deleted,0),1);assert.equal(deletes,1);
  });
  test('real journal quarantine, bounded tombstone purge and late orphan recovery',async()=>{
    const {createBlobStorage}=require('../src/services/netlifyVerificationStorage');let clock=Date.now();
    const environment='local-hardening'+randomUUID().replace(/[^a-z]/g,'').slice(0,10);
    const adapter=createBlobStorage({database:db,store,project:'demo-swiftserve-netlify',environment,now:()=>clock});
    const suffix=require('node:crypto').createHash('sha256').update('demo-swiftserve-netlify/'+environment).digest('hex').slice(0,16);
    const assets=db.collection('pilot_verification_assets_'+suffix);
    await assets.doc('000-synthetic-corrupt').set({key:'outside-namespace',dueAt:12,privateDiagnostic:'must not be retained'});
    const key=await adapter.save({owner:workerId,submissionId:randomUUID(),kind:'document',file:{buffer:png(),mimetype:'image/png'}});
    clock+=7200000;const first=await adapter.reconcile();assert.equal(first.quarantined,1);assert.equal(first.deleted,1);
    const quarantined=(await assets.doc('000-synthetic-corrupt').get()).data();assert.equal(quarantined.privateDiagnostic,undefined);
    clock+=8*86400000;assert.equal((await adapter.reconcile()).purged,1);
    await store.set(key,png());assert.equal((await adapter.reconcile()).orphansRecovered,1);
    assert.equal((await adapter.reconcile()).deleted,1);assert.equal(await store.get(key,{type:'arrayBuffer',consistency:'strong'}),null);
  });
  test('real Blobs read cannot return bytes if expiry passes during retrieval',async()=>{
    const {createBlobStorage}=require('../src/services/netlifyVerificationStorage');let clock=Date.now();
    const environment='local-expiryread'+randomUUID().replace(/[^a-z]/g,'').slice(0,10);
    const wrapped={set:(...a)=>store.set(...a),get:async(...a)=>{const bytes=await store.get(...a);clock+=31*86400000;return bytes;},delete:(...a)=>store.delete(...a),list:(...a)=>store.list(...a)};
    const adapter=createBlobStorage({database:db,store:wrapped,project:'demo-swiftserve-netlify',environment,now:()=>clock});
    const submissionId=randomUUID(),keys=[];for(const kind of ['document','selfie'])keys.push(await adapter.save({owner:workerId,submissionId,kind,file:{buffer:png(),mimetype:'image/png'}}));
    await db.runTransaction(tx=>adapter.attach(tx,keys,workerId,submissionId));
    await assert.rejects(adapter.read({key:keys[0],owner:workerId,submissionId,kind:'document'}),{status:404});
  });
});
