import test from 'node:test';
import assert from 'node:assert/strict';
import {requirePointSetup,reviewedPointRequest,requirePointReceipt,pointEditedSelection,requirePointInputs,restorePointRequest,pointPublicationRejection} from '../dist/point-trader-mark-model.js';
import {PendingCommand} from '../dist/pending-command.js';

const context={contextId:'synthetic-market-context',asOf:'2032-03-14T08:00:00.123456Z',businessDate:'2032-03-13',snapshotId:'synthetic-working-inputs'};
const target={definitionRevisionId:'synthetic-definition',referenceCatalogId:'synthetic-reference',referenceRevisionId:'synthetic-reference-version',
 curveCode:'synthetic-rights',contractId:'synthetic-contract',seriesId:'synthetic-series',source:'synthetic_source',quote:'synthetic_quote',
 observedAt:context.asOf,sourceEventId:'imported opaque event',sourceRevisionToken:'manual_point_revision_v1:opaque-token',expectedPreviousObservationId:null};
const originalInputs={snapshotId:context.snapshotId,fingerprint:'a'.repeat(64)};
const body=(value='20.00')=>({operationId:'synthetic-operation',ownerId:'synthetic-market-owner',context:structuredClone(context),
 policy:'manual_final_direct_point_trader_mark_v1',target:structuredClone(target),value,evidence:'Synthetic price evidence\nExact source',originalInputs:structuredClone(originalInputs)});
const command=request=>Object.fromEntries(['policy','target','value','evidence','originalInputs'].map(key=>[key,structuredClone(request[key])]));
function reply(request){
 const canonical={...command(request),value:request.value==='20.00'?'20':request.value};
 return{operationId:request.operationId,ownerId:request.ownerId,context:{...request.context,asOf:request.context.asOf.replace('Z','+00:00')},
  requestedCommand:command(request),command:canonical,acknowledgement:false,
  outcome:{operationId:request.operationId,observationId:'synthetic-observation',changed:true,...Object.fromEntries(Object.entries(canonical.target).filter(([key])=>!['curveCode','sourceRevisionToken','expectedPreviousObservationId'].includes(key))),
   sourceRevisionId:canonical.target.sourceRevisionToken,previousObservationId:canonical.target.expectedPreviousObservationId,value:canonical.value,knowledgeEventOrder:42,publicationXid:'1234'},
  overviewSections:[{label:'Publication',values:[{label:'Signed value',value:canonical.value+' USD / package'}]}]};
}

test('setup attests the requested source, point clock and complete selected search page without needing an observation',()=>{
 const request={context,source:Object.fromEntries(['definitionRevisionId','referenceCatalogId','referenceRevisionId'].map(key=>[key,target[key]])),curveCode:target.curveCode,contractId:null,search:'Synthetic',offset:0,limit:50,quoteFilter:null,eligibility:null};
 const setup={ownerId:'synthetic-market-owner',context,source:request.source,policy:{code:body().policy,label:'Manual final market value'},
  choices:[{label:'Synthetic whole package',target,valueUnit:'USD / package',currency:'USD',previous:null}],unavailable:[],canPublish:true,page:{offset:0,limit:50,hasMore:false,search:'Synthetic'},originalInputs};
 assert.deepEqual(requirePointSetup(request,setup),setup);
 for(const change of [s=>s.source.referenceRevisionId='another-reference',s=>s.page.search='Another query',s=>s.context.contextId='another-context',
  s=>s.choices[0].target.observedAt='2032-03-14T08:00:00.123457Z',s=>s.choices[0].previous={observationId:'another-predecessor',value:'19',sourceRevisionId:'original imported revision'},s=>delete s.canPublish]){
  const bad=structuredClone(setup);change(bad);assert.throws(()=>requirePointSetup(request,bad),/setup|source|point|exact/i);
 }
});

test('review retains the original operation, exact source clock and backend canonical value without deriving a price',()=>{
 const request=body(),review=reply(request),record=reviewedPointRequest(request,review);
 assert.deepEqual(record,{...request,...review.command});assert.equal(record.context.businessDate,'2032-03-13','the explicit business date is not the UTC instant date');
 assert.equal(record.target.sourceEventId,'imported opaque event');assert.equal(record.target.expectedPreviousObservationId,null);
 assert.equal(record.value,'20');assert.equal(request.value,'20.00');assert.equal(record.operationId,request.operationId);
 for(const value of ['0','-20','0.000000000000000001'])assert.equal(reviewedPointRequest(body(value),reply(body(value))).value,value);
});

test('a changed raw input echo, target, source context or irrelevant field cannot become a reviewed publication',()=>{
 const changes=[
  result=>result.requestedCommand.value='21',result=>result.requestedCommand.evidence='Another request',
  result=>result.command.target.seriesId='another-series',result=>delete result.command.target.expectedPreviousObservationId,
  result=>result.context.contextId='another-context',result=>result.context.businessDate='2032-03-14',
  result=>result.command.target.observedAt='2032-03-14T08:00:00.123457Z',result=>result.ownerId='another-owner',
  result=>result.operationId='another-operation',result=>result.command.price='20',result=>delete result.acknowledgement,
 ];
 for(const change of changes){const request=body(),result=reply(request);change(result);assert.throws(()=>reviewedPointRequest(request,result),/review|exact|publication/i);}
});

test('a retained receipt must identify its complete canonical point and accepted native observation lineage',()=>{
 const request=body('20'),receipt=reply(request);assert.doesNotThrow(()=>requirePointReceipt(request,receipt));
 const changes=[value=>value.outcome.operationId='another-operation',value=>value.outcome.seriesId='another-series',
  value=>value.outcome.referenceRevisionId='another-reference',value=>value.outcome.sourceEventId='another-event',
  value=>value.outcome.sourceRevisionId='another-token',value=>value.outcome.previousObservationId='another-predecessor',
  value=>value.outcome.value='21',value=>delete value.outcome.observationId,value=>value.command.evidence='Different request',
  value=>value.context.asOf='2032-03-14T08:00:00.123457Z',value=>delete value.acknowledgement];
 for(const change of changes){const bad=structuredClone(receipt);change(bad);assert.throws(()=>requirePointReceipt(request,bad),/receipt|exact|retained/i);}
 // An exact recovery keeps the first changed:true outcome. It is still an acknowledgement.
 receipt.acknowledgement=true;assert.doesNotThrow(()=>requirePointReceipt(request,receipt));
 receipt.outcome.changed=false;assert.doesNotThrow(()=>requirePointReceipt(request,receipt));
});

test('edited input offers stay distinct from publication and require their exact original snapshot fingerprint',()=>{
 const request=body('20'),receipt=reply(request);
 receipt.editedSelection={state:'available',selectionId:'synthetic-edited-inputs',originalSnapshotId:context.snapshotId,fingerprint:originalInputs.fingerprint};
 assert.deepEqual(pointEditedSelection(request,receipt.editedSelection),receipt.editedSelection);
 const mismatch={...receipt.editedSelection,fingerprint:'b'.repeat(64)};assert.throws(()=>pointEditedSelection(request,mismatch),/inputs|selection|original/i);
 assert.doesNotThrow(()=>requirePointReceipt(request,{...receipt,editedSelection:mismatch}),'optional view failure cannot invalidate a genuine business receipt');
 assert.deepEqual(pointEditedSelection({...request,originalInputs:null},{state:'unavailable',reason:'No original input selection'}),{state:'unavailable',reason:'No original input selection'});
 assert.throws(()=>pointEditedSelection({...request,originalInputs:null},receipt.editedSelection),/inputs|selection|original/i);
});

test('explicit input application attests the operation, owner, stable selection and unchanged exact business clock',()=>{
 const request=body('20'),offer={state:'available',selectionId:'synthetic-edited-inputs',originalSnapshotId:context.snapshotId,fingerprint:originalInputs.fingerprint};
 const result={operationId:request.operationId,ownerId:request.ownerId,selectionId:offer.selectionId,originalSnapshotId:offer.originalSnapshotId,fingerprint:offer.fingerprint,frame:{id:offer.selectionId,name:'Edited selected inputs',at:context.asOf,businessDate:context.businessDate,originCloseId:null,close:null}};
 assert.deepEqual(requirePointInputs(request,offer,result),result.frame);
 for(const change of [r=>r.operationId='another-operation',r=>r.ownerId='another-owner',r=>r.fingerprint='b'.repeat(64),r=>r.frame.id='another-selection',
  r=>r.frame.businessDate='2032-03-14',r=>r.frame.at='2032-03-14T08:00:00.123457Z',r=>r.frame.originCloseId='old-close',r=>r.frame.contextId='old-context']){
  const bad=structuredClone(result);change(bad);assert.throws(()=>requirePointInputs(request,offer,bad),/inputs|selection|exact/i);
 }
});

test('market recovery restores only the exact closed record path and never substitutes an identity or missing explicit predecessor',()=>{
 const request=body('0'),saved={path:'market-values/record',operationId:request.operationId,body:request,uncertain:true,label:'Publish selected market value'};
 assert.deepEqual(restorePointRequest(saved),saved);assert.equal(restorePointRequest({...saved,path:'gas/operations/record'}),undefined);
 assert.equal(restorePointRequest({...saved,operationId:'another-operation'}),undefined);
 const missing=structuredClone(saved);delete missing.body.target.expectedPreviousObservationId;assert.equal(restorePointRequest(missing),undefined);
 const absentSnapshot=structuredClone(saved);absentSnapshot.body.originalInputs=null;delete absentSnapshot.body.context.snapshotId;
 assert.deepEqual(restorePointRequest(absentSnapshot),absentSnapshot,'business recovery does not require a frame');
});

test('retained market transport preserves its original header stamp without adding it to the business body',()=>{
 const request=body('20'),saved={path:'market-values/record',operationId:request.operationId,body:request,uncertain:true,scopeStamp:'original explicit header'};
 assert.deepEqual(restorePointRequest(saved),saved);assert.equal(Object.hasOwn(request,'scopeStamp'),false);
});

test('only frozen first-send business refusals release a request; optional input errors and refused uncertain retries retain it',()=>{
 for(const suffix of ['input','source','context','stale','conflict','denied','owner_changed','policy','reference'])assert.equal(pointPublicationRejection('point_trader_mark_'+suffix),true);
 for(const code of ['point_trader_mark_inputs','point_trader_mark_inputs_context','point_trader_mark_unknown','access_denied',undefined])assert.equal(pointPublicationRejection(code),false);
 const pending=new PendingCommand(pointPublicationRejection);pending.begin('market-values/record',body(),()=> 'synthetic-operation');pending.failed('point_trader_mark_stale',false);assert.equal(pending.command,undefined);
 pending.begin('market-values/record',body(),()=> 'synthetic-operation');pending.sending();pending.failed('point_trader_mark_stale',true);assert.equal(pending.command.operationId,'synthetic-operation');assert.equal(pending.command.uncertain,true);
});

test('an equal-value acknowledgement retains the imported accepted predecessor without reserving the prospective manual revision',()=>{
 const request=body('20');request.target.expectedPreviousObservationId='synthetic-C';request.target.sourceRevisionToken='manual_point_revision_v1:prospective-D';
 const acknowledged=reply(request);acknowledged.acknowledgement=true;acknowledged.outcome.changed=false;acknowledged.outcome.observationId='synthetic-C';
 acknowledged.outcome.sourceRevisionId='imported opaque revision\u00a0';acknowledged.outcome.previousObservationId='synthetic-B';
 assert.deepEqual(reviewedPointRequest(request,acknowledged),request);assert.doesNotThrow(()=>requirePointReceipt(request,acknowledged));
 assert.equal(request.target.sourceRevisionToken,'manual_point_revision_v1:prospective-D','acknowledgement does not rewrite or consume the requested revision');
 for(const change of [r=>r.outcome.observationId='another-predecessor',r=>r.outcome.value='21',r=>r.outcome.sourceEventId='another-event',r=>r.outcome.changed=true]){
  const bad=structuredClone(acknowledged);change(bad);assert.throws(()=>requirePointReceipt(request,bad),/receipt|retained|exact/i);
 }
 const next={...structuredClone(request),operationId:'synthetic-D21',value:'21'},changed=reply(next);
 changed.outcome.observationId='synthetic-D';
 assert.deepEqual(reviewedPointRequest(next,changed),next,'the same prospective D can record a genuinely changed value');
 assert.doesNotThrow(()=>requirePointReceipt(request,acknowledged),'old D20 recovery still identifies accepted C after D21');
});
