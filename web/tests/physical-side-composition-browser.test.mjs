import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

const browser={skip:!browserAvailable,timeout:browserTestTimeout};
const fixture=`(async()=>{
 window.holding={tradeId:'synthetic-trade',bindingId:'synthetic-binding',revision:'1',instrumentType:'physical_gas',tradeReference:'TR000001',instrumentReference:'IN000001',book:'Synthetic book',
  measureLabel:'Contractual value',discounting:'',unavailableReason:'A required market observation is missing.',executedAt:'2032-03-14T08:00:00Z',trader:'Synthetic trader',booking:{tradeDate:'2032-03-14'}};
 window.groups=[{instrumentId:'retained-definition',bindingId:'synthetic-binding',label:'Retained contract composition',sides:[
  {slot:0,sideId:'physical-side',label:'Physical delivery',roleLabel:'Contractual physical obligation',directionLabel:'Company receives',overviewSections:[{label:'Delivery terms',values:[{label:'Quantity',value:'720 native units'},{label:'Through',value:'2032-03-15T08:00:00Z',kind:'instant'}]}]},
  {slot:1,sideId:'cash-side',label:'Fixed consideration',roleLabel:'Cash consideration',directionLabel:'Company pays',overviewSections:[{label:'Cash terms',values:[{label:'Amount basis',value:'Exact retained contract'},{label:'Evidence',value:'2032-03-15T08:00:00Z'}]}]}]}];
 const at='2032-03-14T08:00:00Z',through='2032-03-15T08:00:00Z';
 window.base={head:{revision:1,instrument_id:'synthetic-binding',payment_at:at,request:{deliveryFrom:at,deliveryTo:through,loadFrom:at,loadTo:through,dischargeFrom:at,dischargeTo:through,paymentAt:at,handlingFee:null,incoterms:{}}},
  physical:{standard_temperature:'60',temperature_scale:'fahrenheit'},profileName:'Synthetic profile',components:[],amend:{allowed:false,reason:'Retained terms only.'},sideGroups:groups};
 window.paths=[];
 window.open=async(type,reply=base,denied=false)=>{
  holding.instrumentType=type;const api=async(path)=>{paths.push(path);if(denied)throw Error('Source authority refused.');return type==='physical_gas'?{...reply,physical:[]}:reply;};
  const read=type==='physical_gas'?(await import('/gas-trade-view.js')).readGasView:type==='physical_crude'?(await import('/crude-trade-view.js')).readCrudeView:(await import('/lng-trade-view.js')).readLngView;
  return read(api,{},holding,{actor:()=> 'synthetic-actor',onDenied:()=>{}});
 };
})()`;

for(const type of ['physical_gas','physical_crude','physical_lng'])
 test(type+' saved contract shows genuine Sides despite unavailable value without a pricing or schedule read',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
  await evaluate(fixture);
  await evaluate(`(async()=>{window.read=await open('${type}');window.view=read.view('America/Chicago');})()`);
  assert.equal(await evaluate("typeof view.termsContent"),'function','retained composition must be exposed by the ordinary saved-terms path');
  await evaluate("view.termsContent(document.querySelector('#host'))");
  assert.equal(await evaluate("document.querySelectorAll('[data-instrument-side-slot]').length"),2);
  const text=await evaluate("document.querySelector('#host').textContent");
  assert.match(text,/Physical delivery/);assert.match(text,/Fixed consideration/);assert.match(text,/Company receives/);assert.match(text,/Company pays/);
  assert.match(text,/CDT|CST/);assert.match(text,/2032-03-15T08:00:00Z/,'plain evidence is not interpreted as a timestamp');
  assert.equal(await evaluate("holding.unavailableReason"),'A required market observation is missing.');
  assert.deepEqual(await evaluate('paths'),['trading/'+type.slice('physical_'.length)]);
  assert.equal(await evaluate("document.querySelectorAll('button').length"),0,'a Side identity does not enable an unqualified action');
 }));

test('missing or foreign physical composition and denied source reads refuse without a fallback request',browser,()=>withBrowserPage('<div id="host"></div>',async evaluate=>{
 await evaluate(fixture);
 for(const type of ['physical_gas','physical_crude','physical_lng']){
  for(const mutation of ['delete reply.sideGroups',"reply.sideGroups[0].bindingId='another-native-binding'"]){
   assert.equal(await evaluate(`(async()=>{const reply=structuredClone(base);${mutation};try{await open('${type}',reply);return false;}catch{return true;}})()`),true);
  }
 }
 const before=await evaluate('paths.length');
 assert.equal(await evaluate("(async()=>{try{await open('physical_gas',base,true);return false;}catch(error){return error.message==='Source authority refused.';}})()"),true);
 assert.equal(await evaluate('paths.length'),before+1,'denied source cannot trigger another product or pricing read');
 assert.equal(await evaluate("document.querySelector('#host').children.length"),0);
}));
