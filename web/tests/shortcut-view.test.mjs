import test from 'node:test';
import assert from 'node:assert/strict';
import {dateRoleName,resolutionDisplay,scheduleErrorMessage} from '../dist/shortcut-view.js';

test('date roles are explicit and never inferred from symbol spelling',()=>{
  assert.equal(dateRoleName('delivery_start'),'Delivery start');
  assert.equal(dateRoleName('last_trading'),'Last trading date');
  assert.throws(()=>dateRoleName(''),/date/i);
});
test('resolved date is displayed with the exact dated contract',()=>{
  const source={curve:'future',entries:[{contractId:'jan',label:'January 2021'},{contractId:'feb',label:'February 2021'}]};
  assert.deepEqual(resolutionDisplay({symbol:'oe.ng1',sequence:{code:'future'},contractId:'feb',date:'2021-02-01',dateRole:'delivery_start'},source),{
    title:'oe.ng1 → February 2021',date:'Feb 1, 2021',role:'Delivery start'});
});
test('unmatched source identity cannot acquire a plausible contract label',()=>{
  assert.throws(()=>resolutionDisplay({sequence:{code:'other'},contractId:'absent'},{curve:'future',entries:[]}),/source|contract/i);
});
test('shortcut errors explain collisions and coverage instead of substituting a default',()=>{
  assert.match(scheduleErrorMessage('shortcut_conflict'),/different|another|new/i);
  assert.match(scheduleErrorMessage('sequence_ineligible'),/eligible|listed|trading/i);
  assert.match(scheduleErrorMessage('sequence_coverage'),/coverage|range/i);
  assert.equal(scheduleErrorMessage('unknown'),undefined);
});
