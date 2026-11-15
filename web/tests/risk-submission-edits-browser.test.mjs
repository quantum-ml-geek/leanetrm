import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
const markup=(await readFile(new URL('../src/index.html',import.meta.url),'utf8')).replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,'');

test('submitting a focused shock size consumes its edits even when every read is refused',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(markup,async(evaluate,command)=>{
 await evaluate(`(async()=>{
  const scope={context:{snapshotId:'synthetic-snapshot',contextId:'synthetic-context'},bookIds:[],portfolioIds:[]};
  const target={id:'synthetic-target',label:'Synthetic contract',coordinate:'market_quote',kind:'contract',unit:'USD',priceUnit:{},factor:{coordinate:'market_quote',target:{}}};
  const catalog={context:{contextId:'synthetic-context',effectiveOn:'2026-01-01',knownThrough:1},asOf:'2026-01-01T00:00:00Z',
   limits:{maxHoldingsBumps:16,maxBooksBumps:64,maxStress:4,maxParts:4},scenarioTargets:[target],heldContractTargets:[target.id],heldCurveTargets:[],
   heldContractsWithoutTarget:[],heldCurvesWithoutTarget:[],excludedPositions:[],bumpConvention:'synthetic',stressConvention:'synthetic',convention:'synthetic',numericalPolicy:'synthetic',pricingPolicy:{}};
  window.pending=[];window.failures=[];window.cleared=0;window.actions=0;window.risk=(await import('/risk-view.js')).setupRisk({api:async path=>path==='portfolio/risk/catalog'?catalog:path==='portfolio/risk/jobs'?[]:new Promise((resolve,reject)=>pending.push({resolve,reject})),
   act:async work=>{actions++;await work();},failed:error=>failures.push(error.message),failureCleared:()=>cleared++,busy:()=>false,zone:()=> 'UTC',profile:()=> 'synthetic-reader',canRun:()=>true,scope:()=>scope,onDenied(){},onChange(){}});
  document.querySelector('#risk-report').hidden=false;document.body.append(document.querySelector('#risk-report'));
  await risk.open();document.querySelector('input[name=risk-choice][value=held]').click();
  const size=document.querySelector('#risk-size-0');size.focus();size.select();
 })()`);
 await command('Input.insertText',{text:'0.09'});
 assert.equal(await evaluate('risk.edited()'),true);
 await evaluate("document.querySelector('#risk-form').requestSubmit();pending[0].reject(Error('Synthetic refused read'));new Promise(resolve=>setTimeout(resolve,30))");
 await evaluate("document.querySelector('#risk-size-0').blur()");
 assert.equal(await evaluate('risk.edited()'),false,'a later native change event must not restore edits already submitted');
 assert.deepEqual(await evaluate('failures'),['Synthetic refused read'],'read refusals must still reach the owning page error display');
 assert.equal(await evaluate('cleared'),1,'a new explicit read clears the previous page error');
 assert.equal(await evaluate('actions'),0,'read error reporting must not acquire application-wide busy state');
 await evaluate("document.querySelector('#risk-form').requestSubmit();const parent=document.createElement('section');document.body.append(parent);parent.append(document.querySelector('#risk-report'));parent.hidden=true;pending[1].reject(Error('A refusal from the previous page'));new Promise(resolve=>setTimeout(resolve,30))");
 assert.deepEqual(await evaluate('failures'),['Synthetic refused read'],'a view left while its read settles must not paint its refusal over another page');
}));
