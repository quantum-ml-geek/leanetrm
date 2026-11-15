import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,withBrowserPage,browserTestTimeout} from './browser-page.mjs';

test('crude invoice preview, choice and balances preserve payment dates across display zones',{skip:!browserAvailable,timeout:browserTestTimeout},async()=>{
 await withBrowserPage('<div id="editor-shelf"></div><main id="host"></main>',async evaluate=>{
  await evaluate(`(async()=>{
   const {setupCrudeOperations}=await import('/crude-operations.js');
   window.zone='America/Chicago';window.jobs=[];
   const due='2027-02-05T00:00:00Z',at='2027-01-04T12:00:00Z';
   const data={tradeId:'trade',profile:'physical_crude_receipt_cash_v1',head:{revision:1,currency_code:'USD',decimal_places:2,quantity_unit:'bbl',handling_fee:'0.1'},version:1,canWrite:true,
    receipts:[{id:'receipt',business_key:'Synthetic receipt',quantity:'100',effective_at:at,disposition:'owned_inventory',evidence:'Synthetic certificate'}],allocations:[],dispatches:[],
    invoices:[{id:'fee',business_key:'Synthetic fee',active:true,slot:2,amount:'10',currency_code:'USD',due_at:due,direction:1}],payments:[],paymentReversals:[],invoiceVoids:[],sales:[],
    balances:{acceptedQuantity:'100',remainingQuantity:'0',ownedInventoryQuantity:'100',ownedQuantity:'100',reservedQuantity:'0',dispatchedQuantity:'0',cash:[],
     invoices:[{invoiceId:'fee',state:'Open',amount:'10',paid:'0',open:'10',dueAt:due}]}};
   window.ui=setupCrudeOperations({api:async(path)=>{
    if(path==='crude/operations/read')return structuredClone(data);
    if(path==='time/inspect')return {candidates:[{instant:at,offset:'+00:00'}]};
    if(path==='crude/operations/invoice/preview')return {previewHash:'synthetic',direction:'receive',amount:'10',currency:'USD',exactAmount:'10',dueAt:due};
    throw Error(path);
   },act:async work=>{const job=work();jobs.push(job);await job;},busy:()=>false,context:()=>({snapshotId:'synthetic',knowledgeMode:'current'}),actor:()=>'synthetic',zone:()=>zone,onDenied:()=>{},queue:async()=>{throw Error('Unexpected write');},pending:()=>undefined,host:()=>document.querySelector('#host'),unsavedChanged:()=>{}});
   window.preview=async()=>{
    for(const [name,value] of Object.entries({kind:'invoice',profile:data.profile,businessKey:'Synthetic preview',effectiveAt:'2027-01-04T12:00',evidence:'Synthetic evidence',receipt:'receipt',component:'handling_fee',precision:'2',rounding:'crude_cumulative_receipt_cash_v1'})){
     const field=document.querySelector('#crude-operation-'+name);field.value=value;field.dispatchEvent(new Event('change',{bubbles:true}));
    }
    document.querySelector('#crude-operation-form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));await Promise.all(jobs.splice(0));
   };
   await ui.open('trade');await preview();
  })()`);
  for(const zone of ['America/Chicago','Asia/Kathmandu']){
   await evaluate(`(async()=>{window.zone=${JSON.stringify(zone)};await ui.open('trade');await preview();})()`);
   const result=await evaluate(`(()=>{const rows=[...document.querySelectorAll('#crude-operation-ledger section')];return {
    dates:rows.filter(s=>['Issued invoices','Invoice balances'].includes(s.querySelector('h4').textContent)).map(s=>s.querySelector('tbody tr td:last-child').textContent),
    headers:rows.flatMap(s=>[...s.querySelectorAll('th')].map(x=>x.textContent)),
    choice:document.querySelector('#crude-operation-invoice').options[1].textContent,
    preview:[...document.querySelectorAll('#crude-operations > p')].at(-1).textContent,
    receipt:rows.find(s=>s.querySelector('h4').textContent==='Accepted receipts').querySelector('tbody tr td:nth-child(2)').textContent
   };})()`);
   assert.deepEqual(result.dates,['Feb 5, 2027','Feb 5, 2027']);
   assert.ok(result.headers.includes('Due date'));assert.ok(result.choice.endsWith('due Feb 5, 2027'));assert.ok(result.preview.endsWith('due Feb 5, 2027'));
   assert.match(result.receipt,zone==='America/Chicago'?/6:00 AM CST/:/5:45 PM GMT\+5:45/);
  }
 });
});
