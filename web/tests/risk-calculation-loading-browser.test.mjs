import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
const markup=(await readFile(new URL('../src/index.html',import.meta.url),'utf8')).replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,'');

test('a read-only risk calculation owns a cancellable request and reset fences its late failure',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(markup,async evaluate=>{
 await evaluate(`(async()=>{
  window.pending=[];window.failures=[];
  const scope={context:{snapshotId:'synthetic-snapshot',contextId:'synthetic-context'},bookIds:['synthetic-book'],portfolioIds:[],tradeIds:null};
  window.risk=(await import('/risk-view.js')).setupRisk({api:(path,body,signal)=>new Promise((resolve,reject)=>pending.push({path,body,signal,resolve,reject})),act:async work=>work(),busy:()=>false,zone:()=> 'UTC',profile:()=> 'synthetic-reader',canRun:()=>true,scope:()=>scope,onDenied(){failures.push('denied');},onChange(){}});
  window.loading=risk.calculate({...scope,parametric:{},bumps:[],stress:[]},false,{contextId:'synthetic-context'},'2026-01-01T00:00:00Z').catch(error=>failures.push(error.message));
  await new Promise(resolve=>setTimeout(resolve,25));
 })()`);
 assert.equal(await evaluate('pending[0].path'),'portfolio/risk');
 assert.equal(await evaluate('pending[0].signal instanceof AbortSignal'),true,'the calculation must be cancelled when its scope is reset');
 assert.equal(await evaluate("document.querySelector('#risk-report').getAttribute('aria-busy')"),'true');
 await evaluate("risk.reset();pending[0].reject(Object.assign(Error('Old calculation refused'),{code:'access_denied'}));loading");
 assert.equal(await evaluate('pending[0].signal.aborted'),true);
 assert.deepEqual(await evaluate('failures'),[]);
 assert.equal(await evaluate("document.querySelector('#risk-progress').textContent"),'');
 await evaluate("window.retry=risk.calculate(pending[0].body,false,{contextId:'synthetic-context'},'2026-01-01T00:00:00Z').catch(error=>failures.push(error.message));new Promise(resolve=>setTimeout(resolve,25))");
 await evaluate("pending[1].reject(Error('Current calculation unavailable'));retry");
 assert.deepEqual(await evaluate('failures'),['Current calculation unavailable']);
 assert.equal(await evaluate("document.querySelector('#risk-report').getAttribute('aria-busy')"),'false','a refused calculation releases its local pending state');
}));
