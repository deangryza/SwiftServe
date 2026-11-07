const {test,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const express=require('express');
const request=require('supertest');
let role,prior,quota,decodes,writes,verified,quotaChecked;
const config=require.resolve('../src/config/firebase'),storage=require.resolve('../src/services/netlifyVerificationStorage'),canvas=require.resolve('canvas');
const original=new Map([config,storage,canvas].map(p=>[p,require.cache[p]]));
const oldMode=process.env.SWIFTSERVE_NETLIFY_PILOT;process.env.SWIFTSERVE_NETLIFY_PILOT='true';
const db={collection:name=>({doc:id=>({name,id,get:async()=>({exists:name==='users'||(name==='worker_verifications'&&prior!==null)||name==='pilot_upload_quotas',data:()=>name==='users'?{role,verificationStatus:'pending'}:name==='worker_verifications'?prior:{attempts:quota}})})}),runTransaction:async fn=>fn({get:async r=>{if(r.name==='pilot_upload_quotas')quotaChecked=true;return r.get();},set:(_r,d)=>{writes.push(d);},update:()=>{}})};
require.cache[config]={id:config,filename:config,loaded:true,exports:{db,auth:{verifyIdToken:async(_t,revoke)=>{verified=revoke;return{uid:'synthetic'};}}}};
require.cache[storage]={id:storage,filename:storage,loaded:true,exports:{getBlobStorage:()=>({save:async({kind})=>kind,attach:async()=>{},requestDeletion:async()=>{}})}};
require.cache[canvas]={id:canvas,filename:canvas,loaded:true,exports:{loadImage:async()=>{assert.equal(quotaChecked,true);decodes++;return{width:32,height:32};}}};
beforeEach(()=>{role='worker';prior=null;quota=0;decodes=0;writes=[];verified=false;quotaChecked=false;});
after(()=>{for(const [p,v]of original){if(v)require.cache[p]=v;else delete require.cache[p];}if(oldMode===undefined)delete process.env.SWIFTSERVE_NETLIFY_PILOT;else process.env.SWIFTSERVE_NETLIFY_PILOT=oldMode;});
function app(){const r=require.resolve('../src/routes/netlifyPilotRoutes');delete require.cache[r];const a=express();a.use('/api/pilot',require(r));a.use((e,_q,s,_n)=>s.status(e.status||500).json({code:e.code}));return a;}
function pair(){const b=Buffer.alloc(40);Buffer.from([137,80,78,71,13,10,26,10]).copy(b);b.writeUInt32BE(13,8);b.write('IHDR',12);b.writeUInt32BE(32,16);b.writeUInt32BE(32,20);return request(app()).post('/api/pilot/verification-images').set('Authorization','Bearer synthetic').field('idType','Synthetic').field('idNumber','TEST').attach('document',b,{filename:'synthetic.png',contentType:'image/png'}).attach('selfie',b,{filename:'synthetic.png',contentType:'image/png'});}
test('non-worker is rejected before quota reservation or native decoding',async()=>{role='client';await pair().expect(403);assert.equal(decodes,0);assert.equal(writes.length,0);assert.equal(verified,true);});
test('already active verification is rejected before decoding',async()=>{prior={status:'pending'};await pair().expect(409);assert.equal(decodes,0);assert.equal(writes.length,0);});
test('daily quota exhaustion is rejected before decoding or storage',async()=>{quota=5;await pair().expect(429);assert.equal(decodes,0);assert.equal(writes.length,0);});
test('eligible upload reserves bounded quota first and preserves manual pending review',async()=>{await pair().expect(201);assert.equal(decodes,2);assert.ok(writes[0].expiresAt instanceof Date);assert.equal(writes.at(-1).faceVerified,false);assert.equal(writes.at(-1).status,'pending');});
