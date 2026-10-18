import test from 'node:test';
import assert from 'node:assert/strict';
import {localTimeValue} from '../dist/user-time.js';
test('local time entry renders the selected user zone instead of appending UTC',()=>{
 assert.equal(localTimeValue('2020-12-18T16:00:00Z','America/Chicago'),'2020-12-18T10:00');
 assert.equal(localTimeValue('2020-12-18T23:00:30Z','Asia/Tokyo',true),'2020-12-19T08:00:30');
});
test('both repeated clocks render the same wall time for explicit backend disambiguation',()=>{
 assert.equal(localTimeValue('2026-11-01T06:30:00Z','America/Chicago'),'2026-11-01T01:30');
 assert.equal(localTimeValue('2026-11-01T07:30:00Z','America/Chicago'),'2026-11-01T01:30');
});
