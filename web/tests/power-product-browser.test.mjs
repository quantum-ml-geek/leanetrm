import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
const page=readFileSync(new URL('../src/index.html',import.meta.url),'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'');
const calendar={revision:{catalogId:'synthetic-catalog',revisionId:'synthetic-version'},code:'six_day_calendar'};
const mask='1'.repeat(168);
const catalog={products:[{code:'synthetic',name:'Synthetic hours',version:7,clock:'product_clock',calendar}],unavailableProducts:[],
 blocks:[{code:'all',name:'All hours'}],intervals:[60],hourLabels:[{code:'HE',name:'Hour ending'}],
 presets:[{product:'synthetic',block:'all',minutes:60,nonHolidays:mask,holidays:mask,columns:Array.from({length:24},(_,i)=>({he:'HE'+(i+1),hb:'HB'+i}))}],
 curves:[{code:'power',commodityCode:'power',contracts:[{id:'period',from:'2027-01-01',to:'2027-02-01',holidayCalendar:'source_publication_calendar'}]}],
 weekdays:['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'],quantityChoices:[],display:{quantity:3,price:4,money:3},classifications:{priceTypes:['Test'],timings:['Test']},numericalPolicy:'synthetic'};
test('published power hours are read-only and name their own calendar separately from source publication dates',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(page,async evaluate=>{
 const result=await evaluate(`(async()=>{const {setupPowerView}=await import('/power-view.js');const widget=setupPowerView({zone:()=> 'UTC',api:async()=>(${JSON.stringify(catalog)}),act:async f=>f(),source:()=>({snapshotId:'snapshot',curve:'power',name:'Synthetic context'}),name:c=>c});await widget.load();
  for(const [id,value] of [['power-product','synthetic'],['power-block','all'],['power-minutes','60'],['power-contract','period']]){const el=document.getElementById(id);el.value=value;el.dispatchEvent(new Event('change'));}
  document.querySelectorAll('button,input,select,textarea').forEach(n=>{if(!n.closest('[data-own-controls]'))n.disabled=false;});
  const cells=[...document.querySelectorAll('.tou-cell')],before=cells.map(c=>c.getAttribute('aria-pressed')).join('');cells[0].click();
  return {count:cells.length,locked:cells.every(c=>c.disabled||c.getAttribute('aria-readonly')==='true'),unchanged:before===[...document.querySelectorAll('.tou-cell')].map(c=>c.getAttribute('aria-pressed')).join(''),calendar:document.getElementById('power-holiday-calendar').textContent};
 })()`);
 assert.equal(result.count,336);assert.equal(result.locked,true);assert.equal(result.unchanged,true);
 assert.match(result.calendar,/Six day calendar/i);assert.match(result.calendar,/published product/i);assert.match(result.calendar,/Source publication calendar/i);
}));
