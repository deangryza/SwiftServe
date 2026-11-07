const {test,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const config=require.resolve('../src/config/firebase');
const priorConfig=require.cache[config], priorMode=process.env.SWIFTSERVE_NETLIFY_PILOT;
const calls=[];
require.cache[config]={id:config,filename:config,loaded:true,exports:{auth:{verifyIdToken:async(token,revoked)=>{
  calls.push({token,revoked});
  if(revoked && ['revoked','disabled'].includes(token))throw Object.assign(new Error('synthetic private details'),{code:'auth/'+token});
  return {uid:'synthetic-worker'};
}}}};
const authenticate=require('../src/middleware/authMiddleware');
beforeEach(()=>{calls.length=0;process.env.SWIFTSERVE_NETLIFY_PILOT='true';});
after(()=>{if(priorConfig)require.cache[config]=priorConfig;else delete require.cache[config];if(priorMode===undefined)delete process.env.SWIFTSERVE_NETLIFY_PILOT;else process.env.SWIFTSERVE_NETLIFY_PILOT=priorMode;});
async function call(token){let status=200,next=false;const req={headers:token?{authorization:'Bearer '+token}:{}};const res={status(n){status=n;return this;},json(){return this;}};await authenticate(req,res,()=>{next=true;});return {status,next,req};}
for(const token of ['revoked','disabled'])test('pilot rejects '+token+' sessions before route handlers',async()=>{
  const r=await call(token);assert.equal(r.status,401);assert.equal(r.next,false);assert.equal(calls[0].revoked,true);
});
test('pilot permits a valid session and refuses missing credentials',async()=>{
  assert.equal((await call('valid')).next,true);assert.equal(calls[0].revoked,true);assert.equal((await call()).status,401);
});
test('non-pilot authentication preserves the existing SDK invocation',async()=>{
  delete process.env.SWIFTSERVE_NETLIFY_PILOT;assert.equal((await call('valid')).next,true);assert.equal(calls[0].revoked,undefined);
});
