import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';
import {createAsyncReadClient} from '../dist/async-read-client.js';

// Execute the actual account-refresh entry points while access is pending. The
// isolated view stubs have no account or database; SSE uses the real dispatcher.
const source=await readFile(new URL('../src/app.ts',import.meta.url),'utf8');
const functions=['cancelCurveRead','openProfile','loadIdentity'].map(name=>{
 const match=source.match(new RegExp(`(?:async )?function ${name}\\([^\\n]*?\\{[^]*?\\n\\}`));
 if(name==='cancelCurveRead')return source.match(/function cancelCurveRead\(\)\{[^\n]+\}/)[0];
 assert.ok(match,`Missing account entry point ${name}`);return match[0];
});
const script=(await transform(functions.join('\n'),{loader:'ts',target:'es2022'})).code;
const flush=()=>new Promise(resolve=>setImmediate(resolve));
class Source extends EventTarget{
 closed=false;
 close(){this.closed=true;}
 emit(type,value){this.dispatchEvent(new MessageEvent(type,{data:JSON.stringify(value)}));}
}

test('permission refresh retires pending reads before temporarily clearing account context',async()=>{
 const nodes=new Map(),node=id=>{if(!nodes.has(id))nodes.set(id,{dataset:{},replaceChildren(){},closest(){return this;}});return nodes.get(id);};
 const noop=()=>{},curveController=new AbortController(),pageController=new AbortController();
 let parkLoanResets=0;
 const context={currentProfile:'synthetic-reader',navigation:{context:{contextId:'synthetic-retained-context',knownThrough:4}},
  permissions:['ReadMarketData'],marketGeneration:0,curveRead:curveController,pageRead:{controller:pageController},
  $:node,select:node,choose:noop,clearPrices:noop,clearReference:noop,setCurveNames:noop,renderBlotterViews:noop,scheduleWorkspace:undefined,
  parkLoan:{reset(){parkLoanResets++;}}};
 for(const name of ['closeConventionDefaults','lifecycle','physicalOperations','deliverySetup','referenceConsole','curveWorkspace','customCurves',
  'volSurfaces','optionChains','riskJobs','riskViewsNav','facilities','jobs','dashboard','deliveryPrices','intervalSeries','intervalCurves','ppa','gas','crude',
  'lng','gasSetup','crudeSetup','referenceEditor','parties','unitConverter','futures','power','touProducts','schedules','dateEditor','priceSetup',
  'curveDefinitions','administration','aiSettings','agentGrants','referenceNavigation','marketCalendar','accessPolicy','assistantPolicy'])
  context[name]={reset:noop,invalidate:noop,clear:noop};
 let stream,submitted,accessReads=0,denyAccess;
 const heldAccess=new Promise((resolve,reject)=>{denyAccess=reject;});
 context.api=async path=>{assert.equal(path,'access');return ++accessReads===1?{permissions:['ReadMarketData','ReadTrading']}:heldAccess;};
 const protocol='async_reads_v1',channelId='10000000-0000-4000-8000-000000000001';
 context.readClient=createAsyncReadClient({getIdentity:()=>({profile:context.currentProfile,context:context.navigation?.context??null}),
  post:async(path,body)=>{
   if(path.endsWith('/channels'))return {protocol,channelId,profile:context.currentProfile,context:context.navigation.context};
   if(path.endsWith('/cancel'))return {...body,state:'cancellation_requested'};
   submitted=body;return {channelId,requestId:body.requestId,state:'accepted'};
  },createEventSource:()=>stream=new Source()});
 vm.createContext(context);vm.runInContext(script,context);
 const pending=context.readClient.read('curve.shapes.v1',{snapshotId:'20000000-0000-4000-8000-000000000001'}).then(()=> 'installed',error=>error.code);
 let refreshing;
 try{
  await flush();stream.emit('ready',{protocol,channelId});await flush();assert.ok(submitted);
  refreshing=context.openProfile().catch(error=>error.message);await flush();
  assert.equal(accessReads,2,'a changed permission list must enter identity refresh and await fresh access');
  assert.equal(parkLoanResets,1,'the Park and loan ticket must release the previous account draft');
  assert.equal(context.navigation,undefined,'the new account metadata is still loading');
  stream.emit('response',{protocol,channelId,requestId:submitted.requestId,operation:submitted.operation,state:'completed',snapshotId:submitted.body.snapshotId,result:{curves:[]}});
  assert.equal(await pending,'async_read_reset','an intentional refresh must not appear to be an unexpected authority change');
  assert.equal(stream.closed,true);assert.equal(curveController.signal.aborted,true);assert.equal(pageController.signal.aborted,true);
  assert.equal(context.pageRead,undefined,'the superseded page cannot publish a late error');
 }finally{
  context.readClient.close();denyAccess(Error('Synthetic access read ended'));await refreshing;
 }
});
