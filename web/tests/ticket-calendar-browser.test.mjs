import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,withBrowserPage,browserTestTimeout} from './browser-page.mjs';

test('ticket calendars require explicit selection and standard payment dates ignore the display zone',{skip:!browserAvailable,timeout:browserTestTimeout},async()=>{
 await withBrowserPage('<div id="host"></div>',async evaluate=>{
  await evaluate(`(async()=>{
   const {renderTicket}=await import('/deal-ticket.js'),{newTicket}=await import('/ticket-model.js');
   const reference={revision:{catalogId:'synthetic-catalog',revisionId:'synthetic-version'},code:'synthetic-calendar'};
   const payment={id:'payment',label:'Payment date',meaning:'Contractual payment day',type:'payment_date',unit:null,state:'editable',required:true,band:'payment',choices:null,dependsOn:[],lookup:null,soon:null,rule:null};
   const kind=code=>({kind:code,pill:code,colour:'cash',min:1,initial:1,max:1,fields:[{...payment,id:code+'_payment'}],columns:[],soon:null,calendarPurposes:{delivery:true,observation:false,payment:true}});
   const description={product:'synthetic',version:1,rowShape:'flow',tradeFields:[],sides:[kind('cash'),kind('fee')],sideLimits:[],tradeColumns:[],levels:['month'],tabs:[],modes:['new'],sideCalendars:[{reference,code:reference.code,coverageFrom:'2020-01-01',coverageTo:'2030-01-01',weekendMask:48,exceptions:[{date:'2027-01-02',open:true}]}]};
   const state=newTicket(description);state.sides[0].values.cash_payment={value:'2027-02-01T23:59:00.123456Z'};
   const on=new Proxy({calendar:(side,policy)=>{window.selected={side,policy};},edit:(side,field,value)=>{window.edited={side,field,value};}},{get:(target,key)=>target[key]??(()=>{})});
   window.draw=zone=>{window.ticket?.destroy();window.ticket=renderTicket(document.querySelector('#host'),{state,mode:'new',actions:null,schedule:null,quantityUnit:null,instant:at=>'EVENT '+at,zone,previous:null,summaries:[],links:[],entry:null,status:{kind:'current',text:'Not previewed'},fieldErrors:{},choices:{},selectedSide:null,tab:'instrument',level:'month',closed:new Set(),on});};
   draw('America/Los_Angeles');
  })()`);
  assert.deepEqual(await evaluate("[...document.querySelectorAll('[data-side-calendar]')].filter(n=>!n.closest('[data-calendar-purpose]').hidden).map(n=>n.value)"),['','','','']);
  assert.equal(await evaluate("document.querySelector('[data-field=\"cash_payment\"] input').type"),'date');
  assert.equal(await evaluate("document.querySelector('[data-field=\"cash_payment\"] input').value"),'2027-02-01');
  await evaluate("draw('Pacific/Auckland')");
  assert.equal(await evaluate("document.querySelector('[data-field=\"cash_payment\"] input').value"),'2027-02-01');
  await evaluate("{const select=document.querySelector('#ticket-calendar-cash-1-shared');select.value=select.options[1].value;select.parentElement.querySelector('button').click();}");
  const selected=await evaluate('window.selected');
  assert.equal(selected.side,'cash-1');
  assert.deepEqual(selected.policy.delivery.calendar,selected.policy.payment.calendar);
  assert.deepEqual(selected.policy.observation,{applicable:false,calendar:null});
  assert.equal(await evaluate("document.querySelector('#ticket-calendar-fee-1-payment').value"),'');
  assert.match(await evaluate("document.querySelector('#ticket-calendar-cash-1-payment').closest('[data-calendar-purpose]').textContent"),/Friday, Saturday/);
  assert.match(await evaluate("document.querySelector('#ticket-calendar-cash-1-payment').closest('[data-calendar-purpose]').textContent"),/2027-01-02: open/);
  await evaluate("{const input=document.querySelector('[data-field=\"cash_payment\"] input');input.dispatchEvent(new Event('change'));}");
  assert.equal((await evaluate('window.edited')).value,'2027-02-01T23:59:00.123456Z');
  await evaluate("{const input=document.querySelector('[data-field=\"cash_payment\"] input');input.value='2027-02-02';input.dispatchEvent(new Event('change'));}");
  assert.equal((await evaluate('window.edited')).value,'2027-02-02T00:00:00Z');
 });
});

test('product calendar locks survive the shared page busy reset',{skip:!browserAvailable,timeout:browserTestTimeout},async()=>{
 await withBrowserPage('<div id="host"></div>',async evaluate=>{
  await evaluate(`(async()=>{
   const {sideCalendar,calendarKey}=await import('/side-calendar.js');
   const reference={revision:{catalogId:'synthetic-catalog',revisionId:'synthetic-version'},code:'synthetic-calendar'};
   const calendar=sideCalendar({id:'locked',choices:()=>[{reference,value:calendarKey(reference),label:'Synthetic',coverageFrom:'2020-01-01',coverageTo:'2030-01-01',weekendMask:96,exceptions:[]}],purposes:()=>({delivery:true,observation:false,payment:true}),locked:()=>({delivery:reference}),changed:()=>{}});
   document.querySelector('#host').append(calendar.element);calendar.sync();
   for(const control of document.querySelectorAll('button,input,select,textarea'))if(!control.closest('[data-own-controls]'))control.disabled=false;
  })()`);
  assert.equal(await evaluate("document.querySelector('#locked-delivery').disabled"),true);
  assert.equal(await evaluate("document.querySelector('#locked-payment').disabled"),false);
 });
});
