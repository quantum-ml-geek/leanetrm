import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

test('a late option outcome settles only its submitting actor and cannot clear another actor request',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 const result=await evaluate(`(async()=>{
  const {readOptionView}=await import('/futures-option-view.js');let actor='synthetic-a';const replies={},callbacks=[];
  const api=async(path,body)=>path==='options/holding'?{tradeId:'synthetic-trade',lots:'2',openLots:'2',events:[]}:new Promise(resolve=>replies[actor]=resolve);
  const allowed={allowed:true,reason:null},denied={allowed:false,reason:'Synthetic rule'},h={tradeId:'synthetic-trade',component:'option',tradeReference:'T-1',instrumentReference:'I-1',book:'Synthetic book',revision:'1',executedAt:'2026-11-04T00:00:00Z',booking:{tradeDate:'2026-11-04'},currency:'USD',closableLots:'2',actions:{exercise:allowed,assignment:denied,instruction:denied}};
  const mount=async()=>{const owner=actor,read=await readOptionView(api,{snapshotId:'synthetic-close'},h,{writes:()=>({enabled:true,reason:null}),actor:()=>actor,recorded:()=>callbacks.push(owner),surface:null});return read.view('UTC').termsContent(document.querySelector('#host'));};
  const tick=()=>new Promise(resolve=>setTimeout(resolve,0)),send=()=>{document.querySelector('#option-exercise-lots').value='1';document.querySelector('#option-exercise').click();};
  const disposeA=await mount();send();await tick();disposeA();actor='synthetic-b';const disposeB=await mount();send();await tick();
  const key='option-lifecycle-request:synthetic-b:synthetic-trade',before=sessionStorage.getItem(key);
  replies['synthetic-a']({kind:'exercise',lots:'1',remainingLots:'1',futuresTradeId:null});await tick();const after=sessionStorage.getItem(key);disposeB();await mount();
  const restored=document.querySelector('#option-exercise').disabled&&!document.querySelector('#option-lifecycle-retry').hidden,observed=[...callbacks];
  replies['synthetic-b']({kind:'exercise',lots:'1',remainingLots:'1',futuresTradeId:null});await tick();return {retained:before!==null&&before===after,restored,callbacks:observed};
 })()`);
 assert.deepEqual(result,{retained:true,restored:true,callbacks:[]});
}));
