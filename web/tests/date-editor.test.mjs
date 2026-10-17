import test from 'node:test';
import assert from 'node:assert/strict';
import {contractExampleRows,calendarFromFields} from '../dist/date-editor.js';
test('example bindings refer to schedule occurrences rather than copied dates',()=>{
  const rows=contractExampleRows('oe.ng',3,'15:30');
  assert.equal(rows.length,3);
  assert.deepEqual(rows[1],{label:'Contract 2',start:'oe.ng[1]',end:'oe.ng[2]',lastTrading:'oe.ng[1] - 3bd',cutoffUtc:'15:30'});
});
test('closure input requires exact dates and a deliberate weekend selection',()=>{
  const fields={name:'Test calendar',from:'2021-01-01',to:'2022-01-01',weekends:'0,6',closures:'2021-01-01\n2021-07-05'};
  assert.deepEqual(calendarFromFields(fields).closedDates,['2021-01-01','2021-07-05']);
  assert.throws(()=>calendarFromFields({...fields,weekends:''}),/weekday/i);
  assert.throws(()=>calendarFromFields({...fields,closures:'July 5'}),/date/i);
  assert.deepEqual(calendarFromFields({...fields,weekends:'none',closures:''}).weekendDays,[]);
});
