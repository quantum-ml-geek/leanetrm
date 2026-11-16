import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';
const source=await readFile(new URL('../src/app.ts',import.meta.url),'utf8');
const method=source.match(/function pageContext\(\):PageContext\{[^]*?\n\}/)[0];
const script=(await transform(method,{loader:'ts',target:'es2022'})).code;
test('REC identity context has no invented inventory date or financial snapshot before inventory is loaded',()=>{
 let date=null,retained=null;
 const context={page:'rec-inventory',contextDirty:false,select:()=>({value:'another-header-close'}),navigation:undefined,instant:value=>value,
  historicalContext:()=>retained,recInventory:{businessDate:()=>date}};
 vm.createContext(context);vm.runInContext(script,context);
 const shown=()=>JSON.parse(JSON.stringify(context.pageContext()));
 assert.deepEqual(shown(),{mode:'current',frameId:null,frameLabel:null});
 date='2026-11-14';assert.deepEqual(shown(),{mode:'current',businessDate:date,frameId:null,frameLabel:null});
 retained={contextId:'exact-history',effectiveOn:'2026-11-13',knownAt:'2026-11-14T00:00:00Z'};
 assert.deepEqual(shown(),{mode:'retained',contextId:retained.contextId,effectiveOn:retained.effectiveOn,knownAtLabel:retained.knownAt,frameId:null,frameLabel:null});
 context.contextDirty=true;assert.deepEqual(shown(),{mode:'unapplied'});
});
