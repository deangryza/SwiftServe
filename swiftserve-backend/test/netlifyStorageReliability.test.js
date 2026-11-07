const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHash, randomUUID } = require('node:crypto');
const { createBlobStorage } = require('../src/services/netlifyVerificationStorage');
const PROJECT = 'demo-swiftserve-netlify', DAY = 86400000;
const hash = s => createHash('sha256').update(s).digest('hex');
const stamp = n => ({ toMillis: () => n });
const normalize = v => v instanceof Date ? stamp(v.getTime()) : Array.isArray(v) ? v.map(normalize) : v && typeof v === 'object' && !v.toMillis ? Object.fromEntries(Object.entries(v).map(([k,x]) => [k,normalize(x)])) : v;
// Serial transactions model atomic claims; injected store hooks exercise takeover
// between the actual object operation and the acknowledgment transaction.
function fixture() {
  const records = new Map(); let clock = 1000, tail = Promise.resolve();
  const ref = path => ({ id: path.split('/').at(-1), path,
    get: async () => snap(path), create: async d => { assert.ok(!records.has(path)); records.set(path,normalize(d)); },
    update: async d => { assert.ok(records.has(path)); records.set(path,{...records.get(path),...normalize(d)}); } });
  const snap = path => ({ ref: ref(path), id: path.split('/').at(-1), exists: records.has(path), data: () => records.get(path) });
  function query(name, after, max = Infinity, filters = []) {
    return { doc: id => ref(name+'/'+id), where: (field,op,value) => query(name,after,max,[...filters,[field,value]]), orderBy: () => query(name,after,max,filters), startAfter: id => query(name,id,max,filters), limit: n => query(name,after,n,filters),
      get: async () => { const docs = [...records.keys()].filter(p => p.startsWith(name+'/') && !p.slice(name.length+1).includes('/') && (!after || p.split('/').at(-1)>after) && filters.every(([field,v])=>records.get(p)[field]?.toMillis?.()<=v.getTime())).sort().slice(0,max).map(snap); return {docs,size:docs.length}; } };
  }
  const db = { collection: name => query(name), runTransaction: fn => {
    const run = tail.then(async () => { const writes=[];const result=await fn({get:r=>r.get(),set:(r,d)=>writes.push(()=>records.set(r.path,normalize(d))),update:(r,d)=>writes.push(()=>records.set(r.path,{...records.get(r.path),...normalize(d)})),delete:r=>writes.push(()=>records.delete(r.path))}); writes.forEach(w=>w()); return result; }); tail=run.catch(()=>{});return run;
  } };
  const objects = new Map();
  const store = { set: async (k,b)=>objects.set(k,b), get: async k=>objects.get(k)||null, delete: async k=>objects.delete(k),
    list: ({prefix}) => ({async *[Symbol.asyncIterator]() {yield {blobs:[...objects.keys()].filter(k=>k.startsWith(prefix)).sort().map(key=>({key}))};}}) };
  const environment = 'local';
  const assets = 'pilot_verification_assets_'+hash(PROJECT+'/'+environment).slice(0,16);
  function asset({owner='worker',expired=true,state='stored'}={}) {
    const submissionId=randomUUID(),key=`verification-v1/${PROJECT}/${environment}/${hash(owner)}/${submissionId}/document`;
    const data={project:PROJECT,environment,key,owner,submissionId,kind:'document',state,createdAt:stamp(clock-2*DAY),expiresAt:stamp(expired?clock-1:clock+DAY),dueAt:stamp(expired?clock-1:clock+DAY),attempts:0,contentType:'image/png'};
    const path=assets+'/'+hash(key);records.set(path,data);objects.set(key,Buffer.from('synthetic'));return {path,data,key};
  }
  const adapter = () => createBlobStorage({database:db,store,project:PROJECT,environment,now:()=>clock});
  return {records,db,store,objects,asset,adapter,assets,get clock(){return clock;},advance:n=>clock+=n};
}

test('malformed query-eligible record is quarantined without blocking a valid asset', async () => {
  const f=fixture(); f.records.set(f.assets+'/000-corrupt',{key:'outside-namespace',project:PROJECT,environment:'local',dueAt:stamp(0),rawDiagnostic:'x'.repeat(10000)});
  f.asset(); const r=await f.adapter().reconcile();
  assert.equal(r.quarantined,1);assert.equal(r.deleted,1);const bad=f.records.get(f.assets+'/000-corrupt');assert.equal(bad.state,'quarantined');assert.ok(JSON.stringify(bad).length<2000);assert.equal(bad.rawDiagnostic,undefined);
});
test('missing and numeric timestamps are found and quarantined rather than hidden by due queries', async () => {
  const f=fixture();for(const value of [undefined,null,2]){const a=f.asset();a.data.dueAt=value;}
  const r=await f.adapter().reconcile();assert.equal(r.quarantined,3);
});
test('expiry while retrieving bytes rejects the image', async () => {
  const f=fixture(),a=f.asset({expired:false,state:'active'});f.store.get=async()=>{f.advance(2*DAY);return Buffer.from('synthetic');};
  await assert.rejects(f.adapter().read({key:a.key,owner:'worker',submissionId:a.data.submissionId,kind:'document'}),{status:404});
});
test('takeover during delete is not acknowledged or counted by the stale owner', async () => {
  const f=fixture(),a=f.asset();f.store.delete=async()=>{f.records.get(a.path).leaseToken='new-owner';};
  const r=await f.adapter().reconcile();assert.equal(r.deleted,0);assert.equal(r.lostOwnership,1);assert.equal(f.records.get(a.path).leaseToken,'new-owner');
});
test('delete failure remains retryable and a later successful acknowledgment is counted', async () => {
  const f=fixture(),a=f.asset();let fail=true;f.store.delete=async k=>{if(fail)throw Object.assign(new Error('private details'),{code:'SYNTHETIC'});f.objects.delete(k);};
  assert.equal((await f.adapter().reconcile()).failed,1);assert.equal(f.records.get(a.path).state,'delete_pending');
  fail=false;f.advance(DAY);assert.equal((await f.adapter().reconcile()).deleted,1);
});
test('bounded pages progress past future records and resume after interruption', async () => {
  const f=fixture();for(let i=0;i<8;i++)f.asset({expired:false});for(let i=0;i<7;i++)f.asset();
  let deleted=0;for(let i=0;i<6;i++)deleted+=(await f.adapter().reconcile({limit:3})).deleted;assert.equal(deleted,7);
});
test('successful tombstones and expired quota records are purged; a late orphan is rediscovered', async () => {
  const f=fixture(),a=f.asset();assert.equal((await f.adapter().reconcile()).deleted,1);
  f.records.set('pilot_upload_quotas/old',{owner:'worker',attempts:5,updatedAt:stamp(0),expiresAt:stamp(f.clock-1)});
  f.advance(8*DAY);const r=await f.adapter().reconcile();assert.equal(r.purged,1);assert.equal(r.quotaPurged,1);assert.equal(f.records.has(a.path),false);
  f.objects.set(a.key,Buffer.from('late synthetic write'));const recovered=await f.adapter().reconcile();assert.equal(recovered.orphansRecovered,1);
  assert.equal((await f.adapter().reconcile()).deleted,1);assert.equal(f.objects.has(a.key),false);
});
test('expired owner cannot acknowledge or overwrite progress after a concurrent takeover', async()=>{
  const f=fixture();f.asset();let first=true,newOwnerResult;
  f.store.delete=async key=>{if(first){first=false;f.advance(60001);newOwnerResult=await f.adapter().reconcile();}f.objects.delete(key);};
  const stale=await f.adapter().reconcile();assert.equal(newOwnerResult.deleted,1);assert.equal(stale.deleted,0);assert.ok(stale.lostOwnership>=1);
  assert.equal((await f.adapter().reconcile()).deleted,0);
});
test('quarantine expires after grace; retry failures retain recovery until acknowledged', async()=>{
  const f=fixture(),a=f.asset();a.data.dueAt=null;
  assert.equal((await f.adapter().reconcile()).quarantined,1);assert.ok(f.objects.has(a.key));
  f.advance(31*DAY);f.store.delete=async()=>{throw Object.assign(new Error('synthetic'),{code:'RETRY'});};
  assert.equal((await f.adapter().reconcile()).failed,1);assert.equal(f.records.get(a.path).state,'delete_pending');
  f.advance(100*DAY);assert.equal((await f.adapter().reconcile()).failed,1);assert.ok(f.records.has(a.path));
  f.store.delete=async key=>f.objects.delete(key);f.advance(DAY);assert.equal((await f.adapter().reconcile()).deleted,1);
});
test('interruption checkpoints completed candidates and resumes without skipping', async()=>{
  const f=fixture();for(let i=0;i<6;i++)f.asset();let checks=0;
  const stopped=await f.adapter().reconcile({shouldStop:()=>++checks>2});assert.equal(stopped.interrupted,true);assert.equal(stopped.deleted,2);
  assert.equal((await f.adapter().reconcile()).deleted,4);
});
test('prefix inventory resumes after restart and recovers a backlog larger than one batch', async()=>{
  const f=fixture();for(let i=0;i<7;i++){const a=f.asset();f.records.delete(a.path);}
  let recovered=0,deleted=0;
  for(let i=0;i<150 && (recovered<7 || deleted<7);i++){const r=await f.adapter().reconcile({limit:2});recovered+=r.orphansRecovered;deleted+=r.deleted;}
  assert.equal(recovered,7);assert.equal(deleted,7);assert.equal(f.objects.size,0);
});
test('an empty intermediate inventory page is not treated as the end of listing',async()=>{
  const f=fixture(),a=f.asset();f.records.delete(a.path);
  f.store.list=({prefix})=>({async *[Symbol.asyncIterator](){yield {blobs:[]};yield {blobs:[]};yield {blobs:[{key:a.key}]};}});
  const r=await f.adapter().reconcile();assert.equal(r.orphansRecovered,0);assert.equal(r.possiblyMore,true);
  const state=[...f.records.entries()].find(([p])=>p.endsWith('/inventory'))[1];assert.ok(state.pending.length>1);
});
