import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
const browser={skip:!browserAvailable,timeout:browserTestTimeout};
const fixture=`(async()=>{
 const module=await import('/field-group-layout.js');window.mount=module.mountFieldGroupLayout;
 window.controls=new Map([...document.querySelectorAll('#pricing label')].map(label=>[label.dataset.field,label]));
 window.layout={fields:['currency','sale','fee'],groups:[{id:'common',label:'Valuation agreement terms',kind:'agreement',fields:['currency']},{id:'sale',label:'Energy sale Side terms',kind:'side_terms',fields:['sale']},{id:'fee',label:'Optional fee Side terms',kind:'side_terms',fields:['fee']}]};
})()`;
const page='<label>Book<input id="party" value="Synthetic book"></label><div id="pricing"><label data-field="currency">Currency<input value="USD"></label><label data-field="sale">Sale<input value="-20"></label><label data-field="fee">Fee<input value="0"></label><label data-field="fuel">Fuel<input value="35"></label></div>';
test('backend field partitions move existing Side controls once and preserve explicit values through a selected-kind layout refresh',browser,()=>withBrowserPage(page,async evaluate=>{
 await evaluate(fixture);await evaluate("mount(document.querySelector('#pricing'),layout,controls)");
 assert.deepEqual(await evaluate("[...document.querySelectorAll('[data-field-layout-group]')].map(card=>card.dataset.fieldLayoutGroup)"),['common','sale','fee']);
 assert.equal(await evaluate("document.querySelectorAll('[data-field=sale] input').length"),1);
 assert.equal(await evaluate("document.querySelector('[data-field-layout-group=sale] input').value"),'-20');
 assert.equal(await evaluate("document.querySelector('[data-field-layout-inactive] [data-field=fuel] input').value"),'35');
 await evaluate("mount(document.querySelector('#pricing'),{fields:['currency','fuel'],groups:[layout.groups[0],{id:'fuel',label:'Fuel input Side terms',kind:'side_terms',fields:['fuel']}]},controls)");
 assert.equal(await evaluate("document.querySelector('[data-field-layout-group=fuel] input').value"),'35');
 assert.equal(await evaluate("document.querySelector('[data-field-layout-inactive] [data-field=sale] input').value"),'-20');
 assert.equal(await evaluate("document.querySelector('#party').value"),'Synthetic book');
 assert.equal(await evaluate("document.querySelectorAll('#pricing input').length"),4);
}));
test('missing, foreign or conflicting active field partitions refuse before moving any controls',browser,()=>withBrowserPage(page,async evaluate=>{
 await evaluate(fixture);
 for(const mutation of ['delete candidate.groups',"candidate.fields.push('unknown')",'candidate.groups[1].fields.push(\'fee\')','candidate.fields.pop()',"candidate.groups[1].kind='inferred_side'"]){
  assert.equal(await evaluate(`(()=>{const candidate=structuredClone(layout);${mutation};try{mount(document.querySelector('#pricing'),candidate,controls);return false;}catch{return true;}})()`),true);
  assert.equal(await evaluate("document.querySelectorAll('[data-field-layout-group]').length"),0);
  assert.equal(await evaluate("document.querySelectorAll('#pricing>label').length"),4);
 }
}));
