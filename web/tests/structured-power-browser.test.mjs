import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';
const markup=readFileSync(new URL('../src/index.html',import.meta.url),'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'');
const pins={definitionCatalogId:'dc',definitionRevisionId:'dr',referenceCatalogId:'rc',referenceRevisionId:'rr'};
const catalog={pins,locations:[{code:'existing',label:'Synthetic existing facility'}],clocks:[{code:'utc',label:'UTC'}],kinds:[{code:'battery',label:'Battery storage',intervalMinutes:[60]},{code:'thermal',label:'Thermal tolling',intervalMinutes:[60]},{code:'solar',label:'Solar output right',intervalMinutes:[60]}],powerQuantities:[{code:'mw',label:'Native MW'}],energyQuantities:[{code:'mwh',label:'Native MWh'}],fuelQuantities:[{code:'fuel',label:'Fuel energy'}],rightQuantities:[{code:'right',label:'One complete resource right'}],currencies:[{code:'usd',label:'USD'}],quotes:[{code:'energy',label:'USD per MWh',quantityCode:'mwh',currencyCode:'usd',multiplier:'1'}],paymentImplementation:'monthly_payment_date_rules_v1',canSave:true,canPreview:true};

test('operating controls retain explicit disabled states through global busy updates',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(markup,async evaluate=>{
 const state=await evaluate(`(async()=>{const {setupStructuredPower}=await import('/structured-power-view.js');const host=document.getElementById('physical-power-page');host.hidden=false;let busy=false;const widget=setupStructuredPower(host,{api:async(path)=>path.endsWith('/catalog')?${JSON.stringify(catalog)}:[],act:async work=>work(),busy:()=>busy,source:()=>({snapshotId:'frame',contextKey:'working'}),identity:()=> 'workspace:alpha'});await widget.load();
 const kind=[...host.querySelectorAll('label')].find(n=>n.firstChild.textContent==='Operating kind').querySelector('select');kind.value='battery';kind.dispatchEvent(new Event('change'));widget.sync();
 const planned=()=>[...host.querySelectorAll('input')].filter(n=>n.placeholder==='Coming soon');
 document.querySelectorAll('button,input,select,textarea').forEach(n=>{if(!n.closest('[data-own-controls]'))n.disabled=false;});widget.sync();const preserved=planned().every(n=>n.disabled);
 busy=true;widget.sync();const blocked=host.inert;busy=false;widget.sync();
 return {preserved,blocked,restored:!host.inert,planned:planned().length,masters:document.querySelectorAll('#nav-facilities').length,groups:document.querySelectorAll('#nav-group-scheduling').length};})()`);
 assert.deepEqual(state,{preserved:true,blocked:true,restored:true,planned:3,masters:1,groups:1});
}));

test('facility form preserves exact transport, backend side values and actor-specific uncertain saves',{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(markup,async(evaluate,command)=>{
 await command('Emulation.setDeviceMetricsOverride',{width:1440,height:1080,deviceScaleFactor:1,mobile:false});
 const submitted=await evaluate(`(async()=>{
  const {setupStructuredPower}=await import('/structured-power-view.js');
  const host=document.getElementById('physical-power-page');host.hidden=false;
  const state=window.operatingTest={identity:'alpha',context:'working',stored:[],requests:[],receipts:{},uncertain:false,last:Promise.resolve()};
  const quantity=(numerator,denominator='1')=>({numerator,denominator,specification:{code:'mwh'}}),money=numerator=>({numerator,denominator:'1',currency:{code:'usd'}});
  const interval={start:'2031-01-01T01:00:00Z',end:'2031-01-01T02:00:00Z',operatingDate:'2031-01-01',hourBeginning:1,minute:0,occurrence:1};
  const row=(q,price,amount)=>({interval,paymentAt:'2031-02-18T00:00:00Z',quantity:q,price:{numerator:price,denominator:'1'},amount:money(amount),presentValue:money(amount),state:1,evidenceId:null,knownAt:null});
  const api=async(path,body)=>{state.requests.push({path,body:structuredClone(body)});
   if(path.endsWith('/catalog'))return ${JSON.stringify(catalog)};
   if(path.endsWith('/list'))return state.stored;
   if(path.endsWith('/get'))return state.stored.find(x=>x.id===body.facilityId&&x.version===body.version);
   if(path.endsWith('/save')){const receipt={requestId:body.requestId,changed:true,facility:structuredClone(body.facility)};state.stored.push(receipt.facility);state.receipts[body.requestId]=receipt;if(state.uncertain){state.uncertain=false;throw Object.assign(Error('Unknown transport outcome'),{code:'response_unknown'});}return receipt;}
   if(path.endsWith('/status'))return state.receipts[body.requestId]??null;
   if(path==='amounts/display')return body.map(x=>x.value);
   if(path.endsWith('/preview'))return {previewId:'preview',kind:'battery',clockFingerprint:'captured-clock',knownAt:'2026-11-16T00:00:00Z',intervals:[{interval,quantities:[{name:'grid_discharge',quantity:quantity('81','10')}]}],closingState:{at:interval.end,commitment:null,elapsedMinutes:null,startsUsed:null,quantities:[{name:'stored_energy',quantity:quantity('0')}]},valuation:{currency:{code:'usd'},value:money('610'),sides:[{id:'sell',name:'discharging_energy',coefficient:'1',quote:{code:'energy'},grossValue:money('810'),contribution:money('810'),rows:[row(quantity('81','10'),'100','810')]},{id:'buy',name:'charging_energy',coefficient:'-1',quote:{code:'energy'},grossValue:money('200'),contribution:money('-200'),rows:[row(quantity('10'),'20','200')]}]},limitations:['Hypothetical supplied plan; no booking.']};
   throw Error('Unexpected test operation '+path);
  };
  state.widget=setupStructuredPower(host,{api,act:work=>state.last=work().catch(error=>{state.error=error.message;}),busy:()=>false,source:()=>({snapshotId:'frame',contextKey:state.context}),identity:()=> 'workspace:'+state.identity});
  state.field=title=>[...host.querySelectorAll('label')].find(n=>n.firstChild.textContent===title)?.querySelector('input,select,textarea');
  state.set=(title,value)=>{const control=state.field(title);if(!control)throw Error('Missing control '+title);control.value=value;control.dispatchEvent(new Event(control.tagName==='SELECT'?'change':'input',{bubbles:true}));};
  state.click=async text=>{const button=[...host.querySelectorAll('button')].find(n=>n.textContent===text);if(!button)throw Error('Missing button '+text);button.click();await state.last;};
  await state.widget.load();await state.click('Add operating parameters');
  state.set('Operating kind','battery');
  for(const [title,value] of Object.entries({'Existing facility location':'existing','Operating clock':'utc','Native interval':'60','Power quantity (MW)':'mw','Energy quantity (MWh)':'mwh','Effective from (UTC, ending in Z)':'2031-01-01T00:00:00Z','Effective to (UTC, ending in Z)':'2032-01-01T00:00:00Z'}))state.set(title,value);
  const params={maximumChargeMw:'10.000000000001',maximumDischargeMw:'10',minimumStoredMwh:'0',maximumStoredMwh:'10',chargeEfficiency:'0.9',dischargeEfficiency:'0.9',meterBoundary:'grid_side_ac',lossPolicy:'zero_auxiliary_and_self_discharge',capacityPolicy:'fixed',simultaneousPolicy:'prohibited',chargingOrigin:'grid',throughputPolicy:'uncapped'};
  for(const [key,value] of Object.entries(params)){const control=host.querySelector('[data-field='+key+']');control.value=value;control.dispatchEvent(new Event(control.tagName==='SELECT'?'change':'input',{bubbles:true}));}
  const forms=host.querySelectorAll('form');if(!forms[0].reportValidity())throw Error('The completed physical parameters did not validate.');forms[0].requestSubmit();await state.last;
  for(const [title,value] of Object.entries({'First operating date':'2031-01-01','First native interval (one-based)':'1','Valuation':'fixed','One complete resource-right quantity for valuation':'right','Valuation currency':'usd','Energy sale/payment quote':'energy','Energy sale/payment price':'100','Charging energy quote':'energy','Charging energy purchase price':'20','Perspective':'resource_right_holder_v1','Value measure':'remaining_operating_value_v1','Discounting':'undiscounted','Monthly payment: calendar days after last delivery day':'18','Monthly payment convention':'monthly_calendar_unadjusted'}))state.set(title,value);
  for(const [key,value] of Object.entries({at:'2031-01-01T00:00:00Z',storedMwh:'0',cumulativeGridThroughputMwh:'0',terminalMinimumMwh:'0',terminalMaximumMwh:'0'})){const control=host.querySelector('[data-field='+key+']');control.value=value;control.dispatchEvent(new Event('input',{bubbles:true}));}
  state.set('Supplied interval plan','10,0,1\\n0,8.1,1');if(!forms[1].reportValidity())throw Error('The completed supplied plan did not validate.');forms[1].requestSubmit();await state.last;
  return {error:state.error??null,save:state.requests.find(x=>x.path.endsWith('/save')).body,preview:state.requests.find(x=>x.path.endsWith('/preview')).body,shown:host.textContent.includes('Remaining operating value: 610 usd'),gross:host.textContent.includes('810')&&host.textContent.includes('-200'),overflow:document.documentElement.scrollWidth>innerWidth};
 })()`);
 assert.equal(submitted.error,null);assert.equal(submitted.save.facility.terms.facilityCode,'existing');assert.equal(submitted.save.facility.terms.battery.maximumChargeMw,'10.000000000001');assert.equal(Object.hasOwn(submitted.save.facility.terms,'rightQuantityCode'),false);
 assert.equal(submitted.preview.valuation.rightQuantityCode,'right');assert.equal(submitted.preview.valuation.chargingPrice.fixedPrice,'20');assert.equal(submitted.preview.batteryDispatch[1].dischargeMw,'8.1');assert.equal(submitted.shown,true);assert.equal(submitted.gross,true);assert.equal(submitted.overflow,false);
 if(process.env.STRUCTURED_POWER_SCREENSHOT){const {writeFile}=await import('node:fs/promises');await evaluate("document.getElementById('physical-power-page').scrollIntoView({block:'start'});new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))");const shot=await command('Page.captureScreenshot',{format:'png'});await writeFile(process.env.STRUCTURED_POWER_SCREENSHOT+'-desktop.png',Buffer.from(shot.data,'base64'));}
 await command('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
 const phone=await evaluate(`({width:innerWidth,scroll:document.documentElement.scrollWidth,overflow:[...document.querySelectorAll('#physical-power-page *')].filter(n=>n.getBoundingClientRect().width&&n.getBoundingClientRect().right>innerWidth+1).slice(0,10).map(n=>({tag:n.tagName,cls:n.className,text:n.textContent?.slice(0,45),width:n.getBoundingClientRect().width,right:n.getBoundingClientRect().right}))})`);
 assert.equal(phone.scroll<=phone.width,true,JSON.stringify(phone));
 if(process.env.STRUCTURED_POWER_SCREENSHOT){const {writeFile}=await import('node:fs/promises');await evaluate("document.querySelector('#physical-power-page form').scrollIntoView({block:'start'});new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))");const shot=await command('Page.captureScreenshot',{format:'png'});await writeFile(process.env.STRUCTURED_POWER_SCREENSHOT+'-phone.png',Buffer.from(shot.data,'base64'));}
 const recovery=await evaluate(`(async()=>{const s=operatingTest,host=document.getElementById('physical-power-page');const maximum=host.querySelector('[data-field=maximumChargeMw]');maximum.value='11';maximum.dispatchEvent(new Event('input',{bubbles:true}));s.uncertain=true;host.querySelector('form').requestSubmit();await s.last;const original=s.requests.filter(x=>x.path.endsWith('/save')).at(-1).body.requestId;
  const visible=text=>[...host.querySelectorAll('button')].find(n=>n.textContent===text)?.parentElement.hidden===false;
  s.identity='beta';s.widget.reset();const cleared=[...host.querySelectorAll('input,textarea')].every(n=>n.value==='');await s.widget.load();const isolated=!visible('Retry original save');
  s.identity='alpha';s.widget.reset();await s.widget.load();const restored=visible('Retry original save');await s.click('Check outstanding save');
  const checked=s.requests.filter(x=>x.path.endsWith('/status')).at(-1).body.requestId;
  return {cleared,isolated,restored,same:original===checked,pending:s.widget.unconfirmed(),revision:s.stored.at(-1).version};})()`);
 assert.deepEqual(recovery,{cleared:true,isolated:true,restored:true,same:true,pending:false,revision:2});
}));
