import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
test('presentation reconciliation retains existing headings and equal nodes without duplicating reordered children',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage('<div id="host">\n<h3>Heading</h3>\n</div>',async evaluate=>{
 const result=await evaluate(`(async()=>{const {replaceChangedChildren}=await import('/view-updates.js');const host=document.querySelector('#host'),heading=host.querySelector('h3'),value=document.createElement('p');value.textContent='123';replaceChangedChildren(host,[heading,value]);const retained=host.querySelector('p'),next=document.createElement('p');next.textContent='123';replaceChangedChildren(host,[heading,next]);return {heading:host.firstChild===heading,children:host.children.length,value:host.lastChild===retained,text:host.textContent};})()`);
 assert.deepEqual(result,{heading:true,children:2,value:true,text:'Heading123'});
}));
