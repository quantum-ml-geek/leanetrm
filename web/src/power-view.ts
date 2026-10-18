import {renderRegularTable} from './regular-table.js';
import {displayDate,friendly} from './market-view.js';

type Contract={id:string;from:string;to:string};
type Preset={product:string;block:string;minutes:number;nonHolidays:string;holidays:string;columns:{he:string;hb:string}[]};
type Choice={code:string;name:string};
type Product={code:string;name:string;version:number;clock:string};
type Catalog={classifications:{priceTypes:string[];timings:string[]};products:Product[];unavailableProducts:{code:string;name:string;reason:string}[];blocks:Choice[];intervals:number[];hourLabels:Choice[];presets:Preset[];curves:{code:string;holidayCalendar:string;contracts:Contract[]}[];weekdays:string[];numericalPolicy:string};
type Preview={holidays:string[];holidayCalendar:string;summary:{hours:string;energy:string;averagePrice:string;amount:string;policy:{implementation:string}};currency:string;mark:string;from:string;to:string;product:string;rows:{label:string;start:string;end:string;offsetMinutes:number;occurrence:number;holiday:boolean;price:string}[];days:{date:string;hours:string;intervals:number}[]};
type Options={api:<T>(path:string,body?:unknown)=>Promise<T>;act:(work:()=>Promise<void>)=>Promise<void>;source:()=>{snapshotId:string;curve:string;name:string};name:(code:string)=>string};
const node=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
function el<K extends keyof HTMLElementTagNameMap>(tag:K,text?:string){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
const choice=(id:string)=>node<HTMLSelectElement>(id);
function options(id:string,values:{value:string;label:string}[],selected?:string,placeholder?:string){const list=placeholder?[{value:'',label:placeholder},...values]:values;choice(id).replaceChildren(...list.map(v=>{const n=el('option',v.label);n.value=v.value;return n;}));choice(id).value=selected&&values.some(v=>v.value===selected)?selected:list[0]?.value??'';}

// Rendering and draft editing only. Membership, dates, prices, units and all
// arithmetic come from the authorized backend operation.
export function setupPowerView(o:Options){
  let catalog:Catalog|undefined,snapshotId='',nonHolidays='',holidays='';
  let current:Preview|undefined;
  const form=node<HTMLFormElement>('power-form');
  function clearResult(){current=undefined;node('power-result').hidden=true;}
  // Product, hours and grid are economic choices: they start unselected and are never assumed.
  function preset(){if(!catalog)throw Error('Load the power example first.');if(!choice('power-product').value||!choice('power-block').value||!choice('power-minutes').value)return undefined;const p=catalog.presets.find(p=>p.product===choice('power-product').value&&p.block===choice('power-block').value&&String(p.minutes)===choice('power-minutes').value);if(!p)throw Error('Choose a supported product and grid.');return p;}
  function grids(){
    if(!catalog)return;const p=preset(),ending=choice('power-labels').value==='HE';
    if(!p){for(const id of ['power-normal-grid','power-holiday-grid'])node(id).replaceChildren(el('p','Choose a product, hours and grid interval to edit the mask.'));return;}
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
  function applyPreset(){const p=preset();nonHolidays=p?.nonHolidays??'';holidays=p?.holidays??'';clearResult();grids();}
  function contracts(){const curve=catalog?.curves.find(c=>c.code===choice('power-curve').value);options('power-contract',curve?.contracts.map(c=>({value:c.id,label:`${c.from} → ${c.to} (end excluded)`}))??[],undefined,'Choose a delivery period…');node('power-holiday-calendar').textContent=curve?`${friendly(curve.holidayCalendar)} calendar · from the curve's settlement index`:'';clearResult();}
  function render(result:Preview){
    current=result;node('power-result').hidden=false;
    node('power-summary').textContent=`${result.summary.hours} hours · ${result.summary.energy} MWh · average ${result.summary.averagePrice} ${result.currency}/MWh · amount ${result.summary.amount} ${result.currency}`;
    node('power-holiday-note').textContent=`Holidays from the ${friendly(result.holidayCalendar)} calendar: ${result.holidays.length?result.holidays.map(displayDate).join(', '):'none in this period'}.`;
    node('power-price-note').textContent=`${result.product}. Flat ${result.mark} ${result.currency}/MWh from the selected curve contract. Generated test fixings; no market data saved. The curve's stored product terms are unchanged.`;
    const scope=JSON.stringify([snapshotId,choice('power-curve').value,choice('power-contract').value,choice('power-product').value,choice('power-block').value,nonHolidays,holidays]);
    renderRegularTable(node('power-days'),'power-days',scope,['Operating date','Hours','Intervals'],result.days.map(d=>[d.date,d.hours,String(d.intervals)]),[1,2],()=>document.body.getAttribute('aria-busy')==='true');
    const rows=choice('power-show').value==='all'?result.rows:result.rows.slice(0,60);
    renderRegularTable(node('power-intervals'),'power-intervals',scope,['Market interval','Start · UTC','End · UTC','UTC offset · minutes','Occurrence','Holiday','Test price'],rows.map(r=>[r.label,r.start,r.end,String(r.offsetMinutes),String(r.occurrence),r.holiday?'Yes':'No',r.price]),[3,4,6],()=>document.body.getAttribute('aria-busy')==='true');
    node('power-rows-note').textContent=rows.length===result.rows.length?'All selected intervals.':'First 60 intervals. Choose Show all to inspect the complete period.';
  }
  for(const id of ['power-product','power-block','power-minutes'])choice(id).onchange=applyPreset;
  choice('power-labels').onchange=()=>{clearResult();grids();};
  choice('power-curve').onchange=contracts;
  choice('power-contract').onchange=clearResult;
  choice('power-show').onchange=()=>{if(current)render(current);};
  for(const id of ['power-mw','power-price-type','power-timing'])node(id).addEventListener('input',clearResult);
  form.onsubmit=event=>{event.preventDefault();void o.act(async()=>{
    clearResult();if(!preset())throw Error('Choose a product, hours and grid interval.');
    const result=await o.api<Preview>('power/preview',{snapshotId,curve:choice('power-curve').value,contractId:choice('power-contract').value,product:choice('power-product').value,productVersion:catalog!.products.find(p=>p.code===choice('power-product').value)!.version,block:choice('power-block').value,minutes:Number(choice('power-minutes').value),hourLabels:choice('power-labels').value,megawatts:node<HTMLInputElement>('power-mw').value,priceType:node<HTMLInputElement>('power-price-type').value,timing:node<HTMLInputElement>('power-timing').value,nonHolidays,holidays,numericalPolicy:catalog!.numericalPolicy});render(result);
  });};
  return {reset(){catalog=undefined;snapshotId='';clearResult();form.hidden=true;node('power-guidance').hidden=false;},async load(){
    clearResult();const source=o.source();snapshotId=source.snapshotId;
    catalog=await o.api<Catalog>('power/catalog',{snapshotId});
    node('power-guidance').hidden=true;form.hidden=false;node('power-context').textContent=`Market date: ${source.name}`;
    options('power-product',catalog.products.map(p=>({value:p.code,label:`${p.name} · ${p.code} v${p.version}`})),undefined,'Choose a product…');
    node('power-unavailable').textContent=catalog.unavailableProducts.map(p=>`${p.name} (${p.code}) is unavailable: ${p.reason}`).join(' ');node('power-unavailable').hidden=!catalog.unavailableProducts.length;
    options('power-block',catalog.blocks.map(b=>({value:b.code,label:b.name})),undefined,'Choose hours…');
    options('power-minutes',catalog.intervals.map(m=>({value:String(m),label:m===60?'Hourly':`${m} minutes`})),undefined,'Choose an interval…');
    options('power-labels',catalog.hourLabels.map(h=>({value:h.code,label:h.name})));
    for(const [id,list] of [['power-price-types',catalog.classifications.priceTypes],['power-timings',catalog.classifications.timings]] as const)node(id).replaceChildren(...list.map(v=>{const n=el('option');n.value=v;return n;}));
    options('power-curve',catalog.curves.map(c=>({value:c.code,label:o.name(c.code)})),source.curve,catalog.curves.some(c=>c.code===source.curve)?undefined:'Choose a power curve…');
    contracts();applyPreset();
  }};
}
