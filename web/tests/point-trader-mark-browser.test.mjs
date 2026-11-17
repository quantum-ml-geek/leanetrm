import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

const browser={skip:!browserAvailable,timeout:browserTestTimeout};
const fixture=`(async()=>{
 window.calls=[];window.errors=[];window.applications=[];window.actor='synthetic-market-editor';window.zone='UTC';window.rights=['ReadMarketData','ImportObservations'];window.historical=false;
 window.source={definitionRevisionId:'synthetic-definition',referenceCatalogId:'synthetic-reference',referenceRevisionId:'synthetic-reference-version'};
 window.context={contextId:'synthetic-market-context',asOf:'2032-03-14T08:00:00.123456Z',businessDate:'2032-03-13',snapshotId:'synthetic-original-inputs'};
 window.scope={stamp:'synthetic-header-a',source,curveCode:'synthetic-rights',frame:{id:context.snapshotId,name:'Explicit independent inputs',at:context.asOf,businessDate:context.businessDate},quoteFilter:null,eligibility:null};
 window.target={...source,curveCode:'synthetic-rights',contractId:'synthetic-contract',seriesId:'synthetic-series',source:'synthetic_source',quote:'synthetic_quote',observedAt:context.asOf,sourceEventId:'imported opaque event',sourceRevisionToken:'manual_point_revision_v1:opaque-token',expectedPreviousObservationId:null};
 const command=body=>Object.fromEntries(['policy','target','value','evidence','originalInputs'].map(key=>[key,structuredClone(body[key])]));
 window.reply=body=>{const canonical={...command(body),value:body.value==='20.00'?'20':body.value};const result={operationId:body.operationId,ownerId:body.ownerId,context:body.context,requestedCommand:command(body),command:canonical,acknowledgement:false,
  outcome:{operationId:body.operationId,observationId:'synthetic-observation',changed:true,...Object.fromEntries(Object.entries(canonical.target).filter(([key])=>!['curveCode','sourceRevisionToken','expectedPreviousObservationId'].includes(key))),sourceRevisionId:canonical.target.sourceRevisionToken,previousObservationId:canonical.target.expectedPreviousObservationId,value:canonical.value,knowledgeEventOrder:42,publicationXid:'1234'},
  overviewSections:[{label:'Market publication',values:[{label:'Signed value',value:canonical.value+' USD / package'},{label:'Value time',value:body.target.observedAt,kind:'instant'},{label:'Evidence',value:'2032-03-14T08:00:00Z'},{label:'Financial adoption',value:'Separate reviewed operation'}]}],
  editedSelection:body.originalInputs?{state:'available',selectionId:'synthetic-edited-inputs',originalSnapshotId:body.originalInputs.snapshotId,fingerprint:body.originalInputs.fingerprint}:{state:'unavailable',reason:'No original input selection'}};
  if(window.predecessorAck){result.acknowledgement=true;Object.assign(result.outcome,{observationId:body.target.expectedPreviousObservationId,changed:false,sourceRevisionId:'imported opaque revision C',previousObservationId:'synthetic-B'});}return result;};
 window.api=async(path,body)=>{calls.push({path,body:structuredClone(body)});
  if(path==='time/inspect'){const value={candidates:[{instant:body.localTime+(body.localTime.length===16?':00':'')+'Z',offset:'+00:00'}]};if(window.holdClock)return new Promise(resolve=>window.answerClock=()=>resolve(value));return value;}
  if(path==='date-schedules/context')return{context:{contextId:'synthetic-market-context-'+body.effectiveOn,effectiveOn:body.effectiveOn,knownAt:'2032-03-15T20:00:00Z'},coverageFrom:'2030-01-01T00:00:00Z',certifiedThrough:'2032-03-15T20:00:00Z'};
  if(path==='market-values/setup'){
   if(window.denySetup)throw Object.assign(Error('Synthetic source access denied'),{code:'access_denied'});
   const result={ownerId:'synthetic-market-owner',context:body.context,source:body.source,policy:{code:'manual_final_direct_point_trader_mark_v1',label:'Final manual point value'},choices:[{label:'Synthetic whole package',target:{...target,observedAt:body.context.asOf},valueUnit:'USD / package',currency:'USD',previous:target.expectedPreviousObservationId?{observationId:target.expectedPreviousObservationId,value:'20',sourceRevisionId:'imported opaque revision C'}:null}],unavailable:[{label:'Synthetic preliminary point',reason:'A preliminary value cannot be finalized here.'}],canPublish:true,page:{offset:body.offset,limit:body.limit,hasMore:body.search==='broad',search:window.wrongSearch?'another search':body.search},originalInputs:body.context.snapshotId?{snapshotId:body.context.snapshotId,fingerprint:'a'.repeat(64)}:null};
   if(window.quoteChoices)result.choices=structuredClone(quoteChoices);if(window.noOriginalInputs)result.originalInputs=null;if(window.holdSetup)return new Promise(resolve=>window.answerSetup=()=>resolve(result));return result;
  }
  if(path==='market-values/preview'){const value=reply(body);if(window.wrongEcho)value.requestedCommand.value='another amount';if(window.badInstant)value.overviewSections[0].values[1].value='not an instant';if(window.holdPreview)return new Promise(resolve=>window.answerPreview=()=>resolve(value));return value;}
  if(path==='market-values/record'){window.original=structuredClone(body);if(window.holdRecord)return new Promise((_resolve,reject)=>window.failRecord=()=>reject(Error('Synthetic original actor private source')));if(window.rejectRetry)throw Object.assign(Error('Synthetic original source is now stale'),{code:'point_trader_mark_stale'});if(window.lost)throw new TypeError('Synthetic lost accepted response');const value=reply(body);if(window.badOffer)value.editedSelection.fingerprint='b'.repeat(64);return value;}
  if(path==='market-values/status'){if(window.absent)return{found:false};const value={...reply(original),found:true,acknowledgement:true};if(window.wrongReceipt)value.outcome.seriesId='another-series';return value;}
  if(path==='market-values/inputs')return{...body,frame:{id:window.wrongInputs?'another-frame':body.selectionId,name:'Edited selected inputs',at:original.context.asOf,businessDate:original.context.businessDate,originCloseId:null,close:null}};
  throw Error('Unexpected market-value operation '+path);
 };
 window.until=async test=>{for(let i=0;i<300&&!test();i++)await new Promise(resolve=>setTimeout(resolve,10));if(!test())throw Error('Point controls not ready '+JSON.stringify(errors));};
 window.mount=()=>window.publisher=window.createPublisher(document.querySelector('#host'),{api,act:async work=>{try{await work();}catch(error){errors.push(error.message);}},busy:()=>false,identity:()=>actor,zone:()=>zone,permission:name=>rights.includes(name),historical:()=>historical,selection:()=>scope,changed(){},applyFrame:async(frame,current)=>{if(!current())throw Error('Synthetic changed header');applications.push(frame);}});
 window.createPublisher=(await import('/point-trader-mark-view.js')).setupPointTraderMark;mount();await publisher.load(context);
 window.pick=(name,value)=>{const input=document.querySelector('[name='+name+']');if(!input)throw Error('Missing '+name);input.value=value;input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));};
 window.prepare=async(value='20.00')=>{pick('point','0');pick('policy','manual_final_direct_point_trader_mark_v1');pick('value',value);pick('evidence','Synthetic publication evidence');document.querySelector('[data-point-value=entry]').requestSubmit();await until(()=>!!document.querySelector('[data-point-value=publish]'));};
})()`;

test('a missing first observation offers explicit blank point/policy/value controls and publishes only the reviewed canonical string',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);
 assert.deepEqual(await evaluate("['point','policy','value'].map(name=>document.querySelector('[name='+name+']').value)"),['','','']);
 assert.match(await evaluate("document.querySelector('#host').textContent"),/preliminary value cannot be finalized/);
 await evaluate("prepare('0')");assert.equal(await evaluate("calls.some(call=>call.path.endsWith('/record'))"),false);
 await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!window.original)");
 const record=await evaluate('original');assert.equal(record.value,'0');assert.equal(record.target.expectedPreviousObservationId,null);assert.equal(record.target.sourceEventId,'imported opaque event');
 assert.equal(await evaluate('applications.length'),0,'publication does not select inputs or adopt a financial value');
 assert.equal(await evaluate("calls.every(call=>call.path.startsWith('market-values/'))"),true);
}));

test('new publication reviews accept exact negative values and display only backend-marked instants in the current zone',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("prepare('-20')");
 await evaluate("zone='America/Chicago';publisher.refresh()");
 const facts=await evaluate("document.querySelector('[data-point-value=review]').textContent");assert.match(facts,/-20 USD \/ package/);assert.match(facts,/2032-03-14T08:00:00Z/,'plain evidence stays literal');assert.match(facts,/America\/Chicago|CDT|CST/);
 await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!window.original)");assert.equal(await evaluate('original.value'),'-20');
}));

test('same-valued points disclose their exact backend currency and quote unit, and changing point clears the entered value',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("quoteChoices=[{label:'Synthetic package quote',target:{...target,expectedPreviousObservationId:'synthetic-C'},currency:'USD',valueUnit:'USD / package · quote multiplier 1',previous:{observationId:'synthetic-C',value:'20',sourceRevisionId:'imported-C'}},{label:'Synthetic energy quote',target:{...target,contractId:'synthetic-other-contract',seriesId:'synthetic-other-series',expectedPreviousObservationId:'synthetic-D'},currency:'EUR',valueUnit:'EUR / kWh · quote multiplier 1000',previous:{observationId:'synthetic-D',value:'20',sourceRevisionId:'imported-D'}}];publisher.load(context)");
 await evaluate("pick('point','0')");assert.match(await evaluate("document.querySelector('[data-point-value=selected-unit]')?.textContent??''"),/USD.*USD \/ package · quote multiplier 1/);
 await evaluate("pick('value','20');pick('point','1')");assert.equal(await evaluate("document.querySelector('[name=value]').value"),'');
 assert.match(await evaluate("document.querySelector('[data-point-value=selected-unit]').textContent"),/EUR.*EUR \/ kWh · quote multiplier 1000/);
 assert.equal(await evaluate("document.querySelector('[name=policy]').value"),'');assert.equal(await evaluate("calls.some(call=>call.path.endsWith('/record'))"),false);
}));

test('equal current values explicitly acknowledge the imported predecessor without consuming the prospective revision',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("target.expectedPreviousObservationId='synthetic-C';target.sourceRevisionToken='prospective-D';predecessorAck=true;publisher.load(context)");
 assert.equal(await evaluate("document.querySelector('[name=value]').value"),'');
 await evaluate("prepare('20')");assert.match(await evaluate("document.querySelector('[data-point-value=review]').textContent"),/acknowledg/i);
 assert.match(await evaluate("document.querySelector('[data-point-value=publish]').textContent"),/acknowledg/i);
 await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!window.original)");
 assert.equal(await evaluate('original.target.sourceRevisionToken'),'prospective-D');assert.equal(await evaluate('applications.length'),0);
 assert.match(await evaluate("document.querySelector('[data-point-value=receipt]').textContent"),/acknowledg/i);
 await evaluate("predecessorAck=false;publisher.load(context)");await evaluate("(async()=>{await prepare('21');document.querySelector('[data-point-value=publish]').click();await until(()=>original.value==='21');})()");
 assert.equal(await evaluate('original.target.sourceRevisionToken'),'prospective-D');assert.equal(await evaluate('original.target.expectedPreviousObservationId'),'synthetic-C');
}));

test('wrong raw review echoes and invalid instant markers withhold publication',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);
 for(const flag of ['wrongEcho','badInstant']){
  await evaluate(`(async()=>{window.${flag}=true;pick('point','0');pick('policy','manual_final_direct_point_trader_mark_v1');pick('value','20');pick('evidence','Synthetic evidence');document.querySelector('[data-point-value=entry]').requestSubmit();await until(()=>errors.length>0);})()`);
  assert.equal(await evaluate("document.querySelector('[data-point-value=publish]')"),null);await evaluate(`window.${flag}=false;errors=[];publisher.load(context)`);
 }
 assert.equal(await evaluate("calls.some(call=>call.path.endsWith('/record'))"),false);
}));

test('a lost publication recovers exact actor/request lineage without fresh setup, ImportObservations or an automatic old input switch',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("lost=true;prepare('20')");await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!window.original)");
 await evaluate("publisher.reset();denySetup=true;rights=['ReadMarketData'];mount();publisher.sync()");
 assert.equal(await evaluate("document.querySelector('[data-point-value=pending]').hidden"),false);assert.equal(await evaluate("document.querySelector('[data-point-value=status]').disabled"),false);assert.equal(await evaluate("document.querySelector('[data-point-value=retry]').disabled"),true);
 await evaluate("wrongReceipt=true;document.querySelector('[data-point-value=status]').click();until(()=>errors.some(error=>error.includes('receipt')))");assert.equal(await evaluate("document.querySelector('[data-point-value=pending]').hidden"),false);
 await evaluate("actor='another-market-reader';publisher.reset();publisher.sync()");assert.equal(await evaluate("document.querySelector('[data-point-value=pending]').hidden"),true);
 await evaluate("actor='synthetic-market-editor';scope={...scope,stamp:'another-header'};publisher.reset();publisher.sync();wrongReceipt=false;document.querySelector('[data-point-value=status]').click();until(()=>document.querySelector('[data-point-value=pending]').hidden)");
 assert.equal(await evaluate('applications.length'),0);assert.equal(await evaluate("document.querySelector('[data-point-value=inputs]')?.disabled??true"),true);
 const calls=await evaluate('calls'),record=calls.find(call=>call.path.endsWith('/record')).body;
 for(const call of calls.filter(call=>call.path.endsWith('/status')))assert.deepEqual(call.body,{ownerId:record.ownerId,operationId:record.operationId});
 assert.equal(calls.filter(call=>call.path.endsWith('/record')).length,1);assert.equal(calls.filter(call=>call.path.endsWith('/setup')).length,1);
}));

test('an unavailable original input view omits its selected snapshot hint from the durable publication and status identity',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("noOriginalInputs=true;lost=true;publisher.load(context)");
 await evaluate("prepare('20')");
 const preview=await evaluate("calls.find(call=>call.path==='market-values/preview').body");
 assert.equal(preview.originalInputs,null);assert.equal(preview.context.snapshotId??null,null,'a missing optional view cannot leave an unrecoverable snapshot hint');
 await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!window.original)");
 assert.equal(await evaluate('original.context.snapshotId??null'),null);
 await evaluate("rights=['ReadMarketData'];publisher.sync();document.querySelector('[data-point-value=status]').click();until(()=>document.querySelector('[data-point-value=pending]').hidden)");
 assert.equal(await evaluate('applications.length'),0);assert.match(await evaluate("document.querySelector('[data-point-value=receipt]').textContent"),/acknowledged/);
}));

test('edited inputs require a separate click and exact frame attestation while malformed optional offers do not make a saved price uncertain',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("prepare('20.00')");await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!document.querySelector('[data-point-value=inputs]'))");
 assert.equal(await evaluate('original.value'),'20');assert.equal(await evaluate('applications.length'),0);
 await evaluate("wrongInputs=true;document.querySelector('[data-point-value=inputs]').click();until(()=>errors.some(error=>error.includes('inputs')))");assert.equal(await evaluate('applications.length'),0);
 await evaluate("wrongInputs=false;document.querySelector('[data-point-value=inputs]').click();until(()=>applications.length===1)");
 const apply=await evaluate("calls.findLast(call=>call.path.endsWith('/inputs')).body");assert.deepEqual(apply,{ownerId:'synthetic-market-owner',operationId:await evaluate('original.operationId'),selectionId:'synthetic-edited-inputs',originalSnapshotId:'synthetic-original-inputs',fingerprint:'a'.repeat(64)});
 await evaluate("(async()=>{await publisher.load(context);badOffer=true;await prepare('20');document.querySelector('[data-point-value=publish]').click();await until(()=>document.querySelector('[data-point-value=pending]').hidden);})()");
 assert.match(await evaluate("document.querySelector('[data-point-value=receipt]').textContent"),/recorded|published/i);assert.equal(await evaluate("document.querySelector('[data-point-value=inputs]')?.disabled??true"),true);
}));

test('snapshot-free setup captures explicit business date and AsOf with pure market authority',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("scope={...scope,frame:null,stamp:'no-frame'};publisher.reset();publisher.load()");
 assert.equal(await evaluate("document.querySelector('[name=businessDate]').value"),'');assert.equal(await evaluate("document.querySelector('[name=valueAt]').value"),'');
 await evaluate("pick('businessDate','2032-03-13');pick('valueAt','2032-03-14T08:00:00');pick('knowledgeMode','current');document.querySelector('[data-point-value=read-form]').requestSubmit();until(()=>calls.filter(call=>call.path.endsWith('/setup')).length===2)");
 const calls=await evaluate('calls'),capture=calls.find(call=>call.path==='date-schedules/context'),setup=calls.filter(call=>call.path.endsWith('/setup')).at(-1);
 assert.deepEqual(capture.body,{effectiveOn:'2032-03-13',knownAt:null,mode:'current'});assert.equal(setup.body.context.asOf,'2032-03-14T08:00:00Z');assert.equal(setup.body.context.businessDate,'2032-03-13');assert.equal(setup.body.context.snapshotId??null,null);
 assert.equal(setup.body.quoteFilter,null);assert.equal(setup.body.eligibility,null);assert.equal(calls.some(call=>/trading|lifecycle|gas\//.test(call.path)),false);
}));

test('source/actor changes invalidate late reviews and search echo conflicts cannot replace exact point choices',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("holdPreview=true;pick('point','0');pick('policy','manual_final_direct_point_trader_mark_v1');pick('value','20');pick('evidence','Synthetic evidence');document.querySelector('[data-point-value=entry]').requestSubmit();until(()=>!!window.answerPreview)");
 await evaluate("scope={...scope,stamp:'another-header'};publisher.reset();answerPreview();new Promise(resolve=>setTimeout(resolve,30))");assert.equal(await evaluate("document.querySelector('[data-point-value=publish]')"),null);
 await evaluate("(async()=>{scope={...scope,stamp:'synthetic-header-a'};holdPreview=false;await publisher.load(context);wrongSearch=true;pick('search','broad');document.querySelector('[data-point-value=search-form]').requestSubmit();await until(()=>errors.length>0);})()");
 assert.equal(await evaluate("document.querySelector('[name=point]')"),null);
 assert.equal(await evaluate("calls.some(call=>call.path.endsWith('/record'))"),false);
}));

test('market-only readers can inspect explicit point choices while missing publication permission or historical selection withholds review',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("rights=['ReadMarketData'];publisher.sync()");
 assert.equal(await evaluate("document.querySelector('[data-point-value=entry] button[type=submit]').disabled"),true);
 assert.match(await evaluate("document.querySelector('#host').textContent"),/Synthetic whole package/);
 await evaluate("rights=['ReadMarketData','ImportObservations'];historical=true;publisher.load(context)");
 assert.equal(await evaluate("document.querySelector('[data-point-value=entry] button[type=submit]').disabled"),true);
 assert.equal(await evaluate("calls.some(call=>call.path.endsWith('/preview')||call.path.endsWith('/record'))"),false);
}));

test('clock edits block the old review but preserve an entered value until explicit refresh discard',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("(async()=>{await prepare('20');pick('businessDate','2032-03-12');pick('knowledgeMode','current');})()");
 assert.equal(await evaluate("document.querySelector('[name=value]')?.value??null"),'20');
 assert.equal(await evaluate("document.querySelector('[data-point-value=publish]')"),null);
 await evaluate("document.querySelector('[data-point-value=read-form]').requestSubmit();until(()=>!document.querySelector('#host-prompt').hidden)");
 await evaluate("document.querySelector('#host-prompt button:first-child').click();new Promise(resolve=>setTimeout(resolve,20))");
 assert.equal(await evaluate("document.querySelector('[name=value]').value"),'20');assert.equal(await evaluate("calls.filter(call=>call.path.endsWith('/setup')).length"),1);
 await evaluate("document.querySelector('[data-point-value=read-form]').requestSubmit();until(()=>!document.querySelector('#host-prompt').hidden)");
 await evaluate("document.querySelector('#host-prompt button:last-child').click();until(()=>calls.filter(call=>call.path.endsWith('/setup')).length===2)");
 assert.equal(await evaluate("document.querySelector('[name=value]').value"),'');
}));

test('late clock resolution cannot capture an earlier business date after the publication criteria change',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("scope={...scope,frame:null,stamp:'no-frame'};publisher.reset();publisher.load()");
 await evaluate("holdClock=true;pick('businessDate','2032-03-13');pick('valueAt','2032-03-14T08:00:00');pick('knowledgeMode','current');document.querySelector('[data-point-value=read-form]').requestSubmit();until(()=>!!window.answerClock)");
 await evaluate("pick('businessDate','2032-03-12');answerClock();new Promise(resolve=>setTimeout(resolve,30))");
 assert.equal(await evaluate("calls.some(call=>call.path==='date-schedules/context')"),false);
 assert.equal(await evaluate("document.querySelector('[name=point]')"),null);
}));

test('late setup cannot restore old point choices over changed publication-clock criteria',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("holdSetup=true;window.loading=publisher.load(context);until(()=>!!window.answerSetup)");
 await evaluate("pick('businessDate','2032-03-12');answerSetup();loading");
 assert.equal(await evaluate("document.querySelector('[name=point]')"),null);
 assert.equal(await evaluate("document.querySelector('[name=businessDate]').value"),'2032-03-12');
}));

test('a late original-actor publication error cannot appear for another account or discard the original recovery request',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("(async()=>{holdRecord=true;await prepare('20');document.querySelector('[data-point-value=publish]').click();await until(()=>!!window.failRecord);})()");
 await evaluate("actor='another-market-reader';publisher.reset();failRecord();new Promise(resolve=>setTimeout(resolve,30))");
 assert.doesNotMatch(await evaluate("document.querySelector('[data-point-value=message]').textContent"),/private source/);assert.doesNotMatch(await evaluate('errors.join()'),/private source/);
 assert.equal(await evaluate("document.querySelector('[data-point-value=pending]').hidden"),true);
 await evaluate("actor='synthetic-market-editor';publisher.reset();publisher.sync()");assert.equal(await evaluate("document.querySelector('[data-point-value=pending]').hidden"),false);
}));

test('submitted source search keeps its exact echo and refine notice across a confirmed refresh without selecting a returned point',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("pick('search','broad');document.querySelector('[data-point-value=search-form]').requestSubmit();until(()=>calls.filter(call=>call.path.endsWith('/setup')).length===2)");
 assert.match(await evaluate("document.querySelector('[data-point-value=search-hint]').textContent"),/more|refine/i);
 assert.equal(await evaluate("document.querySelector('[name=point]').value"),'');
 await evaluate("document.querySelector('[data-point-value=refresh]').click();until(()=>calls.filter(call=>call.path.endsWith('/setup')).length===3)");
 assert.equal(await evaluate("calls.filter(call=>call.path.endsWith('/setup')).at(-1).body.search"),'broad');
 assert.equal(await evaluate("document.querySelector('[name=point]').value"),'');
}));

test('local dismissal requires a fresh checked absence and explicit warning, and never cancels or resubmits the original publication',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate("lost=true;prepare('20')");await evaluate("document.querySelector('[data-point-value=publish]').click();until(()=>!!window.original)");
 assert.equal(await evaluate("document.querySelector('[data-point-value=dismiss]').disabled"),true);
 await evaluate("absent=true;document.querySelector('[data-point-value=status]').click();until(()=>!document.querySelector('[data-point-value=dismiss]').disabled)");
 await evaluate("lost=false;rejectRetry=true;document.querySelector('[data-point-value=retry]').click();until(()=>errors.some(error=>error.includes('stale')))");
 assert.equal(await evaluate("document.querySelector('[data-point-value=dismiss]').disabled"),true,'sending invalidates the previous absence check');
 await evaluate("document.querySelector('[data-point-value=status]').click();until(()=>!document.querySelector('[data-point-value=dismiss]').disabled)");
 await evaluate("document.querySelector('[data-point-value=dismiss]').click();until(()=>!document.querySelector('#host-prompt').hidden)");
 assert.match(await evaluate("document.querySelector('#host-prompt').textContent"),/local|cancel|complete/i);
 await evaluate("document.querySelector('#host-prompt button:last-child').click();until(()=>document.querySelector('[data-point-value=pending]').hidden)");
 assert.equal(await evaluate("document.querySelector('[name=point]')"),null,'another point requires a fresh read');
 assert.equal(await evaluate("calls.filter(call=>call.path.endsWith('/record')).length"),2);assert.equal(await evaluate('applications.length'),0);
}));
