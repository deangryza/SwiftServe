import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequestGate } from '../src/lib/requestGate.js';

test('rapid review actions make one in-flight request and do not cache later reads', async () => {
  const gate=createRequestGate(); let requests=0, release;
  const pending=new Promise(resolve=>{release=resolve;});
  async function action(){if(!gate.tryStart())return;try{requests++;await pending;}finally{gate.finish();}}
  const first=action(); await action(); await action();
  assert.equal(requests,1); release(); await first;
  await action(); assert.equal(requests,2);
});
test('failed requests release the gate for a retry',async()=>{
  const gate=createRequestGate();
  async function failed(){if(!gate.tryStart())return;try{throw Error('synthetic failure');}finally{gate.finish();}}
  await assert.rejects(failed(),/synthetic failure/);
  assert.equal(gate.tryStart(),true);gate.finish();
});
