import test from 'node:test';
import assert from 'node:assert/strict';
import {LiveUpdates} from '../dist/live-context.js';

test('bursts keep one latest update and never run two screen refreshes together',async()=>{
 const scheduled=[],states=[],seen=[];let finish;
 const updates=new LiveUpdates({schedule:work=>{scheduled.push(work);return()=>{};},busy:()=>false,status:s=>states.push(s),
  apply:async value=>{seen.push(value.generation);await new Promise(resolve=>finish=resolve);}});
 updates.offer({generation:1});scheduled.shift()();await Promise.resolve();
 updates.offer({generation:2});updates.offer({generation:1000});assert.deepEqual(seen,[1]);
 finish();await new Promise(resolve=>setImmediate(resolve));scheduled.shift()();await Promise.resolve();
 assert.deepEqual(seen,[1,1000]);finish();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(states.at(-1).state,'live');assert.ok(states.at(-1).updatedAt);
});
test('a replay of the in-flight generation does not refresh successful inputs twice',async()=>{
 const scheduled=[],states=[],seen=[];let finish;
 const updates=new LiveUpdates({schedule:work=>{scheduled.push(work);return()=>{};},busy:()=>false,status:s=>states.push(s),
  apply:async value=>{seen.push(value.generation);await new Promise(resolve=>finish=resolve);}});
 updates.offer({generation:4});scheduled.shift()();await Promise.resolve();
 updates.offer({generation:4});updates.offer({generation:4});
 finish();await new Promise(resolve=>setImmediate(resolve));
 assert.deepEqual(seen,[4]);assert.equal(scheduled.length,0,'a successful generation is applied once even when the stream replays it before completion');
 assert.equal(states.at(-1).state,'live');assert.ok(states.at(-1).updatedAt);
});
test('a failed in-flight generation remains retryable after an unforced replay',async()=>{
 const scheduled=[],states=[],seen=[];let reject,fail=true;
 const updates=new LiveUpdates({schedule:work=>{scheduled.push(work);return()=>{};},busy:()=>false,status:s=>states.push(s),
  apply:async value=>{seen.push(value.generation);if(fail)await new Promise((_,no)=>reject=no);}});
 updates.offer({generation:5});scheduled.shift()();await Promise.resolve();updates.offer({generation:5});
 reject(Error('Synthetic refresh failure'));await new Promise(resolve=>setImmediate(resolve));
 assert.equal(states.at(-1).state,'stale');assert.equal(states.at(-1).updatedAt,undefined);
 assert.equal(scheduled.length,0,'a duplicate notification does not replay a failed read automatically');
 fail=false;updates.offer({generation:5},true);scheduled.shift()();await new Promise(resolve=>setImmediate(resolve));
 assert.deepEqual(seen,[5,5]);assert.equal(states.at(-1).state,'live');assert.ok(states.at(-1).updatedAt);
});
test('an explicit forced refresh of an in-flight generation runs once after it finishes',async()=>{
 const scheduled=[],seen=[];let finish;
 const updates=new LiveUpdates({schedule:work=>{scheduled.push(work);return()=>{};},busy:()=>false,status:()=>{},
  apply:async value=>{seen.push(value.generation);await new Promise(resolve=>finish=resolve);}});
 updates.offer({generation:6});scheduled.shift()();await Promise.resolve();
 updates.offer({generation:6},true);updates.offer({generation:6});
 finish();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(scheduled.length,1);scheduled.shift()();await Promise.resolve();assert.deepEqual(seen,[6,6]);
 finish();await new Promise(resolve=>setImmediate(resolve));assert.equal(scheduled.length,0);
 updates.offer({generation:6});assert.equal(scheduled.length,0);
 updates.offer({generation:6},true);assert.equal(scheduled.length,1);scheduled.shift()();await Promise.resolve();
 assert.deepEqual(seen,[6,6,6]);finish();await new Promise(resolve=>setImmediate(resolve));
});
test('failed refresh stays visibly stale and a reconnect can retry the same generation',async()=>{
 const scheduled=[],states=[];let fail=true;
 const updates=new LiveUpdates({schedule:work=>{scheduled.push(work);return()=>{};},busy:()=>false,status:s=>states.push(s),apply:async()=>{if(fail)throw Error('offline');}});
 updates.offer({generation:3});scheduled.shift()();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(states.at(-1).state,'stale');assert.equal(states.at(-1).updatedAt,undefined);
 fail=false;updates.offer({generation:3});scheduled.shift()();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(states.at(-1).state,'live');
 updates.disconnected();assert.equal(states.at(-1).state,'stale');assert.ok(states.at(-1).updatedAt);
 updates.offer({generation:3});assert.equal(states.at(-1).state,'stale');assert.equal(scheduled.length,0);
 updates.reconnected();assert.equal(states.at(-1).state,'live');
});
test('stopped or obsolete callbacks cannot mark another selection live',async()=>{
 const scheduled=[],states=[];let finish;
 const updates=new LiveUpdates({schedule:work=>{scheduled.push(work);return()=>{};},busy:()=>false,status:s=>states.push(s),apply:()=>new Promise(resolve=>finish=resolve)});
 updates.offer({generation:2});scheduled.shift()();await Promise.resolve();updates.stop();const count=states.length;
 finish();await new Promise(resolve=>setImmediate(resolve));updates.offer({generation:1});assert.equal(states.length,count);
});
