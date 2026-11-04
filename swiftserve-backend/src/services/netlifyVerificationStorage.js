const { createHash, randomUUID } = require('node:crypto');
const { inspectImage } = require('./verificationImagePolicy');
const DAY = 86400000;
const TOMBSTONE_DAYS = 7, QUARANTINE_DAYS = 30;
const hash = s => createHash('sha256').update(s).digest('hex');
const fail = () => Object.assign(new Error('Private verification asset unavailable.'), { status: 404 });
const millis = value => {
  if (!value || typeof value.toMillis !== 'function') return null;
  const n = value.toMillis(); return Number.isFinite(n) ? n : null;
};

function createBlobStorage({ database, store, project, environment = 'local', now = () => Date.now() }) {
  // The pilot is deliberately incapable of selecting production storage.
  if (project !== 'demo-swiftserve-netlify' || !/^local(?:-[a-z]+)?$/.test(environment)) throw new Error('BLOB_PILOT_SCOPE_REQUIRED');
  const prefix = `verification-v1/${project}/${environment}/`;
  const namespace = hash(project + '/' + environment).slice(0,16);
  const assets = database.collection(`pilot_verification_assets_${namespace}`);
  const maintenance = database.collection(`pilot_verification_maintenance_${namespace}`);
  const parseKey = key => {
    if (typeof key !== 'string' || !key.startsWith(prefix) || key.length > 240) return null;
    const match = /^([a-f0-9]{64})\/([a-f0-9-]{36})\/(document|selfie)$/.exec(key.slice(prefix.length));
    return match && { ownerHash: match[1], submissionId: match[2], kind: match[3] };
  };
  const reference = key => {
    if (!parseKey(key)) throw fail();
    return assets.doc(hash(key));
  };
  const valid = (d, id) => {
    const p = parseKey(d?.key);
    return p && id === hash(d.key) && d.project === project && d.environment === environment &&
      d.submissionId === p.submissionId && d.kind === p.kind &&
      (d.orphan === true ? d.ownerHash === p.ownerHash : typeof d.owner === 'string' && d.owner.length > 0 && d.owner.length <= 128 && !d.owner.includes('/') && hash(d.owner) === p.ownerHash) &&
      ['uploading','stored','active','deleting','delete_pending','deleted'].includes(d.state) &&
      ['createdAt','expiresAt','dueAt'].every(k => millis(d[k]) !== null) &&
      ['leaseUntil','deletedAt','purgeAfter'].every(k => d[k] == null || millis(d[k]) !== null) &&
      Number.isSafeInteger(d.attempts) && d.attempts >= 0 && d.attempts <= 1000000 &&
      (d.state !== 'deleted' || millis(d.purgeAfter) !== null || d.deletedAt == null);
  };
  async function save({ owner, submissionId, kind, file }) {
    if (typeof owner !== 'string' || !owner || owner.length > 128 || owner.includes('/') || !/^[a-f0-9-]{36}$/.test(submissionId) || !['document','selfie'].includes(kind)) throw fail();
    const image = inspectImage(file);
    const key = `${prefix}${hash(owner)}/${submissionId}/${kind}`;
    const ref = reference(key), time = now();
    // Journal BEFORE object I/O. Never reuse keys, even after interrupted writes.
    await ref.create({ key, project, environment, owner, submissionId, kind, ...image, state: 'uploading',
      createdAt: new Date(time), expiresAt: new Date(time + 30*DAY), dueAt: new Date(time + 3600000), attempts: 0 });
    await store.set(key, file.buffer, { metadata: { contentType: image.contentType } });
    await database.runTransaction(async tx => {
      const snapshot = await tx.get(ref);
      if (snapshot.data()?.state !== 'uploading') throw fail();
      tx.update(ref, { state: 'stored' });
    });
    return key;
  }
  async function attach(tx, keys, owner, submissionId) {
    if (keys.length !== 2 || new Set(keys).size !== 2) throw fail();
    const rows = await Promise.all(keys.map(key => tx.get(reference(key))));
    for (const row of rows) {
      const d = row.data();
      if (!valid(d, row.id) || d.owner !== owner || d.submissionId !== submissionId || d.state !== 'stored' || millis(d.expiresAt) <= now()) throw fail();
    }
    for (const row of rows) tx.update(row.ref, { state: 'active', dueAt: row.data().expiresAt });
  }
  async function read({ key, owner, submissionId, kind }) {
    const ref = reference(key), row = await ref.get(), d = row.data();
    const readable = (data, id) => valid(data,id) && data.key === key && data.owner === owner && data.submissionId === submissionId && data.kind === kind && data.state === 'active' && millis(data.expiresAt) > now();
    if (!readable(d,row.id)) throw fail();
    const bytes = await store.get(key, { type: 'arrayBuffer', consistency: 'strong' });
    // Recheck both clock and journal: deletion/expiry can happen during object I/O.
    const latest = await ref.get();
    if (!bytes || !readable(latest.data(),latest.id)) throw fail();
    return { bytes: Buffer.from(bytes), contentType: d.contentType };
  }
  async function requestDeletion(keys) {
    for (const key of keys.filter(Boolean)) await reference(key).update({ dueAt: new Date(now()) });
  }
  // One fenced, durable cursor per maintenance pass. Ordering by document ID
  // includes malformed/missing timestamps; dueAt-only queries cannot do that.
  async function acquire(slot) {
    const ref = maintenance.doc(slot), token = randomUUID();
    return database.runTransaction(async tx => {
      const d = (await tx.get(ref)).data();
      if (millis(d?.leaseUntil) > now()) return null;
      const state = { cursor: typeof d?.cursor === 'string' ? d.cursor : null,
        pending: Array.isArray(d?.pending) && d.pending.length > 0 && d.pending.length <= 4096 &&
          d.pending.every(p => typeof p === 'string' && p.length <= 110 && /^[a-z0-9/-]*$/.test(p)) ? d.pending : [''] };
      tx.set(ref, { ...state, leaseToken: token, leaseUntil: new Date(now()+60000) });
      return {ref,token,...state};
    });
  }
  async function checkpoint(lease, patch, release = false) {
    return database.runTransaction(async tx => {
      const d = (await tx.get(lease.ref)).data();
      if (d?.leaseToken !== lease.token || millis(d.leaseUntil) <= now()) return false;
      tx.update(lease.ref, { ...patch, leaseUntil: new Date(release ? 0 : now()+60000) });
      return true;
    });
  }
  async function page(collection, slot, limit, work, result, shouldStop) {
    const lease = await acquire(slot);
    if (!lease) { result.busy = true; result.possiblyMore = true; return; }
    try {
      let query = collection.orderBy('__name__');
      if (lease.cursor) query = query.startAfter(lease.cursor);
      const rows = await query.limit(limit).get();
      result.possiblyMore ||= rows.size === limit;
      for (const row of rows.docs) {
        if (shouldStop()) { result.interrupted=true; result.possiblyMore=true; return; }
        if (!await checkpoint(lease, {})) { result.lostOwnership++; result.possiblyMore=true; return; }
        try { await work(row); } catch { result.failed++; }
        // Failed records are revisited next sweep; one failure cannot pin the cursor.
        if (!await checkpoint(lease, {cursor:row.id})) { result.lostOwnership++; result.possiblyMore=true; return; }
      }
      if (rows.size < limit) await checkpoint(lease, {cursor:null});
    } finally { await checkpoint(lease, {}, true); }
  }
  async function processAsset(row, result) {
    const token = randomUUID();
    const claimed = await database.runTransaction(async tx => {
      const current = await tx.get(row.ref); let d = current.data();
      if (!d) return null;
      if (d.state === 'quarantined' && millis(d.quarantinedUntil) !== null) {
        if (millis(d.quarantinedUntil)>now()) return null;
        const p = parseKey(d.key);
        if (!p || row.id !== hash(d.key)) { tx.delete(row.ref);return {outcome:'purged'}; }
        d = {key:d.key,project,environment,...p,orphan:true,state:'delete_pending',attempts:0,
          createdAt:d.quarantinedUntil,expiresAt:d.quarantinedUntil,dueAt:d.quarantinedUntil};
      }
      if (!valid(d,row.id)) {
        const p = parseKey(d.key), safeKey = p && row.id === hash(d.key) ? d.key : null;
        // Replace arbitrary fields, not merge: diagnostic size and private data
        // retention remain bounded even for a poisoned server-side journal.
        tx.set(row.ref, {project,environment,state:'quarantined',key:safeKey,
          diagnosticCode:'INVALID_ASSET_METADATA',originalKeyHash:hash(String(d.key || '').slice(0,4096)),
          quarantinedUntil:new Date(now()+QUARANTINE_DAYS*DAY)});
        return {outcome:'quarantined'};
      }
      if (millis(d.dueAt)>now() || millis(d.leaseUntil)>now()) return null;
      if (!d.orphan) {
        const v = (await tx.get(database.collection('worker_verifications').doc(d.owner))).data();
        const linked = v?.storageBackend === 'netlify-blobs' && [v.governmentIdPath,v.facePhotoPath].includes(d.key);
        if (linked && millis(d.expiresAt)>now()) { tx.update(row.ref,{state:'active',dueAt:d.expiresAt});return null; }
      }
      // Legacy successful tombstones acquire a finite grace window on first visit.
      const deletedAt = d.state === 'deleted' ? (d.deletedAt || new Date(now())) : null;
      const purgeAfter = d.state === 'deleted' ? (d.purgeAfter || new Date(now()+TOMBSTONE_DAYS*DAY)) : null;
      tx.set(row.ref, {...d,state:'deleting',leaseToken:token,leaseUntil:new Date(now()+60000),
        ...(deletedAt ? {deletedAt,purgeAfter} : {})});
      return {...d,deletedAt,purgeAfter};
    });
    if (!claimed) return;
    if (claimed.outcome) { result[claimed.outcome]++;return; }
    let error;
    try { await store.delete(claimed.key); } catch(e) { error=e; }
    const acknowledgment = await database.runTransaction(async tx => {
      const d = (await tx.get(row.ref)).data();
      if (d?.leaseToken !== token || millis(d.leaseUntil) <= now()) return 'lostOwnership';
      if (!error && millis(d.purgeAfter) !== null && millis(d.purgeAfter) <= now()) {
        tx.delete(row.ref);return 'purged';
      }
      const attempts = Math.min(d.attempts+1,1000000);
      const deletedAt = d.deletedAt || new Date(now()), purgeAfter=d.purgeAfter || new Date(now()+TOMBSTONE_DAYS*DAY);
      tx.set(row.ref, {key:d.key,project,environment,submissionId:d.submissionId,kind:d.kind,
        ...(d.orphan ? {orphan:true,ownerHash:d.ownerHash} : {owner:d.owner}),
        createdAt:d.createdAt,expiresAt:d.expiresAt,state:error?'delete_pending':'deleted',attempts,
        leaseUntil:new Date(0),dueAt:new Date(now()+(error?Math.min(DAY,1000*2**Math.min(attempts,17)):DAY)),
        ...(error ? {} : {deletedAt,purgeAfter}),
        lastErrorCode:error?String(error.code || 'OBJECT_DELETE_FAILED').replace(/[^a-zA-Z0-9_-]/g,'').slice(0,64):null});
      return error ? 'failed' : 'deleted';
    });
    result[acknowledgment]++;
    result.acknowledgments.push({assetId:row.id,outcome:acknowledgment});
  }
  // The SDK does not expose a resumable list cursor. Walk a durable prefix tree
  // instead: at most two provider pages per invocation, subdividing large leaves.
  // Missing journals are reserved transactionally BEFORE deletion, preventing a
  // racing upload from attaching to an object scheduled for cleanup.
  async function inventory(limit, result, shouldStop) {
    if (typeof store.list !== 'function') { result.inventoryUnavailable=true;return; }
    const lease = await acquire('inventory');
    if (!lease) { result.possiblyMore=true;return; }
    try {
      const pending = [...lease.pending], suffix=pending.shift() ?? '';
      const iterator=store.list({prefix:prefix+suffix,paginate:true})[Symbol.asyncIterator]();
      const first=await iterator.next(), second=first.done?{done:true}:await iterator.next();
      let blobs=first.value?.blobs || [];
      if(second.done){
        const generated=blobs.filter(b=>parseKey(b.key));
        result.invalidObjects+=blobs.length-generated.length;blobs=generated;
      }
      if (blobs.length>limit || !second.done) {
        if (second.done) {
          // The entire leaf fits in one provider page. Compact its shared owner
          // prefix instead of spending dozens of calls walking the same hash.
          const tails=blobs.map(b=>b.key.slice(prefix.length)).sort();
          if(tails.length){
            let shared=tails[0],last=tails.at(-1);
            while(!last.startsWith(shared))shared=shared.slice(0,-1);
            if(tails.length===1)pending.unshift(tails[0]);
            else pending.unshift(...[...new Set(tails.map(k=>k[shared.length]))].map(c=>shared+c));
          }
        } else if (suffix.length<110) {
          // Unknown further pages: cover every possible generated character;
          // prioritize an observed branch but never skip the other branches.
          const observed=blobs[0]?.key?.[prefix.length+suffix.length];
          const generatedAlphabet='0123456789abcdef-/ilmnostu';
          const alphabet=[...new Set([generatedAlphabet.includes(observed)?observed:null,...generatedAlphabet])].filter(Boolean);
          pending.unshift(...alphabet.map(c=>suffix+c));
        } else result.invalidObjects+=blobs.length;
      } else {
        for (const {key} of blobs) {
          if (shouldStop()) { result.interrupted=true;result.possiblyMore=true;return; }
          if (!await checkpoint(lease,{})) { result.lostOwnership++;return; }
          const p=parseKey(key);
          if (!p) { result.invalidObjects++;continue; }
          const recovered=await database.runTransaction(async tx=>{
            const ref=reference(key), row=await tx.get(ref);
            if (row.exists) return false;
            tx.set(ref,{key,project,environment,...p,orphan:true,state:'delete_pending',attempts:0,
              createdAt:new Date(now()),expiresAt:new Date(now()),dueAt:new Date(now())});return true;
          });
          if(recovered)result.orphansRecovered++;
        }
      }
      result.possiblyMore ||= pending.length>0 || result.orphansRecovered>0;
      if (!await checkpoint(lease,{pending:pending.length?pending:['']})) result.lostOwnership++;
    } finally { await checkpoint(lease,{},true); }
  }
  async function reconcile({limit=25,shouldStop=()=>false}={}) {
    if(!Number.isInteger(limit)||limit<1||limit>100)throw new Error('INVALID_CLEANUP_LIMIT');
    const result={inspected:0,deleted:0,failed:0,quarantined:0,purged:0,quotaPurged:0,lostOwnership:0,
      orphansRecovered:0,invalidObjects:0,acknowledgments:[],interrupted:false,possiblyMore:false};
    await page(assets,'assets',limit,async row=>{result.inspected++;await processAsset(row,result);},result,shouldStop);
    if(shouldStop()){result.interrupted=true;result.possiblyMore=true;return result;}
    await page(database.collection('pilot_upload_quotas'),'quotas',limit,async row=>{
      const removed=await database.runTransaction(async tx=>{
        const d=(await tx.get(row.ref)).data();if(!d)return false;
        // Legacy quotas have no deadline. Derive it from updatedAt; malformed
        // dates cannot bypass today's quota and get a fresh one-day grace period.
        const expiry=millis(d.expiresAt) ?? (millis(d.updatedAt)===null?null:millis(d.updatedAt)+2*DAY);
        if(expiry===null){tx.set(row.ref,{attempts:5,expiresAt:new Date(now()+DAY)});return false;}
        if(expiry>now())return false;tx.delete(row.ref);return true;
      });if(removed)result.quotaPurged++;
    },result,shouldStop);
    if(shouldStop()){result.interrupted=true;result.possiblyMore=true;return result;}
    try{await inventory(limit,result,shouldStop);}catch{result.failed++;}
    return result;
  }
  return { save, attach, read, requestDeletion, reconcile, prefix };
}
let singleton;
function getBlobStorage() {
  require('../config/netlifyPilot').validatePilot();
  if (!singleton) {
    const { getStore } = require('@netlify/blobs');
    singleton = createBlobStorage({ database: require('../config/firebase').db,
      store: getStore({ name: 'swiftserve-local-verification-v1', consistency: 'strong', fetch: localFetch }), project: 'demo-swiftserve-netlify' });
  }
  return singleton;
}
function localFetch(input, options = {}) {
  const url = new URL(typeof input === 'string' ? input : input.url || String(input));
  if (url.protocol !== 'http:' || !['localhost','127.0.0.1','[::1]'].includes(url.hostname)) throw new Error('PILOT_REMOTE_BLOBS_REJECTED');
  return fetch(input, { ...options, redirect: 'error' });
}
module.exports = { createBlobStorage, getBlobStorage, localFetch };
