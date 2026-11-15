import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

test('VaR setup has local loading, cancels on reset, and fences a previous account failure',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(
 '<button id="navigation">Another page</button><button id="risk-history-open">Prepare</button><details id="risk-history-panel"><summary>VaR</summary><div id="risk-history-body"></div></details>',async evaluate=>{
 await evaluate(`(async()=>{
  window.owner='synthetic-reader-a';window.actions=0;window.pending=[];
  window.view=(await import('/factor-history-view.js')).setupFactorHistory({
   api:(path,body,signal)=>new Promise((resolve,reject)=>pending.push({path,body,signal,resolve,reject})),
   act:async work=>{actions++;try{await work();}catch{}},busy:()=>false,identity:()=>owner,
   scope:()=>({context:{contextId:'synthetic-context',snapshotId:'synthetic-snapshot'},bookIds:['synthetic-book'],portfolioIds:[],tradeIds:null}),
   instant:value=>value,unconfirmed:()=>false,calculate:async()=>{}});
  view.sync(true);view.prepare();await new Promise(resolve=>setTimeout(resolve,25));
 })()`);
 assert.equal(await evaluate('actions'),0,'opening VaR setup must not enter the application-wide busy action');
 assert.equal(await evaluate('pending.length'),1);
 assert.equal(await evaluate("pending[0].path"),'portfolio/risk/catalog','the complete supported statistical capabilities remain authoritative');
 assert.equal(await evaluate("document.querySelector('#navigation').disabled"),false);
 assert.equal(await evaluate("document.querySelector('#risk-parametric-fields').disabled"),true);
 await evaluate('view.prepare();new Promise(resolve=>setTimeout(resolve,25))');
 assert.equal(await evaluate('pending.length'),1,'repeated opening shares the pending setup');
 await evaluate("view.reset();owner='synthetic-reader-b';view.sync(true);view.prepare();new Promise(resolve=>setTimeout(resolve,25))");
 assert.equal(await evaluate('pending[0].signal?.aborted'),true,'reset cancels the old setup transport');
 assert.equal(await evaluate('pending.length'),2);
 await evaluate("pending[0].reject(Object.assign(Error('Old account denied'),{code:'access_denied'}));new Promise(resolve=>setTimeout(resolve,25))");
 assert.match(await evaluate("document.querySelector('#risk-parametric-form [role=status]').textContent"),/Reading/,'late denial must not replace the current pending setup');
 await evaluate("pending[1].reject(Error('Synthetic current outage'));new Promise(resolve=>setTimeout(resolve,25))");
 assert.match(await evaluate("document.querySelector('#risk-parametric-form [role=status]').textContent"),/Synthetic current outage/);
 assert.equal(await evaluate("document.querySelector('#risk-history-open').disabled"),false,'a failed setup can be retried explicitly');
 await evaluate('view.reset()');
 }));

test('Run VaR prepares coverage locally and reset cancels its read without a stale error',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(
 '<button id="navigation">Another page</button><button id="risk-history-open">Prepare</button><details id="risk-history-panel"><summary>VaR</summary><div id="risk-history-body"></div></details>',async evaluate=>{
 await evaluate(`(async()=>{
  window.actions=0;window.pending=[];
  const scope={context:{contextId:'synthetic-context',snapshotId:'synthetic-snapshot',convention:'synthetic',knowledgeMode:'retained'},bookIds:['synthetic-book'],portfolioIds:[],tradeIds:null};
  const config={context:scope.context,pricingPolicy:{},convention:'synthetic',numericalPolicy:'synthetic',
   parametric:{profile:{convention:'synthetic-parametric'},drifts:{zero:'zero',sample:'sample'},defaults:{drift:'zero',confidence:'0.99',tradingTicks:1,deltaTolerance:{absolute:'0',relative:'0'}},finiteDifference:'synthetic'},
   historical:{profile:{convention:'synthetic-historical'},defaults:{compareParametric:false,comparisonDrift:'zero'}},
   history:{guided:{profile:{convention:'synthetic'},lookback:'three_months',minimumSamples:2,closeTime:'end_of_day',priceTypes:['official_close_v1']},priceTypes:[],clockPolicy:{ambiguousTime:'reject',invalidTime:'reject'},
    calendars:[{reference:{code:'synthetic'},label:'Synthetic calendar',clockRule:{fixedOffsetSeconds:0},windows:[{code:'three_months',from:'2026-01-01',to:'2026-02-01',covered:true}]}]}};
  window.view=(await import('/factor-history-view.js')).setupFactorHistory({api:(path,body,signal)=>path==='portfolio/risk/catalog'?Promise.resolve(config):new Promise((resolve,reject)=>pending.push({path,body,signal,resolve,reject})),
   act:async work=>{actions++;try{await work();}catch{}},busy:()=>false,identity:()=> 'synthetic-reader',scope:()=>scope,instant:v=>v,unconfirmed:()=>false,calculate:async()=>{}});
  view.sync(true);view.prepare();await new Promise(resolve=>setTimeout(resolve,25));document.querySelector('#risk-parametric-run').click();await new Promise(resolve=>setTimeout(resolve,25));
 })()`);
 assert.equal(await evaluate('actions'),0,'a read-only VaR calculation must not acquire the global busy action');
 assert.equal(await evaluate('pending[0].path'),'portfolio/risk/history');
 assert.equal(await evaluate("document.querySelector('#risk-parametric-fields').disabled"),true,'only this calculation form waits');
 assert.equal(await evaluate("document.querySelector('#navigation').disabled"),false);
 await evaluate("view.reset();pending[0].reject(Error('Old coverage failure'));new Promise(resolve=>setTimeout(resolve,25))");
 assert.equal(await evaluate('pending[0].signal.aborted'),true);
 assert.doesNotMatch(await evaluate("document.querySelector('#risk-parametric-form [role=status]').textContent"),/Old coverage/);
 }));
