import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';
const source=await readFile(new URL('../src/app.ts',import.meta.url),'utf8');
const entry=source.match(/async function mayLeave\([^]*?\n\}/)[0];
const script=(await transform(entry,{loader:'ts',target:'es2022'})).code;
for(const page of ['physical-power','rec-inventory'])test(`keeping ${page} preserves every unsaved field and leaving resets it once`,async()=>{
 let going=false,powerResets=0,recResets=0,questions=0;
 const context={page,keptWindowEdits:false,physicalLeaving:undefined,recLeaving:undefined,AbortController,
  futures:{windowEdits:()=>false},structuredPower:{unsaved:()=>true,contextChanged:()=>powerResets++},recInventory:{unsaved:()=>true,reset:()=>recResets++},
  $:()=>({}),askInPanel:()=>async()=>{questions++;return going;}};
 vm.createContext(context);vm.runInContext(script,context);
 assert.equal(await context.mayLeave('page'),false);assert.equal(powerResets,0);assert.equal(recResets,0);
 going=true;assert.equal(await context.mayLeave('page'),true);assert.equal(questions,2);
 assert.equal(powerResets,page==='physical-power'?1:0);assert.equal(recResets,page==='rec-inventory'?1:0);
});
