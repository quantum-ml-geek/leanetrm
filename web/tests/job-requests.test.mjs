import test from 'node:test';
import assert from 'node:assert/strict';
import {JobRequest} from '../dist/job-requests.js';

test('an uncertain committed job request survives denied retries and authority restoration',()=>{
  const pending=new JobRequest();
  const original=pending.begin('jobs/create',{name:'Synthetic job'},()=> 'synthetic-request');
  const receipts=new Map();
  let writes=0;
  function backend(allowed){
    if(!allowed)return 'access_denied';
    if(!receipts.has(pending.command.operationId))receipts.set(pending.command.operationId,++writes);
    return receipts.get(pending.command.operationId);
  }
  assert.equal(backend(true),1); // Commit, then lose its response.
  pending.failed('response_unknown');
  pending.failed(backend(false));
  assert.deepEqual(pending.command,original);
  assert.equal(backend(true),1);
  assert.equal(writes,1);
});

test('a confirmed first-attempt rejection can release the unsaved job request',()=>{
  const pending=new JobRequest();
  pending.begin('jobs/create',{name:'Synthetic job'},()=> 'synthetic-request');
  pending.failed('job_limit');
  assert.equal(pending.command,undefined);
});


test('closing the page after dispatch preserves uncertainty across denied retries',()=>{
  const pending=new JobRequest();
  pending.begin('jobs/control',{action:'run_again'},()=> 'synthetic-request');
  assert.equal(pending.sending(),false);
  const saved=JSON.stringify(pending.command); // Persist before network dispatch.
  const restored=new JobRequest();restored.command=JSON.parse(saved);
  restored.failed('access_denied',restored.sending());
  assert.equal(restored.command.operationId,'synthetic-request');
});
