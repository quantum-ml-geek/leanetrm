import test from 'node:test';
import assert from 'node:assert/strict';
import {workspaceReadyMarker} from '../dist/workspace-ready.js';

test('native readiness waits for read completion and two frames, rechecks races, and marks once',()=>{
 let ready=false,marks=0;const frames=[];
 const check=workspaceReadyMarker(()=>ready,callback=>frames.push(callback),()=>marks++);
 check();assert.equal(frames.length,0,'pending initial reads must not schedule readiness');
 ready=true;check();check();assert.equal(frames.length,1,'repeated controls sync shares the same paint check');
 frames.shift()();assert.equal(marks,0);ready=false;frames.shift()();assert.equal(marks,0,'a new pending read during paint prevents a ready mark');
 ready=true;check();frames.shift()();frames.shift()();assert.equal(marks,1);
 check();assert.equal(frames.length,0,'later profile changes cannot republish startup readiness');
});
