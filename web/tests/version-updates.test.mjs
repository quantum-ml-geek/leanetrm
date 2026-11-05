import test from 'node:test';
import assert from 'node:assert/strict';
const tick=()=>new Promise(r=>setImmediate(r));
const deferred=()=>{let resolve;return {promise:new Promise(r=>resolve=r),resolve:v=>resolve(v)};};

test('version watching applies only changed server versions and waits until the view is ready',async()=>{
 const {watchVersions}=await import('../dist/version-updates.js');
 let ready=true,read=deferred(),reads=0;const applied=[];
 const stop=watchVersions({initial:'a',current:()=>true,ready:()=>ready,pause:async()=>tick(),read:async()=>{reads++;return read.promise;},apply:async v=>{applied.push(v);},failed:()=>false});
 await tick();read.resolve('a');await tick();assert.deepEqual(applied,[]);
 read=deferred();ready=false;await tick();const before=reads;read.resolve('b');await tick();assert.deepEqual(applied,[]);assert.equal(reads,before);
 ready=true;await tick();await tick();assert.deepEqual(applied,['b']);stop();
});

test('stopping or replacing the view suppresses a late update and failure',async()=>{
 const {watchVersions}=await import('../dist/version-updates.js');
 const pending=deferred();let current=true,applied=0,failed=0;
 const stop=watchVersions({initial:'a',current:()=>current,ready:()=>true,pause:async()=>tick(),read:()=>pending.promise,apply:async()=>{applied++;},failed:()=>{failed++;return false;}});
 await tick();current=false;stop();pending.resolve('b');await tick();assert.equal(applied,0);assert.equal(failed,0);
});
