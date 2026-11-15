import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,withBrowserPage,browserTestTimeout} from './browser-page.mjs';

test('swap settlement inspection displays contractual dates and observed cash instants',{skip:!browserAvailable,timeout:browserTestTimeout},async()=>{
 await withBrowserPage('<div id="editor-shelf"></div><main id="host"></main>',async evaluate=>{
  await evaluate(`(async()=>{
   const {setupSwapSettlement}=await import('/swap-settlement.js');
   window.zone='America/Chicago';window.jobs=[];
   const paymentAt='2027-02-05T00:00:00Z';
   window.calculation={paymentAt,amount:'10',exactAmount:'10',roundingEffect:'0',resolvedQuantity:'100',prices:[{publishedAt:'2027-02-04T12:00:00Z',contractHash:'synthetic'}]};
   const detail={state:{tradeId:'trade',revision:1,tradeReference:'Synthetic swap'},context:{contextId:'context'},asOf:'2027-02-05T12:00:00Z',canAmend:true,currency:'USD',currencyLabel:'USD',decimalPlaces:2,roundingPolicy:'currency_minor_units_to_even_v1',
    settlement:{version:0,occurrences:[],determinations:[]},balances:[],cashMovements:[{id:'payment',determinationId:null,recordKind:'payment',allocations:[],amount:'10',reversalAmount:'0',effectiveAt:'2027-02-05T12:00:00Z',reference:'Synthetic bank payment',canReverse:false}],valuation:{payments:[{membershipOrdinal:0,ordinal:0,deliveryFrom:'2027-01-01',deliveryTo:'2027-02-01',paymentAt,completionAt:'2027-02-01T00:00:00Z',state:'Undetermined',final:true,realized:true,contractualAmount:'10',remainingValue:'10'}]}};
   window.ui=setupSwapSettlement({api:async path=>{
    if(path==='swaps/settlement/inspect')return structuredClone(detail);
    if(path==='workspace/navigation')return {frames:[]};
    if(path==='swaps/settlement/preview')return {previewHash:'synthetic',expectedVersion:0,previousTotal:'0',proposedContribution:'10',isCorrection:false,inputsChanged:true,calculation};
    throw Error(path);
   },act:async work=>{const job=work();jobs.push(job);await job;},busy:()=>false,zone:()=>zone,context:()=>({snapshotId:'synthetic',knowledgeMode:'current'}),queue:async()=>{throw Error('Unexpected write');},pending:()=>undefined,host:()=>document.querySelector('#host'),unsavedChanged:()=>{},ask:async()=>true});
  })()`);
  for(const zone of ['America/Chicago','Asia/Kathmandu']){
   const result=await evaluate(`(async()=>{
    window.zone=${JSON.stringify(zone)};await ui.open('trade');
    return {text:document.querySelector('#swap-settlement').textContent,source:calculation.paymentAt,cash:document.querySelector('#swap-settlement-cash').textContent};
   })()`);
   assert.equal(result.source,'2027-02-05T00:00:00Z');
   assert.ok(result.text.includes('payment Feb 5, 2027'));
   assert.match(result.cash,zone==='America/Chicago'?/6:00/:/5:45/);
   assert.ok(!result.text.includes('2027-02-05T00:00:00Z'));
  }
 });
});
