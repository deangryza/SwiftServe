const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises'), os = require('node:os'), path = require('node:path');
const { createCanvas } = require('canvas');
const express = require('express'), request = require('supertest');
const { createDocumentService, acceptedDocument } = require('../src/services/documentSuitabilityService');
Object.assign(process.env,{GCLOUD_PROJECT:'demo-swiftserve-cleanup',FIRESTORE_EMULATOR_HOST:'127.0.0.1:8187',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'});
let records, writes, directory, service;
const ref = (collection, id) => ({ collection, id, get: async () => ({ exists: records.has(`${collection}/${id}`), data: () => records.get(`${collection}/${id}`) }) });
const db = { projectId:'demo-swiftserve-cleanup',databaseId:'(default)',collection: collection => ({ doc: id => ref(collection,id),
  orderBy: () => ({ orderBy(){return this;},startAfter(){return this;},limit(){return this;},get: async () => ({ docs: [...records].filter(([key]) => key.startsWith(`${collection}/`)).map(([key,value]) => ({ id:key.split('/')[1],data: () => value })) }) }),
  }),
  async runTransaction(fn) { const pending = []; const result = await fn({ get: r => r.get(), set: (r, value) => pending.push([`${r.collection}/${r.id}`,value]) });
    for (const [key,value] of pending) records.set(key,value); writes.push(...pending); return result; },
};
const audit = (tx, actor, action, uid, details) => tx.set(ref('admin_audit_logs', `${writes.length}-${action}`), { actor: actor.uid, action, uid, ...details });
const config = require.resolve('../src/config/firebase');
require.cache[config] = { id: config, filename: config, loaded: true, exports: { db, storage: null,
  auth: { verifyIdToken: async (token, revoked) => { if (!['worker','client','reviewer','viewer','self'].includes(token)) throw Error('invalid'); return { uid: token === 'self' ? 'worker' : token, admin: token === 'reviewer' || token === 'self', staff: token === 'viewer' }; },
    getUser: async uid => ({ uid, disabled: false, email: `${uid}@example.test`, customClaims: { admin: ['reviewer','worker'].includes(uid), staff: uid === 'viewer' } }) } } };
const routers = require('../src/routes/documentSuitabilityRoutes');
const app = express(); app.use(express.json()); app.use('/document', routers.user); app.use('/review', routers.review);
app.use('/worker-review', require('../src/routes/adminVerificationRoutes'));
let comparisons=0;
app.use('/api', require('../src/routes/verificationRoutes')({
  authenticate: (req,_res,next)=>{req.user={uid:req.headers.authorization?.slice(7)||'worker'};next();},
  attemptLimiter: (_req,_res,next)=>next(),
  compare: async ()=>{ comparisons++;return {match:true,band:'strong',similarity:90,status:'pending'}; },
}));
beforeEach(async () => {
  records = new Map([['users/worker',{ role:'worker' }],['users/client',{ role:'client' }],['admin_accounts/viewer',{ status:'active', email:'viewer@example.test', permissions:['verification.view'] }]]);
  writes=[]; comparisons=0; directory=await fs.mkdtemp(path.join(os.tmpdir(),'swiftserve-document-test-'));
  service=createDocumentService({ db, uploadsDir:directory, audit });
  process.env.UPLOADS_DIR=directory;
});
afterEach(async () => { assert.ok(directory.startsWith(path.join(os.tmpdir(),'swiftserve-document-test-'))); await fs.rm(directory,{recursive:true,force:true}); });
const image = label => {
  const canvas=createCanvas(300,180), c=canvas.getContext('2d'); c.fillStyle='white';c.fillRect(0,0,300,180);
  if(label==='landscape'){c.fillStyle='skyblue';c.fillRect(0,0,300,100);c.fillStyle='green';c.fillRect(0,100,300,80);}
  else if(label==='selfie'){c.fillStyle='gray';c.beginPath();c.ellipse(150,90,65,80,0,0,7);c.fill();}
  else if(label==='screenshot'){c.fillStyle='navy';c.fillRect(0,0,300,30);c.fillStyle='lightgray';c.fillRect(20,60,260,90);}
  else if(label!=='blank'){c.strokeStyle='gray';c.strokeRect(10,10,280,160);c.fillStyle='lightgray';c.fillRect(20,55,60,90);for(let y=65;y<150;y+=15)c.fillRect(100,y,150,3);}
  if(label!=='blank'){c.fillStyle='black';c.fillText(`SYNTHETIC ONLY: ${label}`,20,40);}
  return { buffer:canvas.toBuffer('image/png'),mimetype:'image/png' };
};
const submit = (file=image('card'), previous={}) => service.submit('worker',{idType:'National ID',...previous},file);
const decision = (record,status='DOCUMENT_ACCEPTED',reasonCode='SUITABLE') => ({sessionId:record.sessionId,attemptId:record.attemptId,status,reasonCode});
for (const label of ['selfie','landscape','screenshot','unrelated document','synthetic ID','blurred document','cropped document','blank']) {
  test(`${label} is unclassified review-required, never automatically accepted`, async () => {
    const file=image(label), record=await submit(file);
    assert.equal(record.status,'DOCUMENT_REVIEW_REQUIRED');
    await assert.rejects(acceptedDocument(db,'worker',record.sessionId,record.attemptId,file.buffer), e=>e.code==='DOCUMENT_REVIEW_REQUIRED');
    assert.ok(writes.every(([key])=>!key.startsWith('users/')&&!key.startsWith('worker_profiles/')));
  });
}
test('transaction retries preserve exact digest, pending outcome and account checks',async()=>{
  const original = db.runTransaction;
  const file = image('synthetic retry'), expected = require('node:crypto').createHash('sha256').update(file.buffer).digest('hex');
  let callbacks = 0;
  try {
    db.runTransaction = async fn => {
      for (let i=0;i<2;i++) { callbacks++; await fn({get:r=>r.get(),set(){}}); }
      callbacks++; return original.call(db,fn);
    };
    const result=await submit(file);
    assert.equal(callbacks,3); assert.equal(result.imageDigest,expected);
    assert.equal(result.status,'DOCUMENT_REVIEW_REQUIRED');
    db.runTransaction = async fn => {
      await fn({get:r=>r.get(),set(){}});
      records.get('users/worker').status='suspended';
      return original.call(db,fn);
    };
    await assert.rejects(service.submit('worker',{idType:'National ID',...result},file),e=>e.code==='DOCUMENT_ACCOUNT_REQUIRED');
    assert.equal((await service.refFor('worker').get()).data().attemptId,result.attemptId);
  } finally { db.runTransaction=original; }
});

test('failed transaction removes its new synthetic temporary image',async()=>{
  const original=db.runTransaction;
  try {
    db.runTransaction=async()=>{throw Error('synthetic interruption');};
    await assert.rejects(submit(),/synthetic interruption/);
    const folder=path.join(directory,'document_suitability','worker');
    assert.deepEqual(await fs.readdir(folder),[]);
  } finally { db.runTransaction=original; }
});

test('unreadable and unsupported uploads fail without an accepted record',async()=>{
  for(const file of [{buffer:Buffer.from('bad'),mimetype:'image/png'},{buffer:Buffer.from('<svg/>'),mimetype:'image/svg+xml'},{buffer:Buffer.from([137,80,78,71,13,10,26,10]),mimetype:'image/png'}]){
    await assert.rejects(submit(file),e=>['INVALID_DOCUMENT_UPLOAD','DOCUMENT_UNREADABLE'].includes(e.code));
  }
  assert.equal(records.has('document_suitability/worker'),false);
});

test('National ID above 5 MB is preserved for review; 20 MB bound and other ID limits remain enforced',async()=>{
  const small=image('large synthetic ID');
  const file={...small,buffer:Buffer.concat([small.buffer,Buffer.alloc(6*1024*1024)])};
  const record=await submit(file);
  assert.equal(record.status,'DOCUMENT_REVIEW_REQUIRED');
  assert.equal(record.imageDigest,require('node:crypto').createHash('sha256').update(file.buffer).digest('hex'));
  await assert.rejects(service.submit('worker',{idType:'Passport'},file),e=>e.code==='INVALID_DOCUMENT_UPLOAD');
  await assert.rejects(submit({...small,buffer:Buffer.alloc(20*1024*1024+1)}),e=>e.code==='INVALID_DOCUMENT_UPLOAD');
});
test('acceptance binds exact image, owner, session and attempt without government or worker writes',async()=>{
  const file=image('id'), record=await submit(file);
  await service.review('worker',{uid:'reviewer'},decision(record));
  await acceptedDocument(db,'worker',record.sessionId,record.attemptId,file.buffer);
  for(const args of [['client',record.sessionId,record.attemptId,file.buffer],['worker','wrong',record.attemptId,file.buffer],['worker',record.sessionId,'wrong',file.buffer],['worker',record.sessionId,record.attemptId,image('changed').buffer]])await assert.rejects(acceptedDocument(db,...args));
  assert.ok(writes.some(([key,value])=>key.startsWith('admin_audit_logs/')&&value.action==='document.reviewed'));
  assert.deepEqual(records.get('users/worker'),{role:'worker'});
  assert.equal(records.has('worker_verifications/worker'),false);
});
test('rejection/unreadable permits replacement and stale reviewer cannot overwrite it',async()=>{
  for(const [status,reason] of [['DOCUMENT_REJECTED','NOT_SUPPORTED'],['DOCUMENT_UNREADABLE','UNREADABLE']]){
    records.delete('document_suitability/worker');
    const first=await submit();await service.review('worker',{uid:'reviewer'},decision(first,status,reason));
    const second=await submit(image('replacement'),first);
    assert.equal(second.sessionId,first.sessionId);assert.notEqual(second.attemptId,first.attemptId);
    assert.equal(second.status,'DOCUMENT_REVIEW_REQUIRED');assert.equal(second.history.length,1);
    await assert.rejects(service.review('worker',{uid:'reviewer'},decision(first)),e=>e.code==='DOCUMENT_ATTEMPT_STALE');
    assert.equal((await service.get('worker')).attemptId,second.attemptId);
  }
});
test('mock evidence, self-review and expired attempts cannot be accepted',async()=>{
  const record=await submit();
  await assert.rejects(service.review('worker',{uid:'worker'},decision(record)),e=>e.status===403);
  records.get('document_suitability/worker').providerType='MOCK';
  await assert.rejects(service.review('worker',{uid:'reviewer'},decision(record)),e=>e.code==='DOCUMENT_NOT_REVIEWABLE');
  assert.equal((await service.get('worker')).mock,true);
  records.get('document_suitability/worker').expiresAt=new Date(0);
  await assert.rejects(service.review('worker',{uid:'reviewer'},decision(record)),e=>e.code==='DOCUMENT_SESSION_EXPIRED');
});
test('HTTP enforces reviewer permissions and rejects forged statuses, ownership and government fields',async()=>{
  const record=await submit();
  await request(app).patch('/review/worker').send(decision(record)).expect(401);
  for(const token of ['client','viewer','self'])await request(app).patch('/review/worker').set('Authorization',`Bearer ${token}`).send(decision(record)).expect(403);
  await request(app).patch('/review/worker').set('Authorization','Bearer reviewer').send({...decision(record),government:{status:'AUTHENTICATED'}}).expect(400);
  await request(app).patch('/review/client').set('Authorization','Bearer reviewer').send(decision(record)).expect(409);
  await request(app).post('/document').set('Authorization','Bearer worker').field('status','DOCUMENT_ACCEPTED').field('idType','National ID').attach('document',image('synthetic').buffer,{filename:'id.png',contentType:'image/png'}).expect(400);
  await request(app).patch('/review/worker').set('Authorization','Bearer reviewer').send(decision(record)).expect(200);
  const own=await request(app).get('/document').set('Authorization','Bearer worker').expect(200);
  assert.equal(own.body.item.status,'DOCUMENT_ACCEPTED');
  const other=await request(app).get('/document?uid=worker').set('Authorization','Bearer client').expect(200);
  assert.equal(other.body.item.status,'DOCUMENT_PENDING');
});

test('suitability approval alone cannot approve a worker through the existing decision endpoint',async()=>{
  const record=await submit();await service.review('worker',{uid:'reviewer'},decision(record));
  const binding=await acceptedDocument(db,'worker',record.sessionId,record.attemptId,image('card').buffer);
  const { newEvidence }=require('../src/services/workerVerificationPolicy');
  records.set('worker_verifications/worker',{...newEvidence({match:true,band:'strong',similarity:90,distance:.4},{workerId:'worker',submissionId:'synthetic-worker-attempt',now:new Date(),thresholds:{autoVerifyMin:80,reviewMin:60}}),status:'pending',documentBinding:binding,storageBackend:'local'});
  const response=await request(app).patch('/worker-review/worker').set('Authorization','Bearer reviewer').send({status:'verified'}).expect(409);
  assert.equal(response.body.code,'VERIFICATION_REQUIREMENTS_NOT_MET');
  assert.equal(records.get('users/worker').verificationStatus,undefined);
});

test('public face endpoint cannot bypass pending review or substitute image, session, attempt or declared type',async()=>{
  const file=image('synthetic ID'), record=await submit(file);
  const post=(fields={},bytes=file.buffer,uid='worker')=>{
    const builder=request(app).post('/api/verify').set('Authorization',`Bearer ${uid}`);
    const values={idType:'National ID',idNumber:'SYNTHETIC',documentSessionId:record.sessionId,documentAttemptId:record.attemptId,...fields};
    for(const [key,value]of Object.entries(values))if(value!==null)builder.field(key,value);
    return builder.attach('document',bytes,{filename:'doc.png',contentType:'image/png'}).attach('selfie',file.buffer,{filename:'selfie.png',contentType:'image/png'});
  };
  await post().expect(409);assert.equal(comparisons,0);
  await service.review('worker',{uid:'reviewer'},decision(record));
  await post({documentSessionId:null,documentAttemptId:null}).expect(409);
  await post({documentSessionId:'wrong'}).expect(409);await post({documentAttemptId:'wrong'}).expect(409);
  await post({},image('changed').buffer).expect(409);await post({},file.buffer,'client').expect(409);
  await post({idType:'Passport'}).expect(409);assert.equal(comparisons,0);
  await post().expect(201);assert.equal(comparisons,1);
});

test('live/unknown projects, remote hosts and mock mode fail closed before document operations',async()=>{
  const { documentEnvironment }=require('../src/services/documentSuitabilityService');
  for(const projectId of ['swiftserve-production','swiftserve-staging-2026','unknown'])assert.throws(()=>documentEnvironment({...db,projectId}),e=>e.code==='DOCUMENT_DEMO_ENVIRONMENT_REQUIRED');
  const before=process.env.FIRESTORE_EMULATOR_HOST;
  try{process.env.FIRESTORE_EMULATOR_HOST='remote.example:8187';assert.throws(()=>documentEnvironment(db));}
  finally{process.env.FIRESTORE_EMULATOR_HOST=before;}
  const mockBefore=process.env.NATIONAL_ID_MOCK_ENABLED;
  try{process.env.NATIONAL_ID_MOCK_ENABLED='true';await assert.rejects(service.get('worker'),e=>e.code==='USE_MOCK_IDENTITY_SESSION');}
  finally{if(mockBefore===undefined)delete process.env.NATIONAL_ID_MOCK_ENABLED;else process.env.NATIONAL_ID_MOCK_ENABLED=mockBefore;}
});

test('private images require owner/reviewer authorization and the current unexpired attempt',async()=>{
  const record=await submit();
  await request(app).get('/document/image').expect(401);
  const imagePath=`/document/image?attemptId=${record.attemptId}`;
  const own=await request(app).get(imagePath).set('Authorization','Bearer worker').expect(200);
  assert.match(own.headers['cache-control'],/no-store/);
  await request(app).get(`${imagePath}&uid=worker`).set('Authorization','Bearer client').expect(404);
  await request(app).get(`/review/worker/image?attemptId=${record.attemptId}`).set('Authorization','Bearer client').expect(403);
  await request(app).get(`/review/worker/image?attemptId=${record.attemptId}`).set('Authorization','Bearer viewer').expect(200);
  await request(app).get('/document/image?attemptId=old').set('Authorization','Bearer worker').expect(409);
  const list=await request(app).get('/review').set('Authorization','Bearer viewer').expect(200);
  assert.equal(list.body.items[0].ownerId,'worker');assert.equal(list.body.next,null);
  await request(app).get('/review?after=not-json').set('Authorization','Bearer viewer').expect(400);
  records.get('document_suitability/worker').expiresAt=new Date(0);
  await request(app).get(imagePath).set('Authorization','Bearer worker').expect(404);
});
