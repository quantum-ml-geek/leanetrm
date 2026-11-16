import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';

const source=await readFile(new URL('../src/futures-view.ts',import.meta.url),'utf8');
const actual=source.match(/  function riskChanged\(\)\{[^]*?\n  \}/)?.[0];
assert.ok(actual,'The Blotter Risk completion handler must be present.');
const script=(await transform(actual,{loader:'ts',target:'es2022'})).code;
function harness(){
 let resolve,reject,cleared=0,shown=0;
 const page={hidden:false},pending=new Promise((yes,no)=>{resolve=yes;reject=no;});
 const context={generation:1,scope:'synthetic-original-context',preparing:undefined,inline:undefined,lensFor:undefined,lens:'values',
  risk:{current:()=>({key:1})},resultsKey:()=> 'synthetic-result',inlineResults:()=>pending,
  whereAmI:()=>context.scope,get:()=>page,renderRisk(){},showInline(){shown++;},clear(){cleared++;}};
 vm.createContext(context);vm.runInContext(script,context);context.riskChanged();
 return {context,page,resolve,reject,cleared:()=>cleared,shown:()=>shown};
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));

test('an obsolete Risk display refusal cannot clear a newer or temporarily unloaded market selection',async()=>{
 for(const selection of ['synthetic-new-context',undefined]){
  const h=harness();h.context.scope=selection;
  h.reject(Object.assign(Error('Synthetic old display denied'),{code:'access_denied'}));await flush();
  assert.equal(h.cleared(),0,'authority denial from an obsolete display must not reset another selection');
 }
});
test('an obsolete Risk display success cannot install values in a newer selection',async()=>{
 const h=harness();h.context.scope='synthetic-new-context';h.resolve({state:'shown',run:1});await flush();
 assert.equal(h.shown(),0);assert.equal(h.context.inline,undefined);
});
test('Risk display completion remains fenced when the page is hidden or its read generation changes',async()=>{
 for(const change of [h=>h.page.hidden=true,h=>h.context.generation++]){
  const h=harness();change(h);h.reject(Object.assign(Error('Synthetic former display denied'),{code:'access_denied'}));await flush();
  assert.equal(h.cleared(),0);
 }
});
test('current Risk display authority denial still clears its own values',async()=>{
 const h=harness();h.reject(Object.assign(Error('Synthetic current display denied'),{code:'access_denied'}));await flush();
 assert.equal(h.cleared(),1);
});
test('current Risk display success still installs its results and selects the Risk lens',async()=>{
 const h=harness();h.resolve({state:'shown',run:1});await flush();
 assert.equal(h.shown(),1);assert.equal(h.context.lens,'risk');assert.equal(h.context.inline.state,'shown');
});
