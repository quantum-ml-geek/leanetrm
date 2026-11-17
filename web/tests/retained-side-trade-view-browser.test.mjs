import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
const browser={skip:!browserAvailable,timeout:browserTestTimeout};
const fixture=`(async()=>{
 const module=await import('/retained-side-trade-view.js');window.read=module.readRetainedSideTrade;
 window.context={snapshotId:'selected-frame',knowledgeMode:'retained',contextId:'selected-cut'};
 window.holding={instrumentType:'operating_right',tradeId:'native-trade',bindingId:'native-binding',revision:'2',tradeReference:'TR000002',instrumentReference:'IN000002',book:'Synthetic book',unavailableReason:'Required price is missing.',executedAt:'2032-01-01T12:00:00Z',booking:{tradeDate:'2032-01-01'}};
 window.detail={tradeId:'native-trade',bindingId:'native-binding',instrumentId:'native-binding',revision:2,context:{contextId:'selected-cut',effectiveOn:'2032-01-15',knownAt:'2032-01-15T18:00:00Z'},asOf:'2032-01-15T16:00:00Z',
  retainedSource:{snapshotId:'selected-frame',contextId:'selected-cut',asOf:'2032-01-15T16:00:00Z',businessDate:'2032-01-15',knownAt:'2032-01-15T18:00:00Z'},
  sideGroups:[{instrumentId:'native-binding',bindingId:'native-binding',label:'Retained contract composition',sides:[{slot:0,sideId:'shared-definition',label:'Contract output',roleLabel:'Contractual output',directionLabel:'Company receives proceeds',overviewSections:[{label:'Terms',values:[{label:'Through',value:'2032-02-01T12:00:00Z',kind:'instant'}]}]},{slot:1,sideId:'shared-definition',label:'Contract expense',roleLabel:'Contractual expense',directionLabel:'Company pays',overviewSections:[{label:'Terms',values:[{label:'Amount basis',value:'Exact native contract'}]}]}]}]};
 window.calls=[];window.api=async(path,body)=>{calls.push({path,body:structuredClone(body)});return detail;};
})()`;
for(const type of ['operating_right','rec_forward'])test(type+' opens exact retained Sides without prices or current-knowledge recapture',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);await evaluate(`(async()=>{holding.instrumentType='${type}';window.opened=await read(api,context,holding);opened.view('America/Chicago').termsContent(document.querySelector('#host'));})()`);
 assert.equal(await evaluate("document.querySelectorAll('[data-instrument-side-slot]').length"),2);
 assert.match(await evaluate("document.querySelector('#host').textContent"),/Company receives proceeds.*Company pays/s);
 assert.match(await evaluate("document.querySelector('#host').textContent"),/CST/);
 assert.equal(await evaluate('holding.unavailableReason'),'Required price is missing.');
 assert.equal(await evaluate('calls.length'),1);
 const request=await evaluate('calls[0]');assert.equal(request.path,type==='operating_right'?'physical/power-trades/get':'rec/trades/get');
 assert.equal(request.body.context.contextId,'selected-cut');assert.equal(request.body.context.knowledgeMode,'retained');assert.equal(request.body.tradeId,'native-trade');
 if(type==='operating_right'){assert.equal(request.body.snapshotId,'selected-frame');assert.equal(request.body.bindingId,'native-binding');assert.equal(request.body.revision,2);}
 assert.equal(await evaluate("document.querySelectorAll('button,input,select').length"),0);
}));
test('foreign source/target or missing composition refuses rather than retrying a current read or valuation',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);
 for(const mutation of ["candidate.retainedSource.contextId='current-cut'","candidate.retainedSource.snapshotId='other-frame'","candidate.retainedSource.knownAt='2032-01-15T19:00:00Z'","candidate.bindingId='other-binding'",'candidate.revision=3','delete candidate.sideGroups','delete candidate.retainedSource']){
  assert.equal(await evaluate(`(async()=>{const candidate=structuredClone(detail);${mutation};try{await read(async(path,body)=>{calls.push({path,body});return candidate;},context,holding);return false;}catch{return true;}})()`),true,mutation);
 }
 assert.equal(await evaluate('calls.length'),7);assert.equal(await evaluate("document.querySelector('#host').children.length"),0);
}));
