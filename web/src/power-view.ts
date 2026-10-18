import {renderRegularTable} from './regular-table.js';
import {timeLabels} from './market-view.js';

type Contract={id:string;from:string;to:string};
type Preset={product:string;block:string;minutes:number;nonHolidays:string;holidays:string;columns:{he:string;hb:string}[]};
type QuantityChoice={basis:string;label:string;specification:unknown};
type Catalog={products:{code:string;name:string}[];presets:Preset[];curves:{code:string;contracts:Contract[]}[];weekdays:string[];numericalPolicy:string;quantityChoices:QuantityChoice[];display:{quantity:number;price:number;money:number}};
type Preview={summary:{hours:string;energy:string;averagePrice:string;amount:string;policy:{implementation:string}};amounts:{energyText:string;cashText:string;priceText:string};currency:string;mark:string;from:string;to:string;product:string;rows:{label:string;start:string;end:string;offsetMinutes:number;occurrence:number;holiday:boolean;price:string;priceText:string;energy:{numerator:string;denominator:string};energyText:string}[];days:{date:string;hours:string;intervals:number}[]};
type Options={zone:()=>string;api:<T>(path:string,body?:unknown)=>Promise<T>;act:(work:()=>Promise<void>)=>Promise<void>;source:()=>{snapshotId:string;curve:string;name:string};name:(code:string)=>string};
const node=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
function el<K extends keyof HTMLElementTagNameMap>(tag:K,text?:string){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
const choice=(id:string)=>node<HTMLSelectElement>(id);
function options(id:string,values:{value:string;label:string}[],selected?:string){choice(id).replaceChildren(...values.map(v=>{const n=el('option',v.label);n.value=v.value;return n;}));if(selected&&values.some(v=>v.value===selected))choice(id).value=selected;}

// Rendering and draft editing only. Membership, dates, prices, units and all
// arithmetic come from the authorized backend operation.
export function setupPowerView(o:Options){
  let catalog:Catalog|undefined,snapshotId='',nonHolidays='',holidays='';
  let current:Preview|undefined;
  const form=node<HTMLFormElement>('power-form');
  const quantityKey=(q:QuantityChoice)=>JSON.stringify(q.specification);
  const selectedQuantity=()=>catalog?.quantityChoices.find(q=>quantityKey(q)===choice('power-quantity-basis').value);
  function clearResult(){current=undefined;node('power-result').hidden=true;node('power-days').replaceChildren();node('power-intervals').replaceChildren();for(const id of ['power-summary','power-price-note','power-rows-note'])node(id).textContent='';}
  function preset(){if(!catalog)throw Error('Load the power example first.');const p=catalog.presets.find(p=>p.product===choice('power-product').value&&p.block===choice('power-block').value&&String(p.minutes)===choice('power-minutes').value);if(!p)throw Error('Choose a supported product and grid.');return p;}
  function grids(){
    if(!catalog)return;const p=preset(),ending=choice('power-labels').value==='HE';
    for(const [id,title,cells] of [['power-normal-grid','Non-holidays',nonHolidays],['power-holiday-grid','Holidays',holidays]]){
      const table=el('table');table.className='tou-grid';table.setAttribute('aria-label',title);
      const head=el('thead'),tr=el('tr');tr.append(el('th','Day'));p.columns.forEach(c=>tr.append(el('th',ending?c.he:c.hb)));head.append(tr);table.append(head);
      const body=el('tbody');catalog.weekdays.forEach((day,row)=>{
        const line=el('tr');line.append(el('th',day));p.columns.forEach((column,col)=>{
          const index=row*p.columns.length+col,cell=el('td'),button=el('button');button.type='button';
          const selected=cells[index]==='1';button.className='tou-cell'+(selected?' chosen':'');button.textContent=selected?'●':'';
          button.setAttribute('aria-pressed',String(selected));button.setAttribute('aria-label',`${title} ${day} ${ending?column.he:column.hb}`);
          button.onclick=()=>{const value=id==='power-normal-grid'?nonHolidays:holidays;const next=value.slice(0,index)+(value[index]==='1'?'0':'1')+value.slice(index+1);if(id==='power-normal-grid')nonHolidays=next;else holidays=next;clearResult();grids();};
          cell.append(button);line.append(cell);
        });body.append(line);
      });table.append(body);node(id).replaceChildren(table);
    }
  }
  function applyPreset(){const p=preset();nonHolidays=p.nonHolidays;holidays=p.holidays;clearResult();grids();}
  function contracts(){const curve=catalog?.curves.find(c=>c.code===choice('power-curve').value);options('power-contract',curve?.contracts.map(c=>({value:c.id,label:`${c.from} → ${c.to}`}))??[]);clearResult();}
  function render(result:Preview){
    current=result;node('power-result').hidden=false;
    node('power-summary').textContent=`${result.summary.hours} hours · ${result.amounts.energyText} · ${result.amounts.priceText} · amount ${result.amounts.cashText}`;
    node('power-price-note').textContent=`${result.product}. Flat ${result.mark} ${result.currency}/MWh from the selected curve contract. Generated test fixings; no market data saved. The curve's stored product terms are unchanged.`;
    const scope=JSON.stringify([snapshotId,choice('power-curve').value,choice('power-contract').value,choice('power-product').value,choice('power-block').value,nonHolidays,holidays]);
    renderRegularTable(node('power-days'),'power-days',scope,['Operating date','Hours','Intervals'],result.days.map(d=>[d.date,d.hours,String(d.intervals)]),[1,2],()=>document.body.getAttribute('aria-busy')==='true');
    const rows=choice('power-show').value==='all'?result.rows:result.rows.slice(0,60);
    const labels=timeLabels(rows.flatMap(r=>[r.start,r.end]),o.zone());
    const raw=rows.map((r,i)=>[r.label,labels[2*i],labels[2*i+1],String(r.offsetMinutes),String(r.occurrence),r.holiday?'Yes':'No',r.price,`${r.energy.numerator}/${r.energy.denominator}`]);
    renderRegularTable(node('power-intervals'),'power-intervals',scope,['Market interval',`Start · ${o.zone()}`,`End · ${o.zone()}`,'Market clock offset · minutes','Occurrence','Holiday','Test price','Energy · MWh'],raw,[3,4,6,7],()=>document.body.getAttribute('aria-busy')==='true',{displayRows:raw.map((r,i)=>[...r.slice(0,6),rows[i].priceText,rows[i].energyText])});
    node('power-rows-note').textContent=rows.length===result.rows.length?'All selected intervals.':'First 60 intervals. Choose Show all to inspect the complete period.';
  }
  for(const id of ['power-product','power-block','power-minutes'])choice(id).onchange=applyPreset;
  choice('power-labels').onchange=()=>{clearResult();grids();};
  choice('power-curve').onchange=contracts;
  choice('power-contract').onchange=clearResult;
  choice('power-show').onchange=()=>{if(current)render(current);};
  choice('power-quantity-basis').onchange=()=>{clearResult();const total=selectedQuantity()?.basis==='total_energy';node('power-allocation-field').hidden=!total;choice('power-allocation').required=total;choice('power-allocation').value='';node('power-quantity-label').textContent=total?'Total energy · MWh':'Flat power · MW';};
  for(const id of ['power-mw','power-allocation','power-quantity-precision','power-price-precision','power-money-precision','power-price-type','power-timing','power-holiday-dates'])node(id).addEventListener('input',clearResult);
  form.onsubmit=event=>{event.preventDefault();void o.act(async()=>{
    clearResult();
    const quantityChoice=selectedQuantity(),quantityBasis=quantityChoice?.basis;
    if(!quantityChoice)throw Error('Choose an available total-MWh or flat-MW quantity basis.');
    const result=await o.api<Preview>('power/preview',{snapshotId,curve:choice('power-curve').value,contractId:choice('power-contract').value,product:choice('power-product').value,block:choice('power-block').value,minutes:Number(choice('power-minutes').value),hourLabels:choice('power-labels').value,quantity:{value:node<HTMLInputElement>('power-mw').value,specification:quantityChoice.specification},quantityBasis,allocation:quantityBasis==='total_energy'?choice('power-allocation').value:null,display:{quantity:Number(node<HTMLInputElement>('power-quantity-precision').value),price:Number(node<HTMLInputElement>('power-price-precision').value),money:Number(node<HTMLInputElement>('power-money-precision').value)},priceType:node<HTMLInputElement>('power-price-type').value,timing:node<HTMLInputElement>('power-timing').value,holidayDates:node<HTMLTextAreaElement>('power-holiday-dates').value.split(/\r?\n/).map(v=>v.trim()).filter(Boolean),nonHolidays,holidays,numericalPolicy:catalog!.numericalPolicy});render(result);
  });};
  return {refresh(){if(current)render(current);},reset(){catalog=undefined;snapshotId='';nonHolidays='';holidays='';clearResult();form.reset();for(const id of ['power-curve','power-contract','power-product','power-normal-grid','power-holiday-grid'])node(id).replaceChildren();node('power-context').textContent='';form.hidden=true;node('power-guidance').hidden=false;},async load(){
    clearResult();const source=o.source();snapshotId=source.snapshotId;
    catalog=await o.api<Catalog>('power/catalog',{snapshotId});
    options('power-quantity-basis',[{value:'',label:'Choose quantity basis…'},...catalog.quantityChoices.map(q=>({value:quantityKey(q),label:q.label}))]);choice('power-quantity-basis').value='';choice('power-allocation').required=false;node('power-allocation-field').hidden=true;
    for(const kind of ['quantity','price','money'] as const)node<HTMLInputElement>(`power-${kind}-precision`).value=String(catalog.display[kind]);
    node('power-guidance').hidden=true;form.hidden=false;node('power-context').textContent=source.name;
    options('power-product',catalog.products.map(p=>({value:p.code,label:p.name})),'pjm');
    options('power-curve',catalog.curves.map(c=>({value:c.code,label:o.name(c.code)})),source.curve);
    contracts();applyPreset();
  }};
}
