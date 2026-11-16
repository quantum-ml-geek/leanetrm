import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';

const source=await readFile(new URL('../src/app.ts',import.meta.url),'utf8');
async function entry(name,context){
 const body=source.match(new RegExp(`(?:async )?function ${name}\\([^\\n]*?\\{[^]*?\\n\\}`))?.[0];
 assert.ok(body,`Missing ordinary market entry point ${name}`);
 vm.createContext(context);vm.runInContext((await transform(body,{loader:'ts',target:'es2022'})).code,context);return context[name];
}
const copy=value=>JSON.parse(JSON.stringify(value));
const selectedSource={definitionRevisionId:'synthetic-independent-definition',referenceCatalogId:'synthetic-r2',referenceRevisionId:'synthetic-r2-version'};

test('ordinary point entry uses the selected listed source without a successful evaluation or an observation',async()=>{
 const context={navigation:{curves:[{code:'synthetic-point',name:'Synthetic independent marks',source:selectedSource}],frames:[]},
  curve:'synthetic-point',administrationScope:'synthetic-workspace',exampleId:'synthetic-example',currentProfile:'market-editor',
  select:()=>({value:''}),historicalContext:()=>undefined,contextDirty:false,closeSession:null};
 const selection=await entry('pointValueSelection',context),empty=copy(selection());
 assert.deepEqual(empty.source,selectedSource);assert.equal(empty.curveCode,'synthetic-point');assert.equal(empty.frame,null);
 assert.equal(empty.label,'Synthetic independent marks');
 context.navigation.frames=[{id:'synthetic-working-inputs',name:'Selected working inputs',at:'2032-03-14T08:00:00Z',businessDate:'2032-03-13'}];
 context.select=()=>({value:'synthetic-working-inputs'});const framed=copy(selection());assert.equal(framed.frame.id,'synthetic-working-inputs');assert.notEqual(framed.stamp,empty.stamp);
 context.currentProfile='another-market-reader';assert.notEqual(selection().stamp,framed.stamp);
 context.curve='';assert.equal(selection(),undefined,'no source is chosen on the person’s behalf');
});

test('explicit edited-input application stops when the original header changes during navigation read',async()=>{
 let active=true;const calls=[];
 const context={mayLeave:async move=>{calls.push(['leave',move]);return true;},loadNavigation:async id=>{calls.push(['navigation',id]);active=false;},
  renderFrames:id=>calls.push(['select',id]),closeChanged:()=>calls.push(['changed']),initializeContext:async()=>calls.push(['context']),loadSelectedClose:async()=>calls.push(['load'])};
 const apply=await entry('applyPointInputs',context);await apply({id:'synthetic-edited-inputs'},()=>active);
 assert.deepEqual(calls,[['leave','closes'],['navigation','synthetic-edited-inputs']]);
});

test('explicit edited-input application selects the attested working frame only after navigation and leave admission',async()=>{
 const calls=[];let leave=false;
 const context={mayLeave:async()=>leave,loadNavigation:async id=>calls.push(['navigation',id]),renderFrames:id=>calls.push(['select',id]),
  closeChanged:()=>calls.push(['changed']),initializeContext:async()=>calls.push(['context']),loadSelectedClose:async()=>calls.push(['load'])};
 const apply=await entry('applyPointInputs',context),frame={id:'synthetic-edited-inputs'};
 await apply(frame,()=>true);assert.deepEqual(calls,[]);
 leave=true;await apply(frame,()=>true);assert.deepEqual(calls,[['navigation',frame.id],['select',frame.id],['changed'],['context'],['load']]);
});

test('leaving the ordinary market page asks about an unpublished value before giving up its source',async()=>{
 let leaves=0;const context={page:'market',pointTraderMark:{leave:async()=>{leaves++;return false;}},futures:{windowEdits:()=>false}};
 const leave=await entry('mayLeave',context);assert.equal(await leave('closes'),false);assert.equal(leaves,1);
 assert.equal(await leave('keeps'),true);assert.equal(leaves,1,'display-only changes keep the value edits');
});

test('market filters keep the selected source when a publisher draft is kept, and apply only after leave admission',async()=>{
 let admitted=false;const calls=[];
 const context={busy:false,prefs:{marketType:'all'},mayLeave:async()=>admitted,renderContext:()=>calls.push('restore'),
  act:async work=>{calls.push('action');await work();},updateFilters:async()=>calls.push('filter')};
 const change=await entry('changeMarketFilters',context);await change('forwards');
 assert.equal(context.prefs.marketType,'all');assert.deepEqual(calls,['restore']);
 admitted=true;await change('forwards');assert.equal(context.prefs.marketType,'forwards');assert.deepEqual(calls,['restore','action','filter']);
});

test('sample price navigation uses the same unsaved-source leave gate before clearing the selected curve',async()=>{
 const body=source.match(/^\$\('example'\)\.onclick=[^\n]+/m)?.[0];assert.ok(body);
 const button={},calls=[],context={$:()=>button,act:()=>calls.push('unreviewed action'),leaving:()=>calls.push('leave admission')};
 vm.createContext(context);vm.runInContext((await transform(body,{loader:'ts',target:'es2022'})).code,context);button.onclick();
 assert.deepEqual(calls,['leave admission']);
});

test('page-assistant navigation remains blocked by unpublished values or an uncertain publication',async()=>{
 let edited=true,pending=false;const context={page:'market',pointTraderMark:{unsaved:()=>edited,pending:()=>pending}};
 const unsaved=await entry('unsaved',context);assert.equal(unsaved(),true);
 edited=false;pending=true;assert.equal(unsaved(),true);
 pending=false;assert.equal(unsaved(),false);
});
