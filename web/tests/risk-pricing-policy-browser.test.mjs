import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

const markup=(await readFile(new URL('../src/index.html',import.meta.url),'utf8')).replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,'');
const browser={skip:!browserAvailable,timeout:browserTestTimeout};
const setup=`(async()=>{
 window.calls=[];window.failures=[];window.catalogs=[];window.nativeOffered=true;
 const context={contextId:'synthetic-context',knownAt:'2026-01-01T00:00:00Z',knownThrough:1,effectiveOn:'2026-01-01'};
 window.basePolicy={implementation:'synthetic-base',gasOwned:null};
 window.nativePolicy={implementation:'synthetic-base',gasOwned:{implementation:'synthetic-native',source:'exact-owned-mark'}};
 const target={id:'synthetic-target',label:'Synthetic contract',coordinate:'market_quote',kind:'contract',unit:'USD',priceUnit:{},factor:{coordinate:'market_quote',target:{}}};
 window.api=async(path,body)=>{
  calls.push({path,body});
  if(path==='portfolio/risk/setup')return{selectedPricingPolicyId:'base',pricingPolicies:[{id:'base',label:'Contractual positions',pricingPolicy:basePolicy,wholeBooksOnly:false},...(body.tradeIds===null&&nativeOffered?[{id:'native-gas-v1',label:'Contractual positions and native gas ownership',pricingPolicy:nativePolicy,wholeBooksOnly:true}]:[])]};
  if(path==='trading/directory')return{kind:'directory',asOf:'2026-01-01T00:00:00Z',context,books:[{id:'book',name:'Synthetic book',portfolio_id:'portfolio',portfolio:'Synthetic portfolio'}]};
  if(path==='portfolio/risk/scope')return{trades:[{tradeId:'trade',bookId:'book',tradeReference:'T-1',product:'physical_gas_park_loan',available:true}],selectedTrades:[],total:1,allAvailable:true,nextOffset:null,contextId:context.contextId,snapshotId:'synthetic-snapshot',maxSelectedTrades:256};
  if(path==='portfolio/risk/jobs'){
   if(!body)return[];
   throw Error('Synthetic lost submission acknowledgement');
  }
  if(path.includes('/archive?'))return{items:[],next:null};
  if(path==='portfolio/risk/catalog'){
   catalogs.push(body);
   return{context,asOf:'2026-01-01T00:00:00Z',limits:{maxHoldingsBumps:16,maxBooksBumps:64,maxStress:4,maxParts:4},scenarioTargets:[target],heldContractTargets:[target.id],heldCurveTargets:[],heldContractsWithoutTarget:[],heldCurvesWithoutTarget:[],excludedPositions:[],bumpConvention:'synthetic',stressConvention:'synthetic',convention:'synthetic',numericalPolicy:'synthetic',pricingPolicy:body.pricingPolicy??basePolicy};
  }
  throw Error('Unexpected '+path);
 };
 window.until=async test=>{for(let i=0;i<300&&!test();i++)await new Promise(resolve=>setTimeout(resolve,10));if(!test())throw Error('Risk choice did not settle');};
 document.querySelector('#risk-page').hidden=false;
 window.risk=(await import('/risk-workspace.js')).setupRiskWorkspace({api,
  act:async work=>{try{await work();}catch(error){failures.push(error.message);}},busy:()=>false,zone:()=> 'UTC',identity:()=> 'synthetic-reader',canRun:()=>true,
  instant:value=>value,source:()=>({snapshotId:'synthetic-snapshot'}),convention:()=>null,frames:()=>[],changed(){},view(){}});
 await risk.load();risk.showView('risk-scenarios');await until(()=>catalogs.length===1);risk.sync();
})()`;

test('Risk explicitly selects an opaque native pricing policy and retains it in an uncertain original submission',browser,()=>withBrowserPage(markup,async evaluate=>{
 await evaluate(setup);
 assert.deepEqual(await evaluate("[...document.querySelector('#risk-workspace-pricing-policy').options].filter(option=>option.value).map(option=>[option.value,option.textContent])"),[['base','Contractual positions'],['native-gas-v1','Contractual positions and native gas ownership']]);
 assert.deepEqual(await evaluate('catalogs[0].pricingPolicy'),await evaluate('basePolicy'));
 await evaluate("(async()=>{document.querySelector('#risk-workspace-results').textContent='Synthetic previous result';const policy=document.querySelector('#risk-workspace-pricing-policy');policy.value='native-gas-v1';policy.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>catalogs.length===2);})()");
 assert.deepEqual(await evaluate('catalogs[1].pricingPolicy'),await evaluate('nativePolicy'));
 assert.equal(await evaluate("document.querySelector('#risk-workspace-results').textContent.includes('Synthetic previous result')"),false);
 await evaluate("(async()=>{document.querySelector('#workspace-risk-report input[name=risk-choice][value=held]').click();const size=document.querySelector('#workspace-risk-size-0');size.value='0.1';size.dispatchEvent(new Event('input',{bubbles:true}));document.querySelector('#workspace-risk-form').requestSubmit(document.querySelector('#workspace-risk-queue'));await until(()=>!!sessionStorage.getItem('openetrm.risk.workspace.submission.synthetic-reader'));})()");
 const retained=await evaluate("JSON.parse(sessionStorage.getItem('openetrm.risk.workspace.submission.synthetic-reader'))");
 assert.deepEqual(retained.parts[0].request.pricingPolicy,await evaluate('nativePolicy'));
 assert.deepEqual(retained.parts[0].command.body.request.pricingPolicy,await evaluate('nativePolicy'));
 await evaluate('risk.sync()');
 assert.equal(await evaluate("document.querySelector('#risk-workspace-pricing-policy').disabled"),true,'an uncertain submission keeps its exact policy until recovered');
}));

test('a chosen pricing policy survives refresh only while its complete backend choice remains available',browser,()=>withBrowserPage(markup,async evaluate=>{
 await evaluate(setup);
 await evaluate("(async()=>{const policy=document.querySelector('#risk-workspace-pricing-policy');policy.value='native-gas-v1';policy.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>catalogs.length===2);await risk.load();risk.showView('risk-scenarios');await until(()=>catalogs.length===3);})()");
 assert.equal(await evaluate("document.querySelector('#risk-workspace-pricing-policy').value"),'native-gas-v1');
 assert.deepEqual(await evaluate('catalogs.at(-1).pricingPolicy'),await evaluate('nativePolicy'));
 await evaluate('nativeOffered=false;risk.load()');
 await evaluate('risk.sync()');
 assert.equal(await evaluate("document.querySelector('#risk-workspace-pricing-policy').value"),'');
 assert.equal(await evaluate("document.querySelector('#risk-jobs-new').disabled"),true);
 assert.match(await evaluate("document.querySelector('#risk-workspace-pricing-help').textContent"),/unavailable.*choose/i);
 assert.equal(await evaluate('catalogs.length'),3,'removing an offered policy cannot silently read a base-policy catalog');
}));

test('changing pricing policy rereads the active static VaR catalog with that same opaque choice',browser,()=>withBrowserPage(markup,async evaluate=>{
 await evaluate(setup);
 await evaluate("(async()=>{document.querySelector('#risk-workspace-editor').open=false;risk.showView('risk-var');await until(()=>catalogs.length===2);const policy=document.querySelector('#risk-workspace-pricing-policy');policy.value='native-gas-v1';policy.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>catalogs.length===3);})()");
 assert.deepEqual(await evaluate('catalogs.at(-1).pricingPolicy'),await evaluate('nativePolicy'));
}));

test('a whole-book native ownership policy never widens an individual trade selection',browser,()=>withBrowserPage(markup,async evaluate=>{
 await evaluate(setup);
 await evaluate("(async()=>{const policy=document.querySelector('#risk-workspace-pricing-policy');policy.value='native-gas-v1';policy.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>catalogs.length===2);const mode=document.querySelector('#risk-workspace-trade-mode');mode.value='selected';mode.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>document.querySelector('#risk-workspace-pricing-help').textContent.includes('whole books'));risk.sync();})()");
 const before=await evaluate('catalogs.length');
 assert.equal(await evaluate('catalogs.length'),before,'an incompatible policy cannot read a widened catalog');
 assert.equal(await evaluate("document.querySelector('#risk-workspace-trade-mode').value"),'selected');
 assert.equal(await evaluate("document.querySelector('#risk-jobs-new').disabled"),true);
 assert.match(await evaluate("document.querySelector('#risk-workspace-pricing-help').textContent"),/whole books/i);
 await evaluate("(async()=>{const trades=document.querySelector('#risk-workspace-trades');trades.options[0].selected=true;trades.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>calls.filter(call=>call.path==='portfolio/risk/setup').length===3);await new Promise(resolve=>setTimeout(resolve,20));const policy=document.querySelector('#risk-workspace-pricing-policy');policy.value='base';policy.dispatchEvent(new Event('change',{bubbles:true}));await until(()=>catalogs.length===3);})()");
 assert.deepEqual(await evaluate('catalogs.at(-1).tradeIds'),['trade']);
 assert.deepEqual(await evaluate('catalogs.at(-1).pricingPolicy'),await evaluate('basePolicy'));
}));
