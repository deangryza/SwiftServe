const { test } = require('node:test');
const assert = require('node:assert/strict');
test('document review: Firestore fencing, concurrent review and denied direct client writes', { skip: process.env.RUN_DOCUMENT_EMULATOR_TESTS !== 'true', timeout: 120000 }, async () => {
  const project='demo-swiftserve-cleanup';
  assert.equal(process.env.GCLOUD_PROJECT,project);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8187');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
  assert.ok(!process.env.GOOGLE_APPLICATION_CREDENTIALS);
  const { initializeApp,deleteApp }=require('firebase-admin/app');
  const instance=initializeApp({projectId:project},'document-review-test');
  const db=require('firebase-admin/firestore').getFirestore(instance);
  assert.equal(db.databaseId,'(default)');
  const { createRequire }=require('node:module'),path=require('node:path'),fs=require('node:fs/promises'),os=require('node:os');
  const sdk=createRequire(path.resolve(__dirname,'../../mobile/my_app/rules-tests/package.json'));
  const a=sdk('firebase/app'),auth=sdk('firebase/auth'),store=sdk('firebase/firestore');
  const client=a.initializeApp({projectId:project,apiKey:'synthetic-key'},'document-review-client');
  const signed=auth.getAuth(client);auth.connectAuthEmulator(signed,'http://127.0.0.1:9099',{disableWarnings:true});
  const uid=(await auth.signInAnonymously(signed)).user.uid;
  const clientDb=store.getFirestore(client);store.connectFirestoreEmulator(clientDb,'127.0.0.1',8187);
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'swiftserve-document-emulator-'));
  try {
    await db.collection('users').doc(uid).set({role:'worker',verificationStatus:'pending'});
    const { createDocumentService,acceptedDocument }=require('../src/services/documentSuitabilityService');
    const service=createDocumentService({db,uploadsDir:directory,audit:(tx,actor,action,owner,details)=>tx.set(db.collection('admin_audit_logs').doc(),{actor:actor.uid,action,owner,...details})});
    const canvas=require('canvas').createCanvas(300,200);canvas.getContext('2d').fillRect(10,10,280,180);
    const file={buffer:canvas.toBuffer('image/png'),mimetype:'image/png'};
    const first=await service.submit(uid,{idType:'National ID'},file);
    const body={sessionId:first.sessionId,attemptId:first.attemptId,status:'DOCUMENT_ACCEPTED',reasonCode:'SUITABLE'};
    const results=await Promise.allSettled([service.review(uid,{uid:'synthetic-reviewer-a'},body),service.review(uid,{uid:'synthetic-reviewer-b'},body)]);
    assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
    await acceptedDocument(db,uid,first.sessionId,first.attemptId,file.buffer);
    const binding=await acceptedDocument(db,uid,first.sessionId,first.attemptId,file.buffer);
    let replacement;
    await assert.rejects(require('../src/services/faceVerificationService').compareAndCreateSubmission({
      uid,db,storage:null,blobStorage:null,uploadsDir:directory,document:file,selfie:file,idType:'National ID',idNumber:'SYNTHETIC',documentBinding:binding,
      verify:async()=>{replacement=await service.submit(uid,{idType:'National ID',sessionId:first.sessionId,attemptId:first.attemptId},file);return {match:true,band:'strong',similarity:90,confidence:90,distance:.4};},
    }),e=>e.code==='DOCUMENT_ATTEMPT_STALE');
    assert.equal((await db.collection('worker_verifications').doc(uid).get()).exists,false);
    assert.equal(replacement.status,'DOCUMENT_REVIEW_REQUIRED');
    await assert.rejects(service.review(uid,{uid:'synthetic-reviewer'},body),e=>e.code==='DOCUMENT_ATTEMPT_STALE');
    await assert.rejects(acceptedDocument(db,uid,first.sessionId,first.attemptId,file.buffer));
    const record=store.doc(clientDb,'document_suitability',uid);
    for(const operation of [()=>store.getDoc(record),()=>store.setDoc(record,{status:'DOCUMENT_ACCEPTED'}),()=>store.updateDoc(record,{status:'DOCUMENT_ACCEPTED'}),()=>store.deleteDoc(record)]) {
      await assert.rejects(operation(),e=>e.code==='permission-denied');
    }
    assert.equal((await db.collection('users').doc(uid).get()).data().verificationStatus,'pending');
  } finally {
    await store.terminate(clientDb);await a.deleteApp(client);await db.terminate();await deleteApp(instance);
    assert.ok(directory.startsWith(path.join(os.tmpdir(),'swiftserve-document-emulator-')));await fs.rm(directory,{recursive:true,force:true});
  }
});
