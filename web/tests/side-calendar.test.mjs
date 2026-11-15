import test from 'node:test';
import assert from 'node:assert/strict';
import {SideCalendarPolicySelection,calendarKey} from '../dist/side-calendar.js';
const ref=(version)=>({revision:{catalogId:'synthetic-catalog',revisionId:version},code:'synthetic'});
const a=ref('one'),b=ref('two'),choices=[{reference:a,value:calendarKey(a),label:'one'},{reference:b,value:calendarKey(b),label:'two'}];
const purposes={delivery:true,observation:true,payment:true};
test('each applicable purpose requires explicit selection, even for a sole calendar',()=>{
 const value=new SideCalendarPolicySelection();
 assert.throws(()=>value.read(purposes,choices.slice(0,1)),/Choose/);
 value.choose('delivery',a);value.choose('payment',b);
 assert.throws(()=>value.read(purposes,choices),/observation/);
 value.choose('observation',a);
 assert.deepEqual(value.read(purposes,choices),{implementation:'side_calendar_policy_v1',delivery:{applicable:true,calendar:a},observation:{applicable:true,calendar:a},payment:{applicable:true,calendar:b}});
});
test('explicit use-one expands concrete bindings; linked schedules remain inapplicable',()=>{
 const value=new SideCalendarPolicySelection(),linked={delivery:false,observation:false,payment:true};
 value.useOne(a,linked,{});
 assert.deepEqual(value.read(linked,choices),{implementation:'side_calendar_policy_v1',delivery:{applicable:false,calendar:null},observation:{applicable:false,calendar:null},payment:{applicable:true,calendar:a}});
});
test('different saved purpose versions are preserved and unavailable versions never substituted',()=>{
 const value=new SideCalendarPolicySelection();value.useOne(a,purposes,{});value.choose('payment',b);
 const saved=value.read(purposes,choices),restored=new SideCalendarPolicySelection();restored.restore(saved);
 assert.deepEqual(restored.read(purposes,choices),saved);
 assert.throws(()=>restored.read(purposes,choices.slice(0,1)),/unavailable/);
 assert.deepEqual(restored.read(purposes,choices),saved);
});
test('product locks reject conflicting shared choices atomically',()=>{
 const value=new SideCalendarPolicySelection();value.useOne(a,purposes,{});
 assert.throws(()=>value.useOne(b,purposes,{delivery:a}),/product/);
 assert.equal(value.read(purposes,choices).payment.calendar.revision.revisionId,'one');
 value.choose('delivery',b);
 assert.throws(()=>value.read(purposes,choices,{delivery:a}),/product/);
});
test('explicit clear survives refresh; another Side has independent state',()=>{
 const first=new SideCalendarPolicySelection(),second=new SideCalendarPolicySelection();first.useOne(a,purposes,{});first.choose('payment',null);
 assert.throws(()=>first.read(purposes,choices),/payment/);assert.throws(()=>second.read(purposes,choices),/delivery/);
});
