import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

const preserve='preserve_unallocated_source_quantity_v1',ordering='replay_original_settlement_publication_prefix_v1';
const at='2026-11-02T15:00:00Z',due='2026-11-05T12:00:00Z';
const step=(id,quantity)=>({settlementId:id,expectedRevision:1,quantity,evidenceId:'determination',sourceObservationId:'final-source',expectedReceiptRevision:null,expectedConsumptionRevision:null,lotId:null,reservationId:null,sourceAllocation:preserve});
const selection={implementation:'gas_operator_quantity_reconciliation_v1',rootClaimId:'claim',claims:[{claimId:'claim',expectedRevision:1,quantity:'3',evidenceId:'statement',sourceAllocation:preserve,
 settlements:[step('first','0.750000000000000001'),step('second','2.249999999999999999')]}],consumptions:[],cashout:{ordering,adjustmentDueAt:due},evidence:'Synthetic explicit cashout correction'};
const native=(id,quantity,ordinal,cash)=>({id,quantity,expectedRevision:1,originalPublicationOrder:ordinal,effectiveAt:at,knownAt:at,sourceObservationId:'final-source',cashAmount:cash,cumulativeQuantity:quantity,price:'1.005',exactTotal:cash,roundedTotal:cash});
const result=(id,quantity,cumulative,exact,rounded,cash)=>({settlementId:id,acknowledgedRevision:2,currentRevision:2,currentQuantity:quantity,cumulativeQuantity:cumulative,price:'1.005',exactTotal:exact,roundedTotal:rounded,cashAmount:cash,sourceObservationId:'final-source',changed:true});
const details={quantityUnit:'synthetic_unit',currency:'usd',willChange:true,alreadyRecorded:false,sources:[{accountId:'account',claimId:'claim',claim:{id:'claim',expectedRevision:1,quantity:'3',remainingQuantity:'0',effective_at:at,knownAt:at},
 accounts:[{id:'account',code:'synthetic_operator_account'}],evidence:[{id:'statement',account_id:'account',source_key:'synthetic_operator_statement',revision:1,quantity:'3'},
  {id:'determination',account_id:'account',source_key:'synthetic_cashout_document',revision:2,quantity:'4'}],
 observations:[{id:'final-source',source_code:'synthetic_fixing',role:'daily_settlement',observed_at:'2026-11-01T14:00:00Z',value:'1.005'}],
 settlements:[{...native('first','1',10,'1'),exactTotal:'1.005'},{...native('second','2',11,'2.02'),cumulativeQuantity:'3',exactTotal:'3.015',roundedTotal:'3.02'}],positions:[],consumptions:[],
 cash:[{id:'cash-1',position_id:'claim',amount:'1',currency_code:'usd',due_at:due,effective_at:at},{id:'cash-2',position_id:'claim',amount:'2.02',currency_code:'usd',due_at:due,effective_at:at}],
 payments:[{id:'bank-1',fee_id:'cash-1',business_key:'synthetic_original_bank',revision:1,amount:'0.5',paid_at:at,evidence:'Synthetic observed bank payment'}]}],
 outcome:{accountId:'account',rootClaimId:'claim',claims:[{claimId:'claim',acknowledgedRevision:1,currentRevision:1,currentQuantity:'3',changed:false,settlements:[
 result('first','0.750000000000000001','0.750000000000000001','0.753750000000000001005','0.75','0.75'),
 result('second','2.249999999999999999','3','3.015','3.02','2.27')]}],consumptions:[],cashChanges:[
 {settlementId:'first',positionId:'claim',cashId:'adjust-1',amount:'-0.25',currency:'usd',dueAt:due,effectiveAt:at},
 {settlementId:'second',positionId:'claim',cashId:'adjust-2',amount:'0.25',currency:'usd',dueAt:due,effectiveAt:at}]}};
const context={contextId:'source',snapshotId:'snapshot',asOf:at,businessDate:'2026-11-02'},action='gas.operator.reconcile_quantity';
const offer={target:{handler:'gas_operator_quantity_reconciliation',scopeId:'account',bindingId:'claim'},action,label:'Correct operator quantity or cashout',occurrenceId:'claim',at,before:null,eligible:true,reason:null,revision:0,stateVersion:0,policyId:'policy',policyRevision:1,selection:null};
const settle=()=>new Promise(resolve=>setTimeout(resolve,40));

function physical(){
 const s=structuredClone(selection),d=structuredClone(details);s.claims[0].quantity='1';s.cashout.adjustmentDueAt=null;
 s.claims[0].settlements=[{...step('title','1'),sourceObservationId:null,expectedReceiptRevision:1}];
 s.consumptions=[{consumptionId:'loss',expectedRevision:1,lotId:'stock',quantity:'1.000000000000000001',evidenceId:'loss-document',reservationId:null,retracted:false,sourceAllocation:preserve}];
 const source=d.sources[0];source.claim.quantity='9';source.claim.remainingQuantity='0';
 source.accounts.push({id:'inventory',code:'synthetic_owned_inventory'});
 source.evidence[1]={id:'determination',account_id:'inventory',source_key:'synthetic_title_document',revision:2,quantity:'1'};
 source.evidence.push({id:'loss-document',account_id:'inventory',source_key:'synthetic_loss_document',revision:2,quantity:'1.000000000000000001'});
 source.settlements=[{...native('title','9',10,null),sourceObservationId:null,price:null,exactTotal:null,roundedTotal:null,cashAmount:null,receiptLotId:'stock',consumptionId:null}];
 source.positions=[{id:'stock',account_id:'inventory',quantity:'9',expectedRevision:1}];
 source.consumptions=[{id:'loss',lotId:'stock',quantity:'2',expectedRevision:1,evidenceId:'loss-document',reservation_id:null,kind:'loss',editable:true,effectiveAt:at,knownAt:at}];
 source.reservations=[];source.cash=[];source.payments=[];
 d.outcome.claims[0].settlements=[{...result('title','1','1',null,null,null),price:null}];
 d.outcome.consumptions=[{consumptionId:'loss',acknowledgedRevision:2,currentRevision:2,currentQuantity:'1.000000000000000001',evidenceId:'loss-document',lotId:'stock',reservationId:null,retracted:false,changed:true}];
 d.outcome.cashChanges=[];return{s,d};
}

test('operator review displays explicit ordinary-use and zero withdrawal heads without quantity arithmetic',
 {skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div></div>',async evaluate=>{
 const {s,d}=physical();
 const result=await evaluate(`(async()=>{const {operatorQuantityReview}=await import('/gas-operator-quantity-review.js'),s=${JSON.stringify(s)},d=${JSON.stringify(d)};
  const active=operatorQuantityReview(d,s,v=>'Displayed '+v),zeroS=structuredClone(s),zeroD=structuredClone(d);
  zeroS.consumptions[0].quantity='0';zeroS.consumptions[0].retracted=true;zeroS.consumptions[0].sourceAllocation='withdraw_all_source_allocations_v1';
  Object.assign(zeroD.outcome.consumptions[0],{currentQuantity:'0',retracted:true,currentRevision:3,acknowledgedRevision:3});
  const zero=operatorQuantityReview(zeroD,zeroS,v=>'Displayed '+v),oldD=structuredClone(zeroD);oldD.willChange=false;oldD.alreadyRecorded=true;oldD.outcome.consumptions[0].acknowledgedRevision=1;
  return{active,zero,old:operatorQuantityReview(oldD,s,v=>'Displayed '+v)};})()`);
 const use=result.active.tables.find(row=>row.label==='Reviewed ordinary stock uses');assert.ok(use);
 assert.deepEqual(use.columns.slice(0,4),['Use','Source quantity','Reviewed quantity','Retained current quantity']);
 assert.deepEqual(result.active.tables.find(row=>row.label==='Reviewed settlement prefixes').columns.slice(0,3),['Source quantity','Reviewed quantity','Retained current quantity']);
 for(const value of ['synthetic_owned_inventory','synthetic_loss_document','1.000000000000000001','2','Displayed '+at,'Keep recorded quantity','Preserve unused source quantity'])assert.ok(JSON.stringify(use).includes(value),value);
 assert.ok(JSON.stringify(result.zero.tables).includes('Withdraw recorded quantity'));
 assert.ok(JSON.stringify(result.zero.tables).includes('Withdraw every source allocation'));
 assert.ok(JSON.stringify(result.old.tables).includes('Previously recorded correction'));
}));

test('operator ordinary-use review rejects ineligible, unmatched or lossy source and retained identities',
 {skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div></div>',async evaluate=>{
 const {s,d}=physical();
 const rejected=await evaluate(`(async()=>{const {operatorQuantityReview}=await import('/gas-operator-quantity-review.js'),s=${JSON.stringify(s)},d=${JSON.stringify(d)},rejected=[];
  for(const[name,edit]of Object.entries({missingUse:d=>d.sources[0].consumptions=[],ineligible:d=>d.sources[0].consumptions[0].editable=false,missingEligibility:d=>delete d.sources[0].consumptions[0].editable,
   missingOutcome:d=>d.outcome.consumptions=[],foreignOutcome:d=>d.outcome.consumptions[0].consumptionId='foreign',duplicateOutcome:d=>d.outcome.consumptions.push(d.outcome.consumptions[0]),
   lossySource:d=>d.sources[0].consumptions[0].quantity=2,lossyCurrent:d=>d.outcome.consumptions[0].currentQuantity=1,missingStock:d=>d.sources[0].positions=[],
   foreignDocumentAccount:d=>d.sources[0].evidence[2].account_id='account',unknownCurrentDocument:d=>d.outcome.consumptions[0].evidenceId='',missingKnownTime:d=>delete d.sources[0].consumptions[0].knownAt,
   invalidCurrentRetraction:d=>d.outcome.consumptions[0].retracted=null})){
    const changed=structuredClone(d);edit(changed);try{operatorQuantityReview(changed,s,v=>v);}catch{rejected.push(name);}}
  for(const[name,edit]of Object.entries({foreignUse:s=>s.consumptions[0].consumptionId='foreign',duplicateUse:s=>s.consumptions.push(s.consumptions[0]),lossySelected:s=>s.consumptions[0].quantity=1,
   invalidRetraction:s=>s.consumptions[0].retracted='false',foreignStock:s=>s.consumptions[0].lotId='foreign',foreignReservation:s=>s.consumptions[0].reservationId='foreign'})){
    const changed=structuredClone(s);edit(changed);try{operatorQuantityReview(d,changed,v=>v);}catch{rejected.push(name);}}
  return rejected;})()`);
 assert.deepEqual(rejected,['missingUse','ineligible','missingEligibility','missingOutcome','foreignOutcome','duplicateOutcome','lossySource','lossyCurrent','missingStock','foreignDocumentAccount','unknownCurrentDocument','missingKnownTime','invalidCurrentRetraction','foreignUse','duplicateUse','lossySelected','invalidRetraction','foreignStock','foreignReservation']);
}));

test('operator review shows native prefixes, gross cash and original bank before exact retained execution',
 {skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/app.css"><div id="host"></div>',async evaluate=>{
 const discovery={context,actions:[offer],policies:[],optionProfiles:[],swapProfiles:[],marginPolicies:[],choices:{actions:[{code:action,automatic:false,configurationPermission:'ConfigureGasOwnedHoldings',executionPermission:'RecordGasOwnedHoldings'}],modes:['review'],policyImplementation:'explicit_lifecycle_action_policy_v1'}};
 // This raw-review fixture uses an explicit opaque backend choice. Actual lazy
 // claim/settlement metadata is qualified by the separate native app consumer.
 const setup={context,target:offer.target,accounts:[{id:'account',label:'Synthetic operator'}],policies:[{id:'policy',revision:1,accountId:'account',action,label:'Synthetic review policy'}],configuration:{},forms:{[action]:{label:offer.label,permission:'RecordGasOwnedHoldings',fields:[
 {name:'correction',label:'Exact reviewed native correction',kind:'reference',nullable:false,members:Object.keys(selection),choices:[{id:'exact',label:'Synthetic explicit correction',value:selection}]}]}}};
 await evaluate(`(async()=>{window.sent=[];window.errors=[];const {setupLifecycle}=await import('/lifecycle-view.js');const api=async(path,body)=>{if(path==='lifecycle/view')return ${JSON.stringify(discovery)};if(path==='lifecycle/gas/setup')return ${JSON.stringify(setup)};if(path==='lifecycle/preview')return{hash:'a'.repeat(64),offer:${JSON.stringify(offer)},details:${JSON.stringify(details)}};if(path==='lifecycle/execute'){sent.push(body);if(sent.length===1)throw Error('Synthetic lost successful reply');return{operationId:body.operationId,changed:true};}throw Error('Unexpected '+path);};window.desk=setupLifecycle(document.querySelector('#host'),{api,act:async f=>{try{await f();}catch(e){errors.push(e.message);}},busy:()=>false,identity:()=> 'operator',context:()=>({snapshotId:'header'}),historical:()=>false,zone:()=> 'UTC',permission:()=>true,changed(){}});await desk.load();})()`);
 await settle();await evaluate("document.querySelector('.tabulator-row').click()");await settle();
 assert.equal(await evaluate("!!document.querySelector('[name=correction]')"),true,'The operator handler must read the backend-defined gas form.');
 assert.equal(await evaluate("document.querySelector('[name=correction]').value"),'');
 await evaluate("(()=>{const f=document.querySelector('[data-lifecycle=panel] form');for(const[name,value]of [['policyId','policy:1'],['correction','exact']]){const e=f.querySelector('[name='+name+']');e.value=value;e.dispatchEvent(new Event('change',{bubbles:true}));}f.requestSubmit();})()");await settle();
 assert.deepEqual(await evaluate('errors'),[]);const text=await evaluate("document.querySelector('[data-lifecycle-review]').textContent");
 assert.doesNotMatch(text,/Exact reviewed native correction/);
 for(const value of ['Reviewed operator claims','Source remaining quantity','Reviewed settlement prefixes','Original settlement order','Retained cash contribution','Recorded cash memberships','Recorded bank payment history','Cash adjustments','synthetic_original_bank','0.750000000000000001','2.249999999999999999','0.753750000000000001005','2.27','-0.25','0.25','USD'])assert.ok(text.includes(value),value);
 assert.equal(await evaluate('sent.length'),0);await evaluate("document.querySelector('[data-lifecycle-execute]').click()");await settle();
 assert.equal(await evaluate("document.querySelector('[data-lifecycle=pending]').hidden"),false);await evaluate("document.querySelector('[data-lifecycle=retry]').click()");await settle();
 const sent=await evaluate('sent');assert.equal(sent.length,2);assert.deepEqual(sent[0],sent[1]);assert.deepEqual(sent[0].selection,selection);
}));

test('operator source labels and fixing times require exact admitted native identities',
 {skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div></div>',async evaluate=>{
 const result=await evaluate(`(async()=>{const {operatorQuantityReview}=await import('/gas-operator-quantity-review.js'),d=${JSON.stringify(details)},s=${JSON.stringify(selection)},rejected=[];
  for(const[name,edit]of Object.entries({missingAccounts:d=>delete d.sources[0].accounts,foreignAccount:d=>d.sources[0].accounts[0].id='foreign',
   missingEvidence:d=>delete d.sources[0].evidence,foreignDocument:d=>d.sources[0].evidence[1].id='foreign',foreignDocumentAccount:d=>d.sources[0].evidence[1].account_id='foreign',
   knownForeignClaimDocument:d=>{d.sources[0].accounts.push({id:'foreign',code:'synthetic_other_account'});d.sources[0].evidence[0].account_id='foreign';},
   duplicateDocument:d=>d.sources[0].evidence.push(d.sources[0].evidence[1]),missingObservations:d=>delete d.sources[0].observations,
   foreignFixing:d=>d.sources[0].observations[0].id='foreign',lossyFixing:d=>d.sources[0].observations[0].value=1.005,missingFixingTime:d=>delete d.sources[0].observations[0].observed_at})){
    const changed=structuredClone(d);edit(changed);try{operatorQuantityReview(changed,s,v=>'Displayed '+v);}catch{rejected.push(name);}}
  const foreignStep=structuredClone(d);foreignStep.sources[0].accounts.push({id:'foreign',code:'synthetic_other_account'});foreignStep.sources[0].evidence[1].account_id='foreign';
  return{reviewed:operatorQuantityReview(d,s,v=>'Displayed '+v),foreignStep:operatorQuantityReview(foreignStep,s,v=>'Displayed '+v),rejected};})()`);
 assert.deepEqual(result.rejected,['missingAccounts','foreignAccount','missingEvidence','foreignDocument','foreignDocumentAccount','knownForeignClaimDocument','duplicateDocument','missingObservations','foreignFixing','lossyFixing','missingFixingTime']);
 const displayed=JSON.stringify(result.reviewed);for(const value of ['synthetic_operator_account','synthetic_operator_statement','synthetic_cashout_document','synthetic_fixing','Displayed 2026-11-01T14:00:00Z'])assert.ok(displayed.includes(value),value);
 const stepTable=result.foreignStep.tables.find(row=>row.label==='Reviewed settlement prefixes');
 assert.equal(stepTable.rows[0][stepTable.columns.indexOf('Account / settlement document')],'synthetic_other_account / synthetic_cashout_document');
}));

test('operator review retains old acknowledgements and refuses unmatched, duplicate or lossy native facts',
 {skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div></div>',async evaluate=>{
 const result=await evaluate(`(async()=>{const {operatorQuantityReview}=await import('/gas-operator-quantity-review.js');const d=${JSON.stringify(details)},s=${JSON.stringify(selection)};d.willChange=false;d.alreadyRecorded=true;d.outcome.claims[0].settlements[0].acknowledgedRevision=1;
 const reviewed=operatorQuantityReview(d,s,v=>v),rejected=[];
 for(const[name,edit]of Object.entries({sourceQuantity:d=>d.sources[0].claim.quantity=3,remaining:d=>d.sources[0].claim.remainingQuantity=0,
  missingClaim:d=>d.outcome.claims=[],foreignClaim:d=>d.sources[0].claim.id='other',duplicateSource:d=>d.sources.push(d.sources[0]),
  missingSettlement:d=>d.outcome.claims[0].settlements.pop(),duplicateSettlement:d=>d.outcome.claims[0].settlements.push(d.outcome.claims[0].settlements[0]),
  foreignSettlement:d=>d.outcome.claims[0].settlements[0].settlementId='other',cash:d=>d.sources[0].cash[0].amount=1,cashClaim:d=>d.sources[0].cash[0].position_id='other',bank:d=>d.sources[0].payments[0].amount=.5,
  prefix:d=>d.outcome.claims[0].settlements[0].roundedTotal=.75,adjustment:d=>d.outcome.cashChanges[0].amount=-.25,currency:d=>d.sources[0].cash[0].currency_code='eur'})){
   const changed=structuredClone(d);edit(changed);try{operatorQuantityReview(changed,s,v=>v);}catch{rejected.push(name);}}
 for(const[name,edit]of Object.entries({quantity:s=>s.claims[0].quantity=3,ordering:s=>s.cashout.ordering='guess',allocation:s=>s.claims[0].sourceAllocation='',
  foreignRoot:s=>s.rootClaimId='other'})){const changed=structuredClone(s);edit(changed);try{operatorQuantityReview(d,changed,v=>v);}catch{rejected.push(name);}}
 return{reviewed,rejected};})()`);
 assert.match(Object.fromEntries(result.reviewed.facts).Effect,/acknowledged/);
 const prefixes=result.reviewed.tables.find(row=>row.label==='Reviewed settlement prefixes');assert.ok(prefixes.rows[0].includes('1'));assert.ok(prefixes.rows[0].includes('2'));
 assert.deepEqual(result.rejected,['sourceQuantity','remaining','missingClaim','foreignClaim','duplicateSource','missingSettlement','duplicateSettlement','foreignSettlement','cash','cashClaim','bank','prefix','adjustment','currency','quantity','ordering','allocation','foreignRoot']);
}));

test('operator review preserves native publication order and labels retained changed outcomes as historical',
 {skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div></div>',async evaluate=>{
 const result=await evaluate(`(async()=>{const {operatorQuantityReview}=await import('/gas-operator-quantity-review.js');const d=${JSON.stringify(details)},s=${JSON.stringify(selection)};
  s.claims[0].settlements.reverse();d.willChange=false;d.alreadyRecorded=true;d.outcome.claims[0].changed=true;
  return operatorQuantityReview(d,s,v=>v);})()`);
 assert.deepEqual({order:result.tables.find(row=>row.label==='Reviewed settlement prefixes').rows.map(row=>row.at(-1)),effect:result.tables.find(row=>row.label==='Reviewed operator claims').rows[0][9]},
  {order:['first','second'],effect:'Previously recorded correction'});
 assert.ok(result.tables.find(row=>row.label==='Reviewed operator claims').columns.includes('Acknowledged quantity'));
}));
